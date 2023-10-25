#include <filesystem>
#include <vector>
#include <fstream>
#include <list>
#include <map>
#include <sys/stat.h>
#include "Toastbox/FileDescriptor.h"
#include "Toastbox/RuntimeError.h"
#include "Toastbox/Mmap.h"
#include "Toastbox/NumForStr.h"

// RecordStore: a persistent data structure designed with the following properties:
//          storage amount: many gigabytes of data
//             data format: data is stored as individual records, where each record follows a common templated schema (T_Record)
//     data access pattern: records are optimally added to the end of the store, and removed from the beginning of the store;
//                          random-removal is supported and does not move or affect adjacent records;
//                          the space of a randomly-deleted record is not recovered until chunk compaction occurs (currently unimplemented)
//               threading: data can be written from one thread and read from another thread in parallel

template <
typename T_Record,      // The type of the records
size_t T_ChunkRecordCap // Max number of records per chunk
>
struct RecordStore {
    static constexpr uint32_t Version = T_Record::Version;
    static constexpr uint32_t ChunkRecordCap = T_ChunkRecordCap;
    
    using Path = std::filesystem::path;
    using Record = T_Record;
    
    using ChunkId = uint64_t;
    
    struct Chunk {
        Chunk(ChunkId id, Toastbox::Mmap&& mmap) : id(id), mmap(std::move(mmap)) {}
        ChunkId id = 0;                         // Id of the chunk
        size_t recordCount = 0;                 // Count of records currently stored in chunk
        size_t recordIdx = 0;                   // Index of next record
        std::atomic<size_t> strongCount = 0;    // Count of RecordStrongRef's that currently refer to this chunk
        std::atomic<bool> alive = true;         // Whether the chunk is still alive
        Toastbox::Mmap mmap;
    };
    
    using Chunks = std::list<Chunk>;
    
    // ChunkRef: a reference to a mmap'd chunk
    // ChunkRef may be invalidated after the store is written (via write()) because
    // the Chunk may have been deleted (if it no longer contained records).
    // Use ChunkStrongRef if you need a ChunkRef to stay valid across store writes.
    struct ChunkRef {
        Chunk* chunk = nullptr;
        
        bool operator<(const ChunkRef& x) const {
            if (chunk != x.chunk) return chunk->id < x.chunk->id;
            return false;
        }
        
        bool operator==(const ChunkRef& x) const {
            if (chunk != x.chunk) return false;
            return true;
        }
        
        bool operator!=(const ChunkRef& x) const { return !(*this == x); }
        
        explicit operator bool() const { return chunk; }
        
        Chunk* operator->() const { return &get(); }
        Chunk& operator*() const { return get(); }
        Chunk& get() const { return *chunk; }
    };
    
    // ChunkStrongRef: a strong reference to a mmap'd chunk, which keeps the chunk alive
    // across store writes (via write()).
    // This is useful if multiple threads access the store (with appropriate locking), and one thread needs
    // to ensure that the chunk that it references stays alive while other threads modify the store.
    struct ChunkStrongRef : ChunkRef {
        ChunkStrongRef() {}
        ChunkStrongRef(ChunkRef ref) { _set(ref); }
        
        // Copy
        ChunkStrongRef(const ChunkStrongRef& x) { _set(x); }
        ChunkStrongRef& operator=(const ChunkStrongRef& x) { _set(x); return *this; }
        // Move
        ChunkStrongRef(ChunkStrongRef&& x) { _swap(x); }
        ChunkStrongRef& operator=(ChunkStrongRef&& x) { _swap(x); return *this; }
        ~ChunkStrongRef() { _set({}); }
        
        void _set(const ChunkRef& ref) {
            if (ref.chunk) ref.chunk->strongCount++;
            if (ChunkRef::chunk) ChunkRef::chunk->strongCount--;
            static_cast<ChunkRef&>(*this) = ref;
        }
        
        void _swap(ChunkStrongRef& ref) {
            std::swap(static_cast<ChunkRef&>(*this), static_cast<ChunkRef&>(ref));
        }
    };
    
    template <typename T_ChunkRef>
    struct _RecordRef : T_ChunkRef {
        size_t idx = 0;
        
        _RecordRef() {}
        _RecordRef(const T_ChunkRef& chunk, size_t idx) : T_ChunkRef(chunk), idx(idx) {}
        
//        using T_ChunkRef::T_ChunkRef;
        const T_ChunkRef& chunkRef() const { return *this; }
        
        // alive(): whether the RecordRef is part of a chunk that's still alive.
        bool alive() const { return chunkRef().chunk->alive; }
        
        template <typename T>
        bool operator<(const T& x) const {
            if (chunkRef() != x.chunkRef()) return chunkRef() < x.chunkRef();
            if (idx != x.idx)               return idx < x.idx;
            return false;
        }
        
        template <typename T>
        bool operator==(const T& x) const {
            if (chunkRef() != x.chunkRef()) return false;
            if (idx != x.idx)               return false;
            return true;
        }
        
        template <typename T>
        bool operator!=(const T& x) const { return !(*this == x); }
        
        T_Record* operator->() const { return &record(); }
        T_Record& operator*() const { return record(); }
        T_Record& record() const {
            return *(T_Record*)chunkRef().chunk->mmap.data(idx*sizeof(T_Record), sizeof(T_Record));
        }
    };
    
    // RecordRef: a reference to a record
    // RecordRefs may be invalidated after the store is written (via write()) because
    // the Chunk may have been compacted or deleted entirely (if it no longer contained records).
    // Use RecordStrongRef if you need a RecordRef to stay valid across store writes.
    struct RecordRef : _RecordRef<ChunkRef> {
        using _RecordRef<ChunkRef>::_RecordRef;
    };
    
    // RecordStrongRef: a strong reference to a record, which keeps the record's backing data alive
    // across record removals (via remove()) and store writes (via write()). This is useful if
    // multiple threads access the store (with appropriate locking), and one thread needs to ensure
    // that the data that it references stays alive while other threads modify the store.
    struct RecordStrongRef : _RecordRef<ChunkStrongRef> {
        RecordStrongRef() {}
        RecordStrongRef(const RecordRef& ref) : _RecordRef<ChunkStrongRef>(ref, ref.idx) {}
        operator const RecordRef() const {
            return RecordRef(*this, this->idx);
        }
    };
    
    using RecordRefs = std::vector<RecordRef>;
    using RecordRefConstIter = typename RecordRefs::const_iterator;
    using RecordRefConstReverseIter = typename RecordRefs::const_reverse_iterator;
    
    struct _State {
        ChunkId chunkId = 0;
        RecordRefs recordRefs;
        Chunks chunks;
    };
    
    // Find(): find `ref` between [begin,end)
    // T_Ascending=false must be specified when reverse iterators are given.
    template<bool T_Ascending=true, typename T>
    static T Find(T begin, T end, const RecordRef& ref) {
        T it = std::lower_bound(begin, end, 0,
            [&](const RecordRef& sample, auto) -> bool {
                return (T_Ascending ? sample<ref : ref<sample);
            });
        
        if (it == end) return end;
        if (*it != ref) return end;
        return it;
    }
    
    // FindChunkBegin(): finds the iterator for the beginning of iter's chunk
    template<typename T>
    static T FindChunkBegin(T begin, T iter) {
        if (iter == begin) return begin;
        const ChunkRef iterChunk = *iter;
        return std::lower_bound(begin, iter, 0,
            [&](const ChunkRef& sample, auto) -> bool {
                return sample != iterChunk;
            });
    }
    
    // FindChunkEnd(): finds the iterator for the end (last+1) of iter's chunk
    template<typename T>
    static T FindChunkEnd(T end, T iter) {
        if (iter == end) return end;
        const ChunkRef iterChunk = *iter;
        return std::lower_bound(iter, end, 0,
            [&](const ChunkRef& sample, auto) -> bool {
                return sample == iterChunk;
            });
    }
    
    std::ifstream read(Path path) {
        _path = path;
        std::filesystem::create_directories(_ChunksPath(_path));
        return _StateRead(_path, _state);
    }
    
    std::ofstream write() {
        namespace fs = std::filesystem;
        
        #warning TODO: implement optional 'thorough compaction' (based on argument) to shift records in order to compact chunks into the smallest size possible. skip compaction for chunks with outstanding strong references though (Chunk.strongCount), because the strong references need the addresses to remain constant!
        
        // Ensure that all chunks are written to disk
        for (const Chunk& chunk : _state.chunks) {
            if (chunk.alive) chunk.mmap.sync();
        }
        
        // Prune chunks (in memory) that have 0 records and 0 strong references
        {
            _state.chunks.remove_if([] (const Chunk& chunk) {
                return chunk.recordCount==0 && chunk.strongCount==0;
            });
        }
        
        // Perform 'trivial compaction': truncate each chunk to its last record (according to chunk.recordIdx)
        {
            for (Chunk& chunk : _state.chunks) {
                chunk.mmap.len(chunk.recordIdx * sizeof(T_Record));
            }
        }
        
        // Delete unused chunk files
        {
            std::set<ChunkId> aliveChunks;
            for (Chunk& chunk : _state.chunks) {
                if (chunk.alive) aliveChunks.insert(chunk.id);
            }
            
            for (const fs::path& p : fs::directory_iterator(_ChunksPath(_path))) {
                // Delete the chunk file if it's beyond the new count of chunks (therefore
                // it's an old chunk file that's no longer needed).
                std::optional<ChunkId> deleteName;
                try {
                    deleteName = Toastbox::IntForStr<ChunkId>(p.filename().string());
                    if (aliveChunks.find(*deleteName) != aliveChunks.end()) {
                        deleteName = std::nullopt; // Chunk file is in use; don't delete it
                    }
                // Don't do anything if we can't convert the filename to an integer;
                // assume the file is supposed to be there.
                } catch (...) {}
                
                if (deleteName) {
                    printf("[RecordStore::write()] deleting chunk file %ju\n", (uintmax_t)*deleteName);
                    fs::remove(_chunkPath(*deleteName));
                }
            }
        }
        
        return _StateWrite(_path, _state);
    }
    
    // add(): adds records to the end
    void add(size_t count) {
        _state.recordRefs.resize(_state.recordRefs.size()+count);
        for (auto it=_state.recordRefs.end()-count; it!=_state.recordRefs.end(); it++) {
            RecordRef& ref = *it;
            Chunk& chunk = _chunkGetWritable();
            ref.chunk = &chunk;
            ref.idx = chunk.recordIdx;
            chunk.recordCount++;
            chunk.recordIdx++;
        }
    }
    
    void remove(RecordRefConstIter begin, RecordRefConstIter end) {
        for (auto it=begin; it!=end; it++) {
            Chunk& chunk = const_cast<Chunk&>(*it->chunk);
            chunk.recordCount--;
        }
        
        _state.recordRefs.erase(begin, end);
    }
    
    void clear() {
        for (Chunk& chunk : _state.chunks) {
            chunk.recordCount = 0;
            chunk.alive = false;
        }
        
        _state.recordRefs.clear();
    }
    
    bool empty() const { return _state.recordRefs.empty(); }
    
    const RecordRef& front() const              { return _state.recordRefs.front(); }
    const RecordRef& back() const               { return _state.recordRefs.back(); }
    RecordRefConstIter begin() const            { return _state.recordRefs.begin(); }
    RecordRefConstIter end() const              { return _state.recordRefs.end(); }
    RecordRefConstReverseIter rbegin() const    { return _state.recordRefs.rbegin(); }
    RecordRefConstReverseIter rend() const      { return _state.recordRefs.rend(); }
    
    size_t recordCount() const {
        return _state.recordRefs.size();
    }
    
    struct [[gnu::packed]] _SerializedHeader {
        uint32_t version     = 0; // Version
        uint32_t recordSize  = 0; // sizeof(T_Record)
        uint32_t recordCount = 0; // Count of RecordRef structs in Index file
    };
    
    struct [[gnu::packed]] _SerializedRecordRef {
        uint64_t chunkId = 0;
        uint32_t idx = 0;
        
        // Make sure the type of `chunkId` matches ChunkId
        static_assert(std::is_same_v<decltype(chunkId), ChunkId>);
    };
    
    static constexpr size_t _ChunkLen = sizeof(T_Record)*T_ChunkRecordCap;
    
    static std::ifstream _StateRead(const Path& path, _State& state) {
        try {
            state = {};
            
            std::ifstream f;
            f.exceptions(std::ofstream::failbit | std::ofstream::badbit);
            f.open(_IndexPath(path));
            
            _SerializedHeader header;
            f.read((char*)&header, sizeof(header));
            
            if (header.version != Version) {
                throw Toastbox::RuntimeError("invalid header version (expected: 0x%jx, got: 0x%jx)",
                    (uintmax_t)Version,
                    (uintmax_t)header.version
                );
            }
            
            if (header.recordSize != sizeof(T_Record)) {
                throw Toastbox::RuntimeError("record size mismatch (expected: %ju, got: %ju)",
                    (uintmax_t)sizeof(T_Record), (uintmax_t)header.recordSize);
            }
            
            // Create RecordRefs
            state.recordRefs.resize(header.recordCount);
            
            std::map<ChunkId,Chunk*> chunksMap;
            std::optional<ChunkId> chunkIdPrev;
            std::optional<size_t> idxPrev;
            for (size_t i=0; i<header.recordCount; i++) {
                _SerializedRecordRef ref;
                f.read((char*)&ref, sizeof(ref));
                
                const ChunkId chunkId = ref.chunkId;
                
                // Verify that chunkId's are monotonically increasing
                
                if (chunkIdPrev) {
                    if (!(chunkId >= *chunkIdPrev)) {
                        throw Toastbox::RuntimeError("chunk ids aren't monotonically increasing (previous id: %ju, current id: %ju)",
                            (uintmax_t)(*chunkIdPrev),
                            (uintmax_t)(chunkId)
                        );
                    }
                }
                
                if (chunkIdPrev && idxPrev && chunkId==*chunkIdPrev) {
                    if (!(ref.idx > *idxPrev)) {
                        throw Toastbox::RuntimeError("record indexes aren't monotonically increasing (previous index: %ju, current index: %ju)",
                            (uintmax_t)(*idxPrev),
                            (uintmax_t)(ref.idx)
                        );
                    }
                }
                
                Chunk*& chunk = chunksMap[chunkId];
                if (!chunk) chunk = &state.chunks.emplace_back(chunkId, _ChunkFileOpen(_ChunkPath(path, chunkId)));
                
                if (sizeof(T_Record)*(ref.idx+1) > chunk->mmap.len()) {
                    throw Toastbox::RuntimeError("RecordRef extends beyond chunk (RecordRef end: 0x%jx, chunk end: 0x%jx)",
                        (uintmax_t)(sizeof(T_Record)*(ref.idx+1)),
                        (uintmax_t)chunk->mmap.len()
                    );
                }
                
                state.recordRefs[i].chunk = chunk;
                state.recordRefs[i].idx = ref.idx;
                
                chunk->recordCount++;
                chunk->recordIdx = ref.idx+1;
                
                chunkIdPrev = chunkId;
                idxPrev = ref.idx;
            }
            
            // Set state.chunkId to the last chunkId we encountered + 1
            state.chunkId = (chunkIdPrev ? *chunkIdPrev+1 : 0);
            return f;
        
        } catch (...) {
            state = {};
            throw;
        }
    }
    
    static std::ofstream _StateWrite(const Path& path, const _State& state) {
        std::ofstream f;
        f.exceptions(std::ofstream::failbit | std::ofstream::badbit);
        f.open(_IndexPath(path));
        
        // Write header
        const _SerializedHeader header = {
            .version     = Version,
            .recordSize  = (uint32_t)sizeof(T_Record),
            .recordCount = (uint32_t)state.recordRefs.size(),
        };
        f.write((char*)&header, sizeof(header));
        
        // Write RecordRefs
        for (const RecordRef& ref : state.recordRefs) {
            const _SerializedRecordRef sref = {
                .chunkId = ref.chunk->id,
                .idx = (uint32_t)ref.idx,
            };
            f.write((const char*)&sref, sizeof(sref));
        }
        
        return f;
    }
    
    static Path _IndexPath(const Path& path) {
        return path / "Index";
    }
    
    static Path _ChunksPath(const Path& path) {
        return path / "Chunks";
    }
    
    static Path _ChunkPath(const Path& path, ChunkId id) {
        return _ChunksPath(path) / std::to_string(id);
    }
    
    static Toastbox::Mmap _ChunkFileCreate(const Path& path) {
        constexpr int ChunkPerm = (S_IRUSR|S_IWUSR) | (S_IRGRP) | (S_IROTH);
        const int fd = open(path.c_str(), O_RDWR|O_CREAT|O_CLOEXEC, ChunkPerm);
        if (fd < 0) throw Toastbox::RuntimeError("failed to create chunk file: %s", strerror(errno));
        const size_t cap = Toastbox::Mmap::PageCeil(_ChunkLen);
        return Toastbox::Mmap(fd, cap, MAP_SHARED);
    }
    
    static Toastbox::Mmap _ChunkFileOpen(const Path& path) {
        int fdi = open(path.c_str(), O_RDWR);
        if (fdi < 0) throw Toastbox::RuntimeError("open failed: %s", strerror(errno));
        Toastbox::FileDescriptor fd(fdi);
        
        // Determine file size
        struct stat st;
        int ir = fstat(fd, &st);
        if (ir) throw Toastbox::RuntimeError("fstat failed: %s", strerror(errno));
        // Create the mapping with a capacity of either the file size or _ChunkLen, whichever is larger.
        const size_t cap = Toastbox::Mmap::PageCeil(std::max((size_t)st.st_size, _ChunkLen));
        return Toastbox::Mmap(std::move(fd), cap, MAP_SHARED);
    }
    
    Path _chunkPath(ChunkId id) const {
        return _ChunkPath(_path, id);
    }
    
    Chunk& _chunkCreate() {
        const ChunkId chunkId = _state.chunkId++;
        return _state.chunks.emplace_back(chunkId, _ChunkFileCreate(_chunkPath(chunkId)));
    }
    
    Chunk& _chunkGetWritable() {
        Chunk* chunk = nullptr;
        auto last = std::prev(_state.chunks.end());
        if (last==_state.chunks.end() || (last->recordIdx>=T_ChunkRecordCap || !last->alive)) {
            // We don't have any chunks, the last chunk is full, or the last chunk is dead;
            // create a new chunk
            chunk = &_chunkCreate();
        
        } else {
            // The last chunk can fit more records
            chunk = &(*last);
        }
        
        // Resize the chunk file to be a full chunk, in case it wasn't already.
        // Currently, _ChunkFileCreate() creates 0-byte chunk files, so we set their size here.
        // In the future, when we implement compaction, chunks could have arbitrary sizes, making it
        // doubly necessary to set the file size here.
        chunk->mmap.len(_ChunkLen);
        return *chunk;
    }
    
    Path _path;
    _State _state;
};
