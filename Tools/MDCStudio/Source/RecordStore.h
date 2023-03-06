#include <filesystem>
#include <vector>
#include <fstream>
#include <list>
#include <sys/stat.h>
#include "Toastbox/FileDescriptor.h"
#include "Toastbox/RuntimeError.h"
#include "Toastbox/Mmap.h"
#include "Toastbox/IntForStr.h"

template <
    typename T_Record,
    size_t T_ChunkRecordCap // Max number of records per chunk
>
class RecordStore {
public:
    static constexpr uint32_t Version = T_Record::Version;
    static constexpr uint32_t ChunkRecordCap = T_ChunkRecordCap;
    
    using Path = std::filesystem::path;
    using Record = T_Record;
    
    class Chunk {
    public:
        Chunk(size_t order, Toastbox::Mmap&& mmap) : order(order), mmap(std::move(mmap)) {}
        size_t order = 0;                       // Order of the chunk, so that RecordRefs can order themselves
        size_t recordCount = 0;                 // Count of records currently stored in chunk
        size_t recordIdx = 0;                   // Index of next record
        std::atomic<size_t> strongCount = 0;    // Count of RecordStrongRef's that currently refer to this chunk
        Toastbox::Mmap mmap;
    };
    
    using Chunks = std::list<Chunk>;
    
    class RecordRef {
    public:
        Chunk* chunk = nullptr;
        size_t idx = 0;
        
        bool operator<(const RecordRef& x) const {
            if (chunk != x.chunk)   return chunk->order < x.chunk->order;
            if (idx != x.idx)       return idx < x.idx;
            return false;
        }
        
        bool operator==(const RecordRef& x) const {
            if (chunk != x.chunk)   return false;
            if (idx != x.idx)       return false;
            return true;
        }
        
        operator bool() const { return chunk; }
        T_Record* operator->() const { return &record(); }
        T_Record& operator*() const { return record(); }
        T_Record& record() const {
            return *(T_Record*)chunk->mmap.data(idx*sizeof(T_Record), sizeof(T_Record));
        }
    };
    
    class RecordStrongRef : public RecordRef {
    public:
        RecordStrongRef() {}
        RecordStrongRef(RecordRef ref) { _set(ref); }
        
        // Copy
        RecordStrongRef(const RecordStrongRef& x) { _set(x); }
        RecordStrongRef& operator=(const RecordStrongRef& x) { _set(x); return *this; }
        // Move
        RecordStrongRef(RecordStrongRef&& x) { _swap(x); }
        RecordStrongRef& operator=(RecordStrongRef&& x) { _swap(x); return *this; }
        ~RecordStrongRef() { _set({}); }
        
    private:
        void _set(const RecordRef& ref) {
            if (ref.chunk) ref.chunk->strongCount++;
            if (RecordRef::chunk) RecordRef::chunk->strongCount--;
            static_cast<RecordRef&>(*this) = ref;
        }
        
        void _swap(RecordStrongRef& ref) {
            std::swap(static_cast<RecordRef&>(*this), static_cast<RecordRef&>(ref));
        }
    };
    
    
//    class RecordStrongRef {
//    public:
//        RecordStrongRef() {}
//        RecordStrongRef(RecordRef ref) { _set(ref); }
//        
//        // Copy
//        RecordStrongRef(const RecordStrongRef& x) { _set(x._ref); }
//        RecordStrongRef& operator=(const RecordStrongRef& x) { _set(x._ref); return *this; }
//        // Move
//        RecordStrongRef(RecordStrongRef&& x) { _swap(x._ref); }
//        RecordStrongRef& operator=(RecordStrongRef&& x) { _swap(x._ref); return *this; }
//        ~RecordStrongRef() { _set({}); }
//        
//        operator bool() const { return _ref; }
//        T_Record* operator->() const { return &_ref.record(); }
//        T_Record& operator*() const { return _ref.record(); }
//        T_Record& record() const { _ref.record(); }
//        
//    private:
//        void _set(const RecordRef& ref) {
//            if (ref.chunk) ref.chunk->strongCount++;
//            if (_ref.chunk) _ref.chunk->strongCount--;
//            _ref = ref;
//        }
//        
//        void _swap(RecordRef& ref) {
//            std::swap(_ref, ref);
//        }
//        
//        RecordRef _ref;
//    };
    
    using RecordRefs = std::vector<RecordRef>;
    using RecordRefConstIter = typename RecordRefs::const_iterator;
    using RecordRefConstReverseIter = typename RecordRefs::const_reverse_iterator;
    
    // FindNextChunk(): finds the first RecordRef for the next chunk after the given RecordRef's chunk
    static RecordRefConstIter FindNextChunk(RecordRefConstIter iter, RecordRefConstIter end) {
        if (iter == end) return end;
        const Chunk*const startChunk = iter->chunk;
        
        return std::lower_bound(iter, end, 0,
            [&](const RecordRef& sample, auto) -> bool {
                if (sample.chunk == startChunk) {
                    // If `sample`'s chunk is the same chunk as `iter`,
                    // then `sample` is less than the target
                    return true;
                }
                
                // Otherwise, `sample`'s chunk is neither the same chunk as `iter`,
                // nor the target chunk, so it's greater than the target
                return false;
            });
    }
    
    RecordStore(const Path& path) : _path(path) {}
    
    std::ifstream read() {
        // Reset ourself in case an exception occurs later
        _state = {};
        
        std::filesystem::create_directories(_ChunksPath(_path));
        
        auto [recordRefs, chunks, f] = _IndexRead(_path);
        // If we get here, everything succeeded so we can use the on-disk database
        _state.recordRefs = recordRefs;
        _state.chunks = std::move(chunks);
        return std::move(f);
    }
    
    std::ofstream write() {
        namespace fs = std::filesystem;
        
        // Prohibit syncing between reserve() / add() calls.
        // This isn't allowed because _state.reserved may be referencing chunks whose recordCount==0,
        // and those chunks get deleted below. When add() is called to commit the reserved records,
        // recordCount will be incremented appropriately and sync() can be called safely.
        #warning TODO: we could actually save between reserve() / add() calls, as long as we don't perform the chunk removal. this would be useful if the main thread removes images (and saves after removing them) while the background thread adds images
        assert(_state.reserved.empty());
        
        #warning TODO: implement optional 'thorough compaction' (based on argument) to shift records in order to compact chunks into the smallest size possible. skip compaction for chunks with outstanding strong references though (Chunk.strongCount), because the strong references need the addresses to remain constant!
        
        // Ensure that all chunks are written to disk
        for (const Chunk& chunk : _state.chunks) {
            chunk.mmap.sync();
        }
        
        // Rename chunk filenames to be in the range [0,chunkCount)
        // This needs to happen before we prune empty chunks! Otherwise we won't know the `oldName`,
        // since it depends on a chunk's index in `_state.chunks`
        {
            size_t oldName = 0;
            size_t newName = 0;
            for (const Chunk& chunk : _state.chunks) {
                if (chunk.recordCount) {
                    if (newName != oldName) {
                        fs::rename(_chunkPath(oldName), _chunkPath(newName));
                    }
                    newName++;
                }
                oldName++;
            }
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
        
        // Delete unreferenced chunk files
        for (const fs::path& p : fs::directory_iterator(_ChunksPath(_path))) {
            // Delete the chunk file if it's beyond the new count of chunks (therefore
            // it's an old chunk file that's no longer needed).
            std::optional<size_t> deleteName;
            try {
                deleteName = Toastbox::IntForStr<size_t>(p.filename().string());
                if (*deleteName < _state.chunks.size()) {
                    deleteName = std::nullopt; // Chunk file is in-range; don't delete it
                }
            // Don't do anything if we can't convert the filename to an integer;
            // assume the file is supposed to be there.
            } catch (...) {}
            
            if (deleteName) {
                fs::remove(_chunkPath(*deleteName));
            }
        }
        
        return _IndexWrite(_path, _state.recordRefs, _state.chunks);
    }
    
    // reserve(): reserves space for `count` additional records, but does not actually add them
    // to the store. add() must be called after reserve() to add the records to the store.
    void reserve(size_t count) {
        assert(_state.reserved.empty());
        _state.reserved.resize(count);
        
        for (RecordRef& ref : _state.reserved) {
            Chunk& chunk = _chunkGetWritable();
            
            ref = {
                .chunk = &chunk,
                .idx = chunk.recordIdx,
            };
            
            chunk.recordIdx++;
        }
    }
    
    // add(): adds the records previously reserved via reserve()
    void add() {
        for (auto it=_state.reserved.begin(); it!=_state.reserved.end(); it++) {
            Chunk& chunk = const_cast<Chunk&>(*it->chunk);
            chunk.recordCount++;
        }
        
        _state.recordRefs.insert(_state.recordRefs.end(), _state.reserved.begin(), _state.reserved.end());
        _state.reserved.clear();
    }
    
    void remove(RecordRefConstIter begin, RecordRefConstIter end) {
        for (auto it=begin; it!=end; it++) {
            Chunk& chunk = const_cast<Chunk&>(*it->chunk);
            chunk.recordCount--;
        }
        
        _state.recordRefs.erase(begin, end);
    }
    
    bool empty() const { return _state.recordRefs.empty(); }
    
    RecordRefConstIter find(const RecordRef& ref) const {
        RecordRefConstIter it = std::lower_bound(begin(), end(), 0,
            [&](const RecordRef& sample, auto) -> bool {
                return sample < ref;
            });
        
        if (it == end()) return end();
        if (*it != ref) return end();
        return it;
    }
    
    const RecordRef& front() const              { return _state.recordRefs.front(); }
    const RecordRef& back() const               { return _state.recordRefs.back(); }
    RecordRefConstIter begin() const            { return _state.recordRefs.begin(); }
    RecordRefConstIter end() const              { return _state.recordRefs.end(); }
    RecordRefConstReverseIter rbegin() const    { return _state.recordRefs.rbegin(); }
    RecordRefConstReverseIter rend() const      { return _state.recordRefs.rend(); }
    
    const RecordRef& reservedFront() const              { return _state.reserved.front(); }
    const RecordRef& reservedBack() const               { return _state.reserved.back(); }
    RecordRefConstIter reservedBegin() const            { return _state.reserved.begin(); }
    RecordRefConstIter reservedEnd() const              { return _state.reserved.end(); }
    RecordRefConstReverseIter reservedRBegin() const    { return _state.reserved.rbegin(); }
    RecordRefConstReverseIter reservedREnd() const      { return _state.reserved.rend(); }
    
    size_t recordCount() const {
        return _state.recordRefs.size();
    }
    
private:
    struct [[gnu::packed]] _SerializedHeader {
        uint32_t version     = 0; // Version
        uint32_t recordSize  = 0; // sizeof(T_Record)
        uint32_t recordCount = 0; // Count of RecordRef structs in Index file
        uint32_t chunkCount  = 0; // Count of _Chunk structs in Index file
    };
    
    struct [[gnu::packed]] _SerializedRecordRef {
        uint32_t chunkIdx = 0;
        uint32_t idx = 0;
    };
    
    static constexpr size_t _ChunkLen = sizeof(T_Record)*T_ChunkRecordCap;
    
    static std::tuple<RecordRefs,Chunks,std::ifstream> _IndexRead(const Path& path) {
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
        
        // Create and map in each chunk
        std::list<Chunk> chunks;
        std::vector<Chunk*> chunksVec;
        for (size_t i=0; i<header.chunkCount; i++) {
            Chunk& chunk = _ChunkPush(chunks, _ChunkFileOpen(_ChunkPath(path, i)));
            chunksVec.push_back(&chunk);
        }
        
        // Create RecordRefs
        RecordRefs recordRefs;
        recordRefs.resize(header.recordCount);
        
        std::optional<size_t> chunkIdxPrev;
        std::optional<size_t> idxPrev;
        for (size_t i=0; i<header.recordCount; i++) {
            _SerializedRecordRef ref;
            f.read((char*)&ref, sizeof(ref));
            
            const size_t chunkIdx = ref.chunkIdx;
            Chunk& chunk = *chunksVec.at(chunkIdx);
            
            if (sizeof(T_Record)*(ref.idx+1) > chunk.mmap.len()) {
                throw Toastbox::RuntimeError("RecordRef extends beyond chunk (RecordRef end: 0x%jx, chunk end: 0x%jx)",
                    (uintmax_t)(sizeof(T_Record)*ref.idx),
                    (uintmax_t)chunk.mmap.len()
                );
            }
            
            if ((chunkIdxPrev && idxPrev) && (chunkIdx==*chunkIdxPrev && ref.idx<=*idxPrev)) {
                throw Toastbox::RuntimeError("record indexes aren't monotonically increasing (previous index: %ju, current index: %ju)",
                    (uintmax_t)(*idxPrev),
                    (uintmax_t)(ref.idx)
                );
            }
            
            recordRefs[i] = {
                .chunk = chunksVec.at(ref.chunkIdx),
                .idx = ref.idx,
            };
            
            chunk.recordCount++;
            chunk.recordIdx = ref.idx+1;
            
            chunkIdxPrev = chunkIdx;
            idxPrev = ref.idx;
        }
        
        return std::make_tuple(recordRefs, std::move(chunks), std::move(f));
    }
    
    static std::ofstream _IndexWrite(const Path& path, const RecordRefs& recordRefs, const Chunks& chunks) {
        std::ofstream f;
        f.exceptions(std::ofstream::failbit | std::ofstream::badbit);
        f.open(_IndexPath(path));
        
        // Write header
        const _SerializedHeader header = {
            .version     = Version,
            .recordSize  = (uint32_t)sizeof(T_Record),
            .recordCount = (uint32_t)recordRefs.size(),
            .chunkCount  = (uint32_t)chunks.size(),
        };
        f.write((char*)&header, sizeof(header));
        
        // Write RecordRefs
        Chunk* chunkPrev = nullptr;
        uint32_t chunkIdx = 0;
        for (const RecordRef& ref : recordRefs) {
            if (chunkPrev && ref.chunk!=chunkPrev) chunkIdx++;
            
            const _SerializedRecordRef sref = {
                .chunkIdx = chunkIdx,
                .idx = (uint32_t)ref.idx,
            };
            f.write((const char*)&sref, sizeof(sref));
            
            chunkPrev = ref.chunk;
        }
        
        return f;
    }
    
    static Path _IndexPath(const Path& path) {
        return path / "Index";
    }
    
    static Path _ChunksPath(const Path& path) {
        return path / "Chunks";
    }
    
    static Path _ChunkPath(const Path& path, size_t idx) {
        return _ChunksPath(path) / std::to_string(idx);
    }
    
    Path _chunkPath(size_t idx) const {
        return _ChunkPath(_path, idx);
    }
    
    static Chunk& _ChunkPush(std::list<Chunk>& chunks, Toastbox::Mmap&& mmap) {
        const size_t order = (chunks.empty() ? 0 : chunks.back().order+1);
        return chunks.emplace_back(order, std::move(mmap));
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
    
    Chunk& _chunkGetWritable() {
        auto lastChunk = std::prev(_state.chunks.end());
        if (lastChunk==_state.chunks.end() || lastChunk->recordIdx>=T_ChunkRecordCap) {
            // We don't have any chunks, or the last chunk is full
            // Create a new chunk
            return _ChunkPush(_state.chunks, _ChunkFileCreate(_chunkPath(_state.chunks.size())));
        
        } else {
            // The last chunk can fit more records
            // Resize the chunk file to be a full chunk, in case it wasn't already.
            // Currently, _ChunkFileCreate() creates 0-byte chunk files, so we set their size here.
            // In the future, when we implement compaction, chunks could have arbitrary sizes, making it
            // doubly necessary to set the file size here.
            lastChunk->mmap.len(_ChunkLen);
            return *lastChunk;
        }
    }
    
    const Path _path;
    
    struct {
        RecordRefs recordRefs;
        RecordRefs reserved;
        Chunks chunks;
    } _state;
};
