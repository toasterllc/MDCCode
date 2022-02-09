#import <Foundation/Foundation.h>
#import <filesystem>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import "MSP.h"
#import "MDCUSBDevice.h"
#import "ImageLibrary.h"
#import "Mmap.h"
#import "ImagePipeline.h"
#import "RenderThumb.h"
#import "ImgSD.h"
#import "Vendor.h"

class MDCDevice : public MDCUSBDevice {
public:
    using MDCUSBDevice::MDCUSBDevice;
    
    MDCDevice(USBDevice&& dev) : MDCUSBDevice(std::move(dev)), _devDir(_DevDirForSerial(serial())) {
        printf("MDCDevice()\n");
    }
    
    ~MDCDevice() {
        auto lock = std::unique_lock(_state.lock);
        #warning TODO: this will deadlock if the thread tries to acquire the lock...
        if (_state.updateImageLibraryThread.joinable()) {
            _state.updateImageLibraryThread.join();
        }
    }
    
    ImageLibraryPtr imgLib() {
        auto lock = std::unique_lock(_state.lock);
        if (!_state.imgLib) {
            _state.imgLib = std::make_shared<MDCTools::Vendor<ImageLibrary>>(_devDir / "ImageLibrary");
            // Load the library
            _state.imgLib->vend()->read();
        }
        return _state.imgLib;
    }
    
    void updateImageLibrary() {
        auto lock = std::unique_lock(_state.lock);
        assert(!_state.updateImageLibraryThread.joinable());
        #warning TODO: what should we do if the thread's already running?
        _state.updateImageLibraryThread = std::thread([this] { _threadUpdateImageLibrary(); });
        _state.updateImageLibraryThread.detach();
    }
    
private:
    using _Path = std::filesystem::path;
    static constexpr uint32_t _Version = 0;
    
    struct [[gnu::packed]] _SerializedState {
        uint32_t version = 0;
        Img::Id imgIdEnd = 0;
    };
    
    struct _Range {
        uint32_t idx  = 0;
        uint32_t len = 0;
    };
    
    static _Path _StatePath(const _Path& devDir) { return devDir / "State"; }
    
    static _Path _DevDirForSerial(const std::string_view& serial) {
        auto urls = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask];
        if (![urls count]) throw Toastbox::RuntimeError("failed to get NSApplicationSupportDirectory");
        
        const _Path appSupportDir = _Path([urls[0] fileSystemRepresentation]) / [[[NSBundle mainBundle] bundleIdentifier] UTF8String];
        return appSupportDir / "Devices" / serial;
    }
    
    static _SerializedState _SerializedStateRead(const _Path& devDir) {
        const Mmap mmap(_StatePath(devDir));
        
        const _SerializedState& state = *mmap.data<_SerializedState>(0);
        
        if (state.version != _Version) {
            throw Toastbox::RuntimeError("invalid state version (expected: 0x%jx, got: 0x%jx)",
                (uintmax_t)_Version,
                (uintmax_t)state.version
            );
        }
        
        return state;
    }
    
    static void _SerializedStateWrite(const _Path& devDir, const _SerializedState& state) {
        std::ofstream f;
        f.exceptions(std::ofstream::failbit | std::ofstream::badbit);
        f.open(_StatePath(devDir));
        f.write((char*)&state, sizeof(state));
    }
    
//    static MSP::ImgRingBuf _ReadImgRingBuf(MDCUSBDevice& dev) {
//        dev.mspConnect();
//        
//        MSP::State state;
//        dev.mspRead(MSP::StateAddr, &state, sizeof(state));
//        
//        if (state.magicVersion != MSP::State::MagicVersion) {
//            throw Toastbox::RuntimeError("invalid MSP state magicVersion (expected: 0x%jx, got: 0x%jx)",
//                (uintmax_t)MSP::State::MagicVersion,
//                (uintmax_t)state.magicVersion
//            );
//        }
//        
//        dev.mspDisconnect();
//        
//        const MSP::ImgRingBuf* imgRingBuf = &state.img.ringBuf;
//        const MSP::ImgRingBuf* imgRingBuf2 = &state.img.ringBuf2;
//        const bool br = MSP::ImgRingBuf::FindLatest(imgRingBuf, imgRingBuf2);
//        if (!br) throw Toastbox::RuntimeError("both image ring buffers are invalid");
//    }
    
    static const MSP::ImgRingBuf& _GetImgRingBuf(const MSP::State& state) {
        const MSP::ImgRingBuf& imgRingBuf0 = state.sd.imgRingBufs[0];
        const MSP::ImgRingBuf& imgRingBuf1 = state.sd.imgRingBufs[1];
        const std::optional<int> comp = MSP::ImgRingBuf::Compare(imgRingBuf0, imgRingBuf1);
        if (!comp) throw Toastbox::RuntimeError("both image ring buffers are invalid");
        return *comp>=0 ? imgRingBuf0 : imgRingBuf1;
    }
    
    void _threadUpdateImageLibrary() {
        try {
            mspConnect();
            
            MSP::State state;
            mspRead(MSP::StateAddr, &state, sizeof(state));
            
            if (state.magic != MSP::State::MagicNumber) {
                // Program MSPApp onto MSP
                #warning TODO: implement
                throw Toastbox::RuntimeError("TODO: implement");
            }
            
            if (state.version > MSP::State::Version) {
                // Newer version than we understand -- tell user to upgrade or re-program
                #warning TODO: implement
                throw Toastbox::RuntimeError("TODO: implement");
            }
            
            if (!state.sd.valid) {
                // MSPApp state isn't valid -- ignore
                #warning TODO: implement
                throw Toastbox::RuntimeError("TODO: implement");
            }
            
            const STM::SDCardInfo sdCardInfo = sdInit();
            if (memcmp(&sdCardInfo.cardId, &state.sd.cardId, sizeof(state.sd.cardId))) {
                // Current SD card id doesn't match MSP's card id
                #warning TODO: implement
                throw Toastbox::RuntimeError("TODO: implement");
            }
            
//            if (state.magic != MSP::State::MagicNumber) {
//                throw Toastbox::RuntimeError("invalid MSP::State magic number (expected: 0x%08jx, got: 0x%08jx)",
//                    (uintmax_t)MSP::State::MagicNumber,
//                    (uintmax_t)state.magic
//                );
//            }
//            
//            if (state.version != MSP::State::Version) {
//                throw Toastbox::RuntimeError("unrecognized MSP::State version (expected: 0x%02jx, got: 0x%02jx)",
//                    (uintmax_t)MSP::State::Version,
//                    (uintmax_t)state.version
//                );
//            }
            
//            mspDisconnect();
//            
//            const SD::CardId cardId = sdCardIdGet();
//            
//            printf("cardId:     ");
//            for (size_t i=0; i<sizeof(cardId); i++) {
//                printf("%02x ", ((uint8_t*)&cardId)[i]);
//            }
//            printf("\n");
//            
//            const SD::CardData cardData = sdCardDataGet();
//            printf("cardData:   ");
//            for (size_t i=0; i<sizeof(cardData); i++) {
//                printf("%02x ", ((uint8_t*)&cardData)[i]);
//            }
//            printf("\n");
            
            const MSP::ImgRingBuf& imgRingBuf = _GetImgRingBuf(state);
            
            #warning TODO: if the user keeps deleting images from the end of the local library, we'll unnecessarily
            #warning TODO: re-download those images every time this function runs, since the library.back() will
            #warning TODO: no longer reference the 'most recent' image.
            #warning TODO: to fix this, we should keep track of the most recent image downloaded from
            #warning TODO: the device, and use that to determine which images should be downloaded
            {
                // Remove images from beginning of library: lib has, device doesn't
                {
                    auto il = imgLib()->vend();
                    const Img::Id deviceImgIdBegin = imgRingBuf.buf.idBegin;
                    const auto removeBegin = il->begin();
                    
                    // Find the first image >= `deviceImgIdBegin`
                    const auto removeEnd = std::lower_bound(il->begin(), il->end(), 0,
                        [&](const ImageLibrary::RecordRef& sample, auto) -> bool {
                            return il->recordGet(sample)->id < deviceImgIdBegin;
                        });
                    
                    printf("Removing %ju images\n", (uintmax_t)std::distance(removeBegin, removeEnd));
                    il->remove(removeBegin, removeEnd);
                }
                
                // Add images to end of library: device has, lib doesn't
                {
                    #warning TODO: what if _imgIdEnd() < il->recordGet(il->back())->id+1, because the ImageLibrary was sync'd, but we crashed before we wrote imgIdEnd?
                    const Img::Id libImgIdEnd = imgLib()->vend()->imgIdEnd();
                    const Img::Id deviceImgIdEnd = imgRingBuf.buf.idEnd;
                    
                    if (libImgIdEnd > deviceImgIdEnd) {
                        throw Toastbox::RuntimeError("image library claims to have newer images than the device (libImgIdEnd: %ju, deviceImgIdEnd: %ju)",
                            (uintmax_t)libImgIdEnd,
                            (uintmax_t)deviceImgIdEnd
                        );
                    }
                    
                    const uint32_t addCount = deviceImgIdEnd-libImgIdEnd;
                    
                    _Range newest;
                    newest.idx = imgRingBuf.buf.widx - std::min((uint32_t)imgRingBuf.buf.widx, addCount);
                    newest.len = imgRingBuf.buf.widx - newest.idx;
                    
                    _Range oldest;
                    oldest.len = addCount - newest.len;
                    oldest.idx = state.sd.imgCap - oldest.len;
                    
                    _loadImages(oldest);
                    _loadImages(newest);
                }
                
                // Write the library
                imgLib()->vend()->write();
            }
        
        } catch (const std::exception& e) {
            fprintf(stderr, "Failed to update image library: %s", e.what());
        }
    }
    
    void _loadImages(const _Range& range) {
        using namespace MDCTools;
        
        constexpr size_t ChunkImgCount = 16; // Number of images to read at a time
        if (!range.len) return; // Short-circuit if there are no images to read in this range
        
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) throw std::runtime_error("MTLCreateSystemDefaultDevice returned nil");
        Renderer renderer(device, [device newDefaultLibrary], [device newCommandQueue]);
        
        std::unique_ptr<uint8_t[]> buf = std::make_unique<uint8_t[]>(ChunkImgCount * ImgSD::ImgPaddedLen);
        sdRead(range.idx * ImgSD::ImgPaddedLen);
        
        for (size_t i=0; i<range.len;) {
            const size_t chunkImgCount = std::min(ChunkImgCount, range.len-i);
            readout(buf.get(), chunkImgCount*ImgSD::ImgPaddedLen);
            printf("Read %ju images\n", (uintmax_t)chunkImgCount);
            
            _addImages(renderer, buf.get(), chunkImgCount);
            i += chunkImgCount;
        }
        
        // Make sure all rendering is complete
        renderer.commitAndWait();
    }
    
    void _addImages(MDCTools::Renderer& renderer, const uint8_t* data, size_t imgCount) {
        using namespace MDCTools;
        using namespace MDCStudio::ImagePipeline;
        
        // We're intentionally not holding onto the vended library (imgLib()->vend()) because
        // we don't want to hold the library lock while we process images, since that would
        // block the main thread.
        // Instead we access methods via imgLibVendor->method(), which only acquires the
        // image library lock for the duration of the function call.
        auto& imgLibVendor = *imgLib();
        
        // Reserve space for `imgCount` additional images
        imgLibVendor->reserve(imgCount);
        
        for (size_t idx=0; idx<imgCount; idx++) {
            const uint8_t* imgData = data+idx*ImgSD::ImgPaddedLen;
            const Img::Header& imgHeader = *(const Img::Header*)imgData;
            const auto recordRefIter = imgLibVendor->reservedBegin()+idx;
            ImageRef& imageRef = *imgLibVendor->recordGet(recordRefIter);
            
            // Validate checksum
            const uint32_t checksumExpected = ChecksumFletcher32(imgData, Img::ChecksumOffset);
            uint32_t checksumGot = 0;
            memcpy(&checksumGot, imgData+Img::ChecksumOffset, Img::ChecksumLen);
            if (checksumGot != checksumExpected) {
                throw Toastbox::RuntimeError("invalid checksum (expected:0x%08x got:0x%08x)", checksumExpected, checksumGot);
            }
            
            // Populate ImageRef fields
            {
                imageRef.id = imgHeader.id;
            }
            
            // Render the thumbnail into the ImageLibrary
            {
                const ImageLibrary::Chunk& chunk = *recordRefIter->chunk;
                
                Pipeline::RawImage rawImage = {
                    .cfaDesc = {
                        CFAColor::Green, CFAColor::Red,
                        CFAColor::Blue, CFAColor::Green,
                    },
                    .width = Img::PixelWidth,
                    .height = Img::PixelHeight,
                    .pixels = (ImagePixel*)(imgData+Img::PixelsOffset),
                };
                
                const Pipeline::Options pipelineOpts = {
                    .reconstructHighlights  = { .en = true, },
                    .debayerLMMSE           = { .applyGamma = true, },
                };
                
                Pipeline::Result renderResult = Pipeline::Run(renderer, rawImage, pipelineOpts);
                const size_t thumbDataOff = (uintptr_t)&imageRef.thumbData - (uintptr_t)chunk.mmap.data();
                
                RenderThumb::Options thumbOpts = {
                    .thumbWidth = ImageRef::ThumbWidth,
                    .thumbHeight = ImageRef::ThumbHeight,
                    .dst = (void*)chunk.mmap.data(),
                    .dstOff = thumbDataOff,
                    .dstCap = chunk.mmap.len(),
                };
                
                RenderThumb::Run(renderer, thumbOpts, renderResult.txt);
            }
        }
        
        // Add the records that we previously reserved
        imgLibVendor->add();
    }
    
    const _Path _devDir;
    
    struct {
        std::mutex lock; // Protects this struct
        ImageLibraryPtr imgLib;
        std::thread updateImageLibraryThread;
    } _state;
};

using MDCDevicePtr = std::shared_ptr<MDCDevice>;
