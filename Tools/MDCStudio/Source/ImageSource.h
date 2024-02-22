#import <Foundation/Foundation.h>
#import <filesystem>
#import <thread>
#import <set>
#import <array>
#import <chrono>
#import <AppleTextureEncoder.h>
#import "Toastbox/Atomic.h"
#import "Toastbox/Math.h"
#import "Toastbox/Signal.h"
#import "Toastbox/Util.h"
#import "Code/Shared/Time.h"
#import "Code/Shared/Clock.h"
#import "Code/Shared/MSP.h"
#import "Code/Shared/ImgSD.h"
#import "Code/Shared/ChecksumFletcher32.h"
#import "Tools/Shared/ImagePipeline/ImagePipeline.h"
#import "Tools/Shared/ImagePipeline/EstimateIlluminant.h"
#import "Tools/Shared/ImagePipeline/RenderThumb.h"
#import "Tools/Shared/AssertionCounter.h"
#import "Tools/Shared/ELF32Binary.h"
#import "ImageLibrary.h"
#import "Cache.h"

namespace MDCStudio {

struct Image {
    size_t width = 0;
    size_t height = 0;
    MDCTools::CFADesc cfaDesc;
    std::unique_ptr<uint8_t[]> data;
    operator bool() const { return (bool)data; }
};

struct ImageSource; using ImageSourcePtr = SharedPtr<ImageSource>;
struct ImageSource : Object {
    enum class Priority : uint8_t { High, Low, Cache };
    using Path = std::filesystem::path;
    
    struct _Cleanup {
        _Cleanup(std::function<void()> fn) : _fn(fn) {}
        ~_Cleanup() { _fn(); }
        std::function<void()> _fn;
    };
    
    using Cleanup = std::unique_ptr<_Cleanup>;
    
    using __ThumbBuffer = uint8_t[ImgSD::Thumb::ImagePaddedLen];
    using _ThumbCache = Cache<ImageRecordPtr,__ThumbBuffer,512,(uint8_t)Priority::Low>;
    using _ThumbBuffer = _ThumbCache::Entry;
    using _ThumbBufferReserved = _ThumbCache::Reserved;
    
    using __ImageBuffer = uint8_t[ImgSD::Full::ImagePaddedLen];
    using _ImageCache = Cache<ImageRecordPtr,__ImageBuffer,8,(uint8_t)Priority::Low>;
    using _ImageBuffer = _ImageCache::Entry;
    using _ImageBufferReserved = _ImageCache::Reserved;
    
    // Thread: convenience to automatically join() the thread upon instance destruction
    struct Thread : std::thread {
        using std::thread::thread;
        
        // Move constructor
        Thread(Thread&& x) { set(std::move(x)); }
        // Move assignment operator
        Thread& operator=(Thread&& x) { set(std::move(x)); return *this; }
        
        ~Thread() {
            if (joinable()) join();
        }
        
        void set(Thread&& x) {
            if (joinable()) join();
            std::thread::operator=(std::move(x));
        }
    };
    
    static int _CPUCount() {
//        return 1;
        static int CPUCount = std::max(1, (int)std::thread::hardware_concurrency());
        return CPUCount;
    }
    
    static void ImageRecordInit(ImageRecord& rec, Img::Id id, SD::Block addrFull, SD::Block addrThumb) {
        rec.info.id = id;
        rec.info.addrFull = addrFull;
        rec.info.addrThumb = addrThumb;
        rec.status.loadCount = 0;
    }
    
    void init(const Path& dir) {
        printf("ImageSource::init() %p\n", this);
        Object::init(); // Call super
        
        _dir = dir;
        _imageLibrary = Object::Create<ImageLibrary>();
        
        // Read state from disk
        try {
            _SerializedState state = _SerializedStateRead(_dir);
            _name = std::string(state.name);
        } catch (const std::exception& e) {}
        
        // Load the library
        {
            auto lock = std::unique_lock(*_imageLibrary);
            _imageLibrary->read(_dir / "ImageLibrary");
        }
        
        // Init _dataRead
        {
            _dataRead.thread = Thread([&] { _dataRead_thread(); });
        }
        
        // Init _thumbRender
        {
            _thumbRender.master.thread = Thread([&] { _thumbRender_masterThread(); });
            
            for (int i=0; i<_CPUCount(); i++) {
                _thumbRender.slave.threads.emplace_back([&] { _thumbRender_slaveThread(); });
            }
        }
    }
    
    ~ImageSource() {
        printf("~ImageSource() %p\n", this);
        stop();
    }
    
    ObjectProperty(std::string, name);
    
    void changed(const Event& ev) override {
        if (ev.prop == &_name) {
            write();
        }
    }
    
    virtual void stop() {
        _dataRead.signal.stop();
        _thumbRender.master.signal.stop();
        _thumbRender.slave.signal.stop();
        
        for (_LoadState& loadState : _loadStates.mem()) {
            loadState.signal.stop();
        }
        
        _thumbCache.stop();
        _imageCache.stop();
        _loadStates.stop();
    }
    
    void _dataReadPause(int inc) {
        auto lock = _dataRead.signal.lock();
        _dataRead.pause += inc;
        _dataRead.signal.signalAll();
    }
    
    Cleanup dataReadPause() {
        _dataReadPause(1);
        return std::make_unique<_Cleanup>([=] { _dataReadPause(-1); });
    }
    
    Path dir() const {
        return _dir;
    }
    
//    const Toastbox::SendRight& service() {
//        auto lock = deviceLock();
//        return _device.device->dev().service();
//    }
    
    // MARK: - Serialization
    
    void write() {
        _SerializedState state;
        state.version = _Version;
        // Copy UTF8 device name into state.name
        // state.name is initialized with zeroes, so we don't need to explicitly set a
        // null byte, but we do need to limit the number of copied bytes to
        // `sizeof(state.name)-1` to ensure that the null byte isn't overwritten
        name().copy(state.name, sizeof(state.name)-1);
        
        _SerializedStateWrite(_dir, state);
    }
    
    // MARK: - ImageSource
    
    virtual ImageLibraryPtr imageLibrary() { return _imageLibrary; }
    
    virtual void renderThumbs(std::set<ImageRecordPtr> recs) {
        try {
            auto lock = _thumbRender.master.signal.lock();
            _thumbRender.master.recs = std::move(recs);
        } catch (const Toastbox::Signal::Stop&) {
            // No-op if we're in the process of teardown
        }
        _thumbRender.master.signal.signalOne();
    }
    
    virtual Image getImage(Priority priority, const ImageRecordPtr& rec) {
        // If the image is in our cache, return it
        _ImageBuffer cached = _imageCache.get(rec);
        if (cached) return _imageCreate(cached);
        // Short-circuit if the caller only wanted the image if it's cached
        if (priority == Priority::Cache) return {};
        return _loadImage(priority, rec);
    }
    
    virtual void deleteImages(const ImageSet& recs) {
        auto lock = std::unique_lock(*_imageLibrary);
        _imageLibrary->remove(recs);
        _imageLibrary->write();
    }
    
    virtual Cleanup dataReadStart() { return nullptr; }
    virtual void dataRead(const ImageRecordPtr& rec, const _ThumbBuffer& buf) = 0;
    virtual void dataRead(const ImageRecordPtr& rec, const _ImageBuffer& buf) = 0;
    
    // MARK: - Private
    
    static constexpr uint32_t _Version = 0;
    
    static constexpr MDCTools::CFADesc _CFADesc = {
        MDCTools::CFAColor::Green, MDCTools::CFAColor::Red,
        MDCTools::CFAColor::Blue, MDCTools::CFAColor::Green,
    };
    
    struct [[gnu::packed]] _SerializedState {
        uint32_t version = 0;
        char name[128] = {}; // UTF-8 with NULL byte
    };
    
    struct _LoadState {
        Toastbox::Signal signal; // Protects this struct
        std::set<ImageRecordPtr> notify;
        Toastbox::Atomic<size_t> underway = 0;
    };
    
    using _LoadStatePool = Cache<int,_LoadState,4>;
    
    struct _BufferReserved : std::variant<_ThumbBufferReserved,_ImageBufferReserved> {
        size_t cap() const {
            if (auto x=thumb())      return sizeof(*(x->entry()));
            else if (auto x=image()) return sizeof(*(x->entry()));
            else                     abort();
        }
        
        void* storage() const {
            if (auto x=thumb())      return &*(x->entry());
            else if (auto x=image()) return &*(x->entry());
            else                     abort();
        }
        
        bool operator<(const _BufferReserved& b) const {
            if (auto x=thumb())      return x->entry() < b.thumb()->entry();
            else if (auto x=image()) return x->entry() < b.image()->entry();
            else                     abort();
        }
        
        bool operator==(const _BufferReserved& b) const {
            if (auto x=thumb())      return x->entry() == b.thumb()->entry();
            else if (auto x=image()) return x->entry() == b.image()->entry();
            else                     abort();
        }
        
        bool operator!=(const _BufferReserved& b) const {
            if (auto x=thumb())      return x->entry() != b.thumb()->entry();
            else if (auto x=image()) return x->entry() != b.image()->entry();
            else                     abort();
        }
        
        const _ThumbBufferReserved* thumb() const { return std::get_if<_ThumbBufferReserved>(this); }
        const _ImageBufferReserved* image() const { return std::get_if<_ImageBufferReserved>(this); }
        
        _ThumbBufferReserved* thumb() { return std::get_if<_ThumbBufferReserved>(this); }
        _ImageBufferReserved* image() { return std::get_if<_ImageBufferReserved>(this); }
    };
    
    struct _DataReadWork {
        ImageRecordPtr rec;
        _BufferReserved buf;
        std::function<void(_DataReadWork&&)> callback;
        
        bool operator<(const _DataReadWork& x) const {
            if ((bool)buf.thumb() != (bool)x.buf.thumb()) return (bool)buf.thumb() < (bool)x.buf.thumb();
            if (rec != x.rec) return rec->info.id > x.rec->info.id; // Order descending!
            if (buf != x.buf) return buf < x.buf;
            return false;
        }
        
        bool operator==(const _DataReadWork& x) const {
            if ((bool)buf.thumb() != (bool)x.buf.thumb()) return false;
            if (rec != x.rec) return false;
            if (buf != x.buf) return false;
            return true;
        }
        
        bool operator!=(const _DataReadWork& x) const { return !(*this == x); }
    };
    
    struct _RenderWork {
        bool initial = false;
        bool validateChecksum = false;
        ImageRecordPtr rec;
        _ThumbBuffer buf;
        std::function<void()> callback;
    };
    
    using _DataReadWorkQueue = std::queue<_DataReadWork>;
    using _RenderWorkQueue = std::queue<_RenderWork>;
//    using _ImageLoadQueue = std::queue<_RenderWork>;
    
    static Path _StatePath(const Path& dir) { return dir / "State"; }
    
    static _SerializedState _SerializedStateRead(const Path& dir) {
        std::ifstream f;
        f.exceptions(std::ofstream::failbit | std::ofstream::badbit);
        f.open(_StatePath(dir));
        
        _SerializedState state;
        f.read((char*)&state, sizeof(state));
        state.name[sizeof(state.name)-1] = 0; // Ensure that state.name has a null byte
        
        if (state.version != _Version) {
            throw Toastbox::RuntimeError("invalid state version (expected: 0x%jx, got: 0x%jx)",
                (uintmax_t)_Version,
                (uintmax_t)state.version
            );
        }
        
        return state;
    }
    
    static void _SerializedStateWrite(const Path& dir, const _SerializedState& state) {
        std::ofstream f;
        f.exceptions(std::ofstream::failbit | std::ofstream::badbit);
        f.open(_StatePath(dir));
        f.write((char*)&state, sizeof(state));
    }
    
    static bool _ImageChecksumValid(const void* data, Img::Size size) {
        const size_t ChecksumOffset = (size==Img::Size::Full ? Img::Full::ChecksumOffset : Img::Thumb::ChecksumOffset);
        // Validate thumbnail checksum
        const uint32_t checksumExpected = ChecksumFletcher32(data, ChecksumOffset);
        uint32_t checksumGot = 0;
        memcpy(&checksumGot, (uint8_t*)data+ChecksumOffset, Img::ChecksumLen);
        if (checksumGot != checksumExpected) {
            printf("Checksum invalid (expected:0x%08x got:0x%08x)\n", checksumExpected, checksumGot);
            return false;
        }
        return true;
    }
    
    static constexpr size_t _ThumbTmpStorageLen = ImageThumb::ThumbWidth * ImageThumb::ThumbHeight * 4;
    using _ThumbTmpStorage = std::array<uint8_t, _ThumbTmpStorageLen>;
    
    // _ThumbRender(): renders a thumbnail from the RAW source pixels (src) into the
    // destination buffer (dst), as BC7-compressed data
    static CCM _ThumbRender(MDCTools::Renderer& renderer, at_encoder_t compressor, _ThumbTmpStorage& tmpStorage,
        const ImageOptions& opts, bool estimateIlluminant, const void* src, void* dst) {
        
        using namespace MDCTools;
        using namespace MDCTools::ImagePipeline;
        using namespace Toastbox;
        
        CCM ccm;
        
        // Render thumbnail into `thumbTxt`
        constexpr MTLTextureUsage ThumbTxtUsage = MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
        const Renderer::Txt thumbTxt = renderer.textureCreate(MTLPixelFormatRGBA8Unorm,
            ImageThumb::ThumbWidth, ImageThumb::ThumbHeight, ThumbTxtUsage);
        {
            Renderer::Txt rawTxt = Pipeline::TextureForRaw(renderer,
                Img::Thumb::PixelWidth, Img::Thumb::PixelHeight, (const ImagePixel*)src);
            
            ccm.illum = (estimateIlluminant ? EstimateIlluminant::Run(renderer, _CFADesc, rawTxt) : ColorRaw(opts.whiteBalance.illum));
            ccm.matrix = (estimateIlluminant ? ColorMatrixForIlluminant(ccm.illum).matrix : ColorMatrix((double*)opts.whiteBalance.colorMatrix));
            
            const Pipeline::Options popts = {
                .cfaDesc                = _CFADesc,
                
                .illum                  = ccm.illum,
                .colorMatrix            = ccm.matrix,
                
                .defringe               = { .en = false, },
                .reconstructHighlights  = { .en = opts.reconstructHighlights, },
                .debayerLMMSE           = { .applyGamma = true, },
                
                .exposure               = (float)opts.exposure,
                .saturation             = (float)opts.saturation,
                .brightness             = (float)opts.brightness,
                .contrast               = (float)opts.contrast,
                
                .localContrast = {
                    .amount             = (float)opts.localContrast.amount,
                    .radius             = (float)opts.localContrast.radius,
                },
            };
            
            Pipeline::Run(renderer, popts, rawTxt, thumbTxt);
            renderer.sync(thumbTxt);
            renderer.commitAndWait();
        }
        
        // Compress thumbnail into `dst`
        {
//            constexpr float CompressErrorThreshold = 0.0009765625;    // Fast
            constexpr float CompressErrorThreshold = 0.00003051757812;  // High quality
            
            [thumbTxt getBytes:&tmpStorage[0] bytesPerRow:ImageThumb::ThumbWidth*4
                fromRegion:MTLRegionMake2D(0,0,ImageThumb::ThumbWidth,ImageThumb::ThumbHeight) mipmapLevel:0];
            
            const at_texel_region_t srcTexels = {
                .texels = (void*)&tmpStorage[0],
                .validSize = {
                    .x = ImageThumb::ThumbWidth,
                    .y = ImageThumb::ThumbHeight,
                    .z = 1,
                },
                .rowBytes = ImageThumb::ThumbWidth*4,
                .sliceBytes = 0,
            };
            
            const at_block_buffer_t dstBuffer = {
                .blocks = dst,
                .rowBytes = ImageThumb::ThumbWidth*4,
                .sliceBytes = 0,
            };
            
            const float cr = at_encoder_compress_texels(
                compressor,
                &srcTexels,
                &dstBuffer,
                CompressErrorThreshold,
        //        at_flags_default
                at_flags_print_debug_info
            );
            
            if (cr < 0) {
                throw Toastbox::RuntimeError("at_encoder_compress_texels failed");
            }
        }
        
        return ccm;
    }
    
    Image _imageCreate(const _ImageBuffer& buf) {
//        assert(len >= Img::Full::ImageLen);
        auto data = std::make_unique<uint8_t[]>(Img::Full::PixelLen);
        memcpy(data.get(), *buf+Img::PixelsOffset, Img::Full::ImageLen);
        return Image{
            .width = Img::Full::PixelWidth,
            .height = Img::Full::PixelHeight,
            .cfaDesc = _CFADesc,
            .data = std::move(data),
        };
    }
    
    void _readCompleteCallback(_LoadState& state, _DataReadWork&& work, bool initial) {
        _ThumbBufferReserved& buf = *work.buf.thumb();
        
        // Enqueue rendering
        {
            {
                auto lock = _thumbRender.slave.signal.lock();
                _renderEnqueue(lock, state, initial, true, work.rec, buf.entry());
            }
            _thumbRender.slave.signal.signalAll();
        }
        
        // Insert buffers into our cache, if this isn't the initial load.
        // We don't want to populate the cache on the initial load because we want the Cache buffers to
        // be available for SDReads, but if we store them in the cache, we have fewer buffers available
        // for use during initial import, which slows down the importing process.
        if (!initial) _thumbCache.set(work.rec, std::move(buf));
    }
    
    void _renderCompleteCallback(_LoadState& state, ImageRecordPtr rec) {
        constexpr size_t NotifyThreshold = 8;
        
        const size_t count = --state.underway;
        
        std::set<ImageRecordPtr> notify;
        {
            auto lock = state.signal.lock();
            state.notify.insert(rec);
            if (state.notify.size()>=NotifyThreshold || !count) {
                notify = std::move(state.notify);
            }
        }
        
        if (!notify.empty()) {
            auto lock = std::unique_lock(*_imageLibrary);
            _imageLibrary->observersNotify(ImageLibrary::Event::Type::ChangeThumbnail, notify);
        }
        
        if (!count || !notify.empty()) state.signal.signalAll();
    }
    
    void _renderEnqueue(const std::unique_lock<std::mutex>& lock, _LoadState& state, bool initial, bool validateChecksum, ImageRecordPtr rec, _ThumbBuffer buf) {
        // Enqueue _RenderWork into _thumbRender.slave.queue
        _thumbRender.slave.queue.push(_RenderWork{
            .initial = initial,
            .validateChecksum = validateChecksum,
            .rec = rec,
            .buf = std::move(buf),
            .callback = [=, &state] { _renderCompleteCallback(state, rec); },
        });
    }
    
    void _loadThumbs(Priority priority, bool initial,
        std::set<ImageRecordPtr> recs, std::function<void(float)> progressCallback=nullptr) {
        
        const size_t imageCount = recs.size();
        auto timeStart = std::chrono::steady_clock::now();
        
        auto state = _loadStates.pop().entry();
        assert(!state->underway);
        state->underway += imageCount;
        
        Thread progressThread;
        if (progressCallback && imageCount) {
            progressThread = Thread([&] {
                try {
                    state->signal.wait([&] {
                        const float progress = (float)(imageCount - state->underway) / imageCount;
                        progressCallback(progress);
                        return !state->underway;
                    });
                } catch (const Toastbox::Signal::Stop&) {
                    printf("[_loadThumbs:progressThread] Stopping\n");
                }
            });
        }
        
        // Kick off rendering for all the recs that are in the cache
        {
            bool enqueued = false;
            {
                auto lock = _thumbRender.slave.signal.lock();
                
                for (auto it=recs.begin(); it!=recs.end();) {
                    const ImageRecordPtr& rec = *it;
                    
                    // If the thumbnail is in our cache, kick off rendering
                    _ThumbBuffer buf = _thumbCache.get(rec);
                    if (buf) {
                        _renderEnqueue(lock, *state, initial, false, rec, std::move(buf));
                        enqueued = true;
                        it = recs.erase(it);
                    
                    // Otherwise, on to the next one
                    } else {
                        it++;
                    }
                }
            }
            
            // Notify _thumbRender of more work
            if (enqueued) _thumbRender.slave.signal.signalAll();
        }
        
        // The remaining recs aren't in our cache, so kick off SD reading + rendering
        for (auto it=recs.rbegin(); it!=recs.rend(); it++) {
            const ImageRecordPtr& rec = *it;
            
            // Only load the record if it's still needed
            if (rec.alive()) {
                _ThumbBufferReserved buf = _thumbCache.pop((uint8_t)priority);
                
    //                printf("[_loadImages] Got buffer %p for image id %ju\n", &*buf, (uintmax_t)rec->info.id);
                
                _DataReadWork work = {
                    .rec = rec,                
                    .buf = std::move(buf),
                    .callback = [&] (_DataReadWork&& work) {
                        _readCompleteCallback(*state, std::move(work), initial);
                    },
                };
                
//                printf("[_loadImages:p%ju] Enqueuing _DataReadWork\n", (uintmax_t)priority);
                {
                    auto lock = _dataRead.signal.lock();
                    _DataReadWorkQueue& queue = _dataRead.queues[(size_t)priority];
                    queue.push(std::move(work));
                }
                _dataRead.signal.signalOne();
            
            } else {
                state->underway--;
            }
        }
        
        // Wait until everything's done
        state->signal.wait([&] { return !state->underway; });
        
        // Print profile stats
        {
            using namespace std::chrono;
            const milliseconds duration = duration_cast<milliseconds>(steady_clock::now()-timeStart);
            const double msPerImage = ((double)duration.count()/imageCount);
            const double mibPerSec = ((imageCount * ImgSD::Thumb::ImagePaddedLen) /
                (duration.count() / 1000.)) / (1024*1024);
            printf("[_loadImages:p%ju] _loadThumbs() took %ju ms for %ju images (avg = %.1f ms/img; throughput = %.1f MiB/sec)\n",
                (uintmax_t)priority,
                (uintmax_t)duration.count(),
                (uintmax_t)imageCount,
                msPerImage,
                mibPerSec);
        }
    }
    
    Image _loadImage(Priority priority, const ImageRecordPtr& rec) {
        auto state = _loadStates.pop().entry();
        _ImageBufferReserved buf = _imageCache.pop((uint8_t)priority);
        
        _DataReadWork work = {
            .rec = rec,
            .buf = std::move(buf),
            .callback = [&] (_DataReadWork&& work) {
                buf = std::move(*work.buf.image());
                state->signal.signalOne();
            },
        };
        
        {
            auto lock = _dataRead.signal.lock();
            _DataReadWorkQueue& queue = _dataRead.queues[(size_t)priority];
            queue.push(std::move(work));
        }
        _dataRead.signal.signalOne();
        
        // Wait until the buffer is returned to us by our SDRead callback
        state->signal.wait([&] { return buf.entry(); });
        Image image = _imageCreate(buf.entry());
        _imageCache.set(rec, std::move(buf));
        return image;
    }
    
    // MARK: - Data Read
    
    // _dataRead.lock must be held!
    _DataReadWorkQueue* _dataRead_nextQueue() {
        for (_DataReadWorkQueue& x : _dataRead.queues) {
            if (!x.empty()) return &x;
        }
        printf("[_dataRead_nextQueue] Stalled\n");
        return nullptr;
    }
    
    void _dataRead_thread() {
        constexpr auto SDModeTimeout = std::chrono::seconds(3);
        try {
            for (;;) {
                // Wait for work
                printf("[_dataRead_thread] Waiting for work...\n");
                _dataRead.signal.wait([&] { return _dataRead_nextQueue() && !_dataRead.pause; });
                
                // Initiate DataRead mode
                printf("[_dataRead_thread] Calling dataReadStart() START\n");
                auto dr = dataReadStart();
                printf("[_dataRead_thread] Calling dataReadStart() END\n");
                
                for (;;) {
                    _DataReadWork work;
                    {
                        // Wait for work
                        _DataReadWorkQueue* queue = nullptr;
                        bool pause = false;
                        auto lock = _dataRead.signal.wait_for(SDModeTimeout, [&] {
                            queue = _dataRead_nextQueue();
                            pause = _dataRead.pause;
                            return queue || pause;
                        });
                        // Check if we timed out waiting for work
                        if (!queue || pause) break;
//                        printf("[_dataRead_thread] Dequeued work\n");
                        work = std::move(queue->front());
                        queue->pop();
                    }
                    
                    {
                        {
//                            printf("[_dataRead_thread] reading blockBegin:%ju len:%ju (%.1f MB)\n",
//                                (uintmax_t)blockBegin, (uintmax_t)len, (float)len/(1024*1024));
                            
                            if (work.buf.thumb()) {
                                dataRead(work.rec, work.buf.thumb()->entry());
                            } else {
                                dataRead(work.rec, work.buf.image()->entry());
                            }
                        }
                        
                        work.callback(std::move(work));
                    }
                }
                
                printf("[_dataRead_thread] Exiting SD mode\n");
            }
        
        } catch (const Toastbox::Signal::Stop&) {
            printf("[_dataRead_thread] Stopping\n");
        } catch (const std::exception& e) {
            printf("[_dataRead_thread] Error: %s\n", e.what());
        }
    }
    
    // MARK: - Thumb Render
    
    template<MTLPixelFormat T_Format>
    static constexpr at_block_format_t _ATBlockFormatForMTLPixelFormat() {
// For compilation on macOS 10.15
#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_15_1
        return at_block_format_bc7;
#else
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
        if constexpr (T_Format == MTLPixelFormatASTC_4x4_LDR) {
            return at_block_format_astc_4x4_ldr;
        } else if constexpr (T_Format == MTLPixelFormatBC7_RGBAUnorm) {
            return at_block_format_bc7;
        } else {
            static_assert(Toastbox::AlwaysFalse_v<T_Format>);
        }
#pragma clang diagnostic pop
#endif
    }
    
    void _thumbRender_masterThread() {
        printf("[_thumbRender_masterThread] Starting\n");
        try {
            for (;;) {
                ImageSet recs;
                {
                    auto lock = _thumbRender.master.signal.wait([&] { return !_thumbRender.master.recs.empty(); });
                    recs = std::move(_thumbRender.master.recs);
                    // Update .thumb.render asap (ie before we've actually rendered) so that the
                    // visibleThumbs() function on the main thread stops enqueuing work asap
                    for (const ImageRecordPtr& rec : recs) {
                        rec->options.thumb.render = false;
                    }
                }
                
                printf("[_thumbRender_masterThread] Enqueueing %ju thumbnails for rendering\n", (uintmax_t)recs.size());
                _loadThumbs(ImageSource::Priority::High, false, recs);
                printf("[_thumbRender_masterThread] Rendered %ju thumbnails\n", (uintmax_t)recs.size());
            }
        
        } catch (const Toastbox::Signal::Stop&) {
        }
        printf("[_thumbRender_masterThread] Exiting\n");
    }
    
    
    void _thumbRender_slaveThread() {
        using namespace MDCTools;
        
        try {
            id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
            Renderer renderer(dev, [dev newDefaultLibrary], [dev newCommandQueue]);
            std::unique_ptr<_ThumbTmpStorage> thumbTmpStorage = std::make_unique<_ThumbTmpStorage>();
            
            at_encoder_t compressor = at_encoder_create(
                at_texel_format_rgba8_unorm,
                at_alpha_opaque,
                _ATBlockFormatForMTLPixelFormat<ImageThumb::PixelFormat>(),
                at_alpha_opaque,
                nullptr
            );
            
            if (!compressor) {
                throw Toastbox::RuntimeError("failed to create at_encoder_create");
            }
            
            for (;;) @autoreleasepool {
                _RenderWork work;
                {
                    auto lock = _thumbRender.slave.signal.wait([&] { return !_thumbRender.slave.queue.empty(); });
                    work = _thumbRender.slave.queue.front();
                    _thumbRender.slave.queue.pop();
                }
                
                ImageRecord& rec = *work.rec;
                
                if (work.validateChecksum) {
                    if (_ImageChecksumValid(*work.buf, Img::Size::Thumb)) {
//                        printf("Checksum valid (thumb)\n");
                    } else {
                        printf("Checksum INVALID (thumb)\n");
//                        abort();
                    }
                }
                
                if (work.initial) {
                    // Populate .info
                    {
                        const Img::Header& imgHeader = *(const Img::Header*)(*work.buf);
                        
                        // Validate the magic number
                        if (imgHeader.magic.u24 != Img::Header::MagicNumber.u24) {
                            printf("[_thumbRender_slaveThread] Invalid magic number (got: %jx, expected: %jx)\n",
                                (uintmax_t)imgHeader.magic.u24, (uintmax_t)Img::Header::MagicNumber.u24);
                            printf("[_thumbRender_slaveThread] Skipping image\n");
                            // Skip this image
                            // In particular, we want to make sure loadCount==0, so that _sync_thread() can observe
                            // it and remove this image.
                            goto thumbDone;
                        }
                        
                        if (imgHeader.id != rec.info.id) {
                            #warning TODO: how do we properly handle this?
                            printf("[_thumbRender_slaveThread] Invalid image id (got: %ju, expected: %ju)\n",
                                (uintmax_t)imgHeader.id, (uintmax_t)rec.info.id);
//                            throw Toastbox::RuntimeError("invalid image id (got: %ju, expected: %ju)",
//                                (uintmax_t)imgHeader.id, (uintmax_t)rec.info.id);
                        }
                        
                        rec.info.timestamp      = imgHeader.timestamp;
                        
                        rec.info.imageWidth     = imgHeader.imageWidth;
                        rec.info.imageHeight    = imgHeader.imageHeight;
                        
                        rec.info.coarseIntTime  = imgHeader.coarseIntTime;
                        rec.info.analogGain     = imgHeader.analogGain;
                        
                        rec.info.batteryLevelMv = imgHeader.batteryLevelMv;
                    }
                    
                    // Populate .options
                    {
                        rec.options = {};
                    }
                }
                
                // Render the thumbnail into rec.thumb
                {
                    const void* thumbSrc = (*work.buf)+Img::PixelsOffset;
                    void* thumbDst = rec.thumb.data;
                    
                    // estimateIlluminant: only perform illuminant estimation upon our initial import
                    const bool estimateIlluminant = work.initial;
                    const CCM ccm = _ThumbRender(renderer, compressor, *thumbTmpStorage, rec.options,
                        estimateIlluminant, thumbSrc, thumbDst);
                    
                    if (estimateIlluminant) {
                        // Populate .info.illumEst
                        ccm.illum.m.get(rec.info.illumEst);
                        // Populate .options.whiteBalance
                        ImageWhiteBalanceSet(rec.options.whiteBalance, true, ccm);
                    }
                }
                
                // Atomically increment loadCount, ensuring that we never write a value of 0, since 0 is a
                // special value that loadCount is initialized to that indicates that we've never rendered.
                // We're using an atomic store here, so there's an implicit seq_cst memory barrier that ensures
                // that the thumbnail update is complete before the loadCount change can be observed.
                {
                    // Verify that we can safely cast our loadCount field to a std::atomic<uint32_t>
                    // by checking loadCount's type and alignment.
                    using Atomic32 = std::atomic<uint32_t>;
                    static_assert(std::is_same_v<uint32_t, decltype(rec.status.loadCount)>);
                    static_assert(!(offsetof(ImageRecord, status.loadCount) % alignof(Atomic32)));
                    Atomic32& loadCount = reinterpret_cast<Atomic32&>(rec.status.loadCount);
                    uint32_t loadCountCopy = loadCount;
                    loadCountCopy++;
                    if (!loadCountCopy) loadCountCopy++; // Skip 0
                    loadCount = loadCountCopy;
                }
                
            thumbDone:
                work.callback();
            }
        
        } catch (const Toastbox::Signal::Stop&) {
            printf("[_thumbRender_slaveThread] Stopping\n");
        }
    }
    
    // MARK: - Members
    
    Path _dir;
    ImageLibraryPtr _imageLibrary;
    
    _ThumbCache _thumbCache;
    _ImageCache _imageCache;
    _LoadStatePool _loadStates;
    
    struct {
        Toastbox::Signal signal; // Protects this struct
        Thread thread;
        _DataReadWorkQueue queues[(size_t)Priority::Low+1];
        uint32_t pause = 0;
    } _dataRead;
    
    struct {
        struct {
            Toastbox::Signal signal; // Protects this struct
            Thread thread;
            ImageSet recs;
        } master;
        
        struct {
            Toastbox::Signal signal; // Protects this struct
            std::vector<Thread> threads;
            _RenderWorkQueue queue;
        } slave;
    } _thumbRender;
};

} // namespace MDCStudio
