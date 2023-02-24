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
    
    using Path = std::filesystem::path;
    using Record = T_Record;
    
    struct Chunk {
        size_t recordCount = 0; // Count of records currently stored in chunk
        size_t recordIdx = 0; // Index of next record
        Toastbox::Mmap mmap;
    };
    
    using Chunks = std::list<Chunk>;
    using ChunkConstIter = typename Chunks::const_iterator;
    
    struct RecordRef {
        ChunkConstIter chunk;
        size_t idx = 0;
    };
    
    using RecordRefs = std::vector<RecordRef>;
    using RecordRefConstIter = typename RecordRefs::const_iterator;
    using RecordRefConstReverseIter = typename RecordRefs::const_reverse_iterator;
    
    // FindNextChunk(): finds the first RecordRef for the next chunk after the given RecordRef's chunk
    static RecordRefConstIter FindNextChunk(RecordRefConstIter iter, RecordRefConstIter end) {
        if (iter == end) return end;
        const ChunkConstIter startChunk = iter->chunk;
        
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
        
        #warning TODO: optionally (based on argument) peform 'compaction' to move records into smallest number of chunks as possible
        #warning TODO: truncate each chunk file on disk to have the minimum size to contain its last record
        #warning TODO: delete unreferenced chunk files in Chunks dir
        
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
        
        // Prune chunks (in memory) that have 0 records
        {
            _state.chunks.remove_if([] (const Chunk& chunk) {
                return chunk.recordCount==0;
            });
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
    
//    const Path& path() { return _path; }
//    
//    T_Record* add() {
//        _ChunkIter chunk = _writableChunk();
//        const size_t idx = chunk->recordIdx;
//        const size_t off = sizeof(T_Record)*idx;
//        _state.recordRefs.push_back({
//            .chunk = chunk,
//            .idx = idx,
//        });
//        
//        chunk->recordCount++;
//        chunk->recordIdx++;
//        
//        return chunk->mmap.template data<T_Record>(off);
//    }
    
//    void remove(size_t idx) {
//        const RecordRef& ref = _state.recordRefs.at(idx);
//        ref.chunk->recordCount--;
//        
//        _state.recordRefs.erase(_state.recordRefs.begin()+idx);
//    }
    
    // reserve(): reserves space for `count` additional records, but does not actually add them
    // to the store. add() must be called after reserve() to add the records to the store.
    void reserve(size_t count) {
        assert(_state.reserved.empty());
        _state.reserved.resize(count);
        
        for (RecordRef& ref : _state.reserved) {
            const _ChunkIter chunk = _writableChunk();
            
            ref = {
                .chunk = chunk,
                .idx = chunk->recordIdx,
            };
            
            chunk->recordIdx++;
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
    
    T_Record* recordGet(const RecordRef& ref) {
        return (T_Record*)(ref.chunk->mmap.data() + ref.idx*sizeof(T_Record));
    }
    
    T_Record* recordGet(RecordRefConstIter iter) {
        return recordGet(*iter);
    }
    
    T_Record* recordGet(RecordRefConstReverseIter iter) {
        return recordGet(*iter);
    }
    
    bool empty() const { return _state.recordRefs.empty(); }
    
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
    
//    ChunkConstIter getRecordChunk(size_t idx) const {
//        return _state.recordRefs.at(idx).chunk;
//    }
    
    size_t recordCount() const {
        return _state.recordRefs.size();
    }
    
private:
    using _ChunkIter = typename Chunks::iterator;
    using _RecordRefIter = typename RecordRefs::iterator;
    
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
    
    static constexpr size_t _ChunkCap = sizeof(T_Record)*T_ChunkRecordCap;
    
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
        
        Chunks chunks;
        std::vector<_ChunkIter> chunkIters;
        
        // Create and map in each chunk
        for (size_t i=0; i<header.chunkCount; i++) {
            chunks.push_back(Chunk{
                .recordCount = 0,
                .recordIdx = 0,
                .mmap = Toastbox::Mmap(_ChunkPath(path, i), SIZE_MAX, MAP_SHARED),
            });
            chunkIters.push_back(std::prev(chunks.end()));
        }
        
        // Create RecordRefs
        RecordRefs recordRefs;
        recordRefs.resize(header.recordCount);
        
//        const _SerializedRecordRef* serializedRecordRefs = mmap.data<_SerializedRecordRef>(off);
//        off += sizeof(_SerializedRecordRef)*(header.recordCount);
//        const _SerializedRecordRef* serializedRecordRefsLast = mmap.data<_SerializedRecordRef>(off-sizeof(_SerializedRecordRef));
//        (void)serializedRecordRefsLast; // Silence warning; just using variable to bounds-check
        
        std::optional<size_t> chunkIdxPrev;
        std::optional<size_t> idxPrev;
        for (size_t i=0; i<header.recordCount; i++) {
            _SerializedRecordRef ref;
            f.read((char*)&ref, sizeof(ref));
            
            const size_t chunkIdx = ref.chunkIdx;
            Chunk& chunk = *chunkIters.at(chunkIdx);
            
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
                .chunk = chunkIters.at(ref.chunkIdx),
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
        std::optional<ChunkConstIter> chunkPrev;
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
    
    static Toastbox::Mmap _CreateChunk(const Path& path) {
        constexpr int ChunkPerm = (S_IRUSR|S_IWUSR) | (S_IRGRP) | (S_IROTH);
        
        const int fdi = open(path.c_str(), O_RDWR|O_CREAT|O_CLOEXEC, ChunkPerm);
        if (fdi < 0) throw Toastbox::RuntimeError("failed to create chunk file: %s", strerror(errno));
        
        const Toastbox::FileDescriptor fd(fdi);
        const int ir = ftruncate(fd, _ChunkCap);
        if (ir) throw Toastbox::RuntimeError("ftruncate failed: %s", strerror(errno));
        
        // Explicitly give `_ChunkCap` to Mmap, otherwise a race is possible where the file gets truncated
        // on disk by another process, and our resulting mapping is shorter than we expect. By supplying
        // the length explicitly, we ensure that the resulting mapping is the expected length, regardless
        // of the file size on disk.
        return Toastbox::Mmap(fd, _ChunkCap, MAP_SHARED);
    }
    
    _ChunkIter _writableChunk() {
        _ChunkIter lastChunk = std::prev(_state.chunks.end());
        if (lastChunk==_state.chunks.end() || lastChunk->recordIdx>=T_ChunkRecordCap) {
            // We don't have any chunks, or the last chunk is full
            // Create a new chunk
            Toastbox::Mmap mmap = _CreateChunk(_chunkPath(_state.chunks.size()));
            
            _state.chunks.push_back(Chunk{
                .recordCount = 0,
                .recordIdx = 0,
                .mmap = std::move(mmap),
            });
            
            return std::prev(_state.chunks.end());
        
        } else {
            // Last chunk can fit more records
            // Resize the last chunk if it's too small to fit more records
            if (lastChunk->mmap.len() < _ChunkCap) {
                lastChunk->mmap = _CreateChunk(_chunkPath(_state.chunks.size()-1));
            }
            
            return lastChunk;
        }
    }
    
    const Path _path;
    
    struct {
        RecordRefs recordRefs;
        RecordRefs reserved;
        Chunks chunks;
    } _state;
};
