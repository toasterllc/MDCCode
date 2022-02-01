#import <Foundation/Foundation.h>
#import <filesystem>
#import "MSP.h"
#import "MDCUSBDevice.h"
#import "ImageLibrary.h"

class MDCDevice : public MDCUSBDevice {
public:
    using MDCUSBDevice::MDCUSBDevice;
    
    MDCDevice(USBDevice&& dev) : MDCUSBDevice(std::move(dev)) {
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
            auto urls = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask];
            if (![urls count]) throw Toastbox::RuntimeError("failed to get NSApplicationSupportDirectory");
            
            const _Path appSupportDir = _Path([urls[0] fileSystemRepresentation]) / [[[NSBundle mainBundle] bundleIdentifier] UTF8String];
            std::filesystem::create_directories(appSupportDir);
            
            _state.imgLib = std::make_shared<ImageLibrary>(appSupportDir / "ImageLibrary");
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
        const MSP::ImgRingBuf* imgRingBuf = &state.img.ringBuf;
        const MSP::ImgRingBuf* imgRingBuf2 = &state.img.ringBuf2;
        const bool br = MSP::ImgRingBuf::FindLatest(imgRingBuf, imgRingBuf2);
        if (!br) throw Toastbox::RuntimeError("both image ring buffers are invalid");
        return *imgRingBuf;
    }
    
    void _threadUpdateImageLibrary() {
        try {
            mspConnect();
            
            MSP::State state;
            mspRead(MSP::StateAddr, &state, sizeof(state));
            
            if (state.magic != MSP::State::MagicNumber) {
                // Program MSPApp
            }
            
            if (state.version > MSP::State::Version) {
                // Newer version than we understand -- tell user to upgrade or re-program
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
            
            mspDisconnect();
            
            const SD::CardId cardId = sdCardIdGet();
            
            printf("cardId:     ");
            for (size_t i=0; i<sizeof(cardId); i++) {
                printf("%02x ", ((uint8_t*)&cardId)[i]);
            }
            printf("\n");
            
            const SD::CardData cardData = sdCardDataGet();
            printf("cardData:   ");
            for (size_t i=0; i<sizeof(cardData); i++) {
                printf("%02x ", ((uint8_t*)&cardData)[i]);
            }
            printf("\n");
            
            const MSP::ImgRingBuf& imgRingBuf = _GetImgRingBuf(state);
            
            #warning TODO: if the user keeps deleting images from the end of the local library, we'll unnecessarily
            #warning TODO: re-download those images every time this function runs, since the library.back() will
            #warning TODO: no longer reference the 'most recent' image.
            #warning TODO: to fix this, we should keep track of the most recent image downloaded from
            #warning TODO: the device, and use that to determine which images should be downloaded
            {
                ImageLibrary& il = *imgLib();
                auto ilLock = std::unique_lock(il.lock);
                
                // Remove images: lib has, device doesn't
                if (il.recordCount()) {
                    const Img::Id deviceImgIdBegin = imgRingBuf.buf.idBegin;
                    
                    const auto removeBegin = il.begin();
                    
                    // Find the first image >= `deviceImgIdBegin`
                    const auto removeEnd = std::lower_bound(il.begin(), il.end(), 0,
                        [&](const ImageLibrary::RecordRef& sample, auto) -> bool {
                            return il.recordGet(sample)->id < deviceImgIdBegin;
                        });
                    
                    printf("Removing %ju images\n", (uintmax_t)std::distance(removeBegin, removeEnd));
                    il.remove(removeBegin, removeEnd);
                }
                
                // Add images: device has, lib doesn't
                {
                    const Img::Id libImgIdEnd = (!il.empty() ? il.recordGet(il.back())->id+1 : 0);
                    const Img::Id deviceImgIdEnd = imgRingBuf.buf.idEnd;
                    
                    if (libImgIdEnd > deviceImgIdEnd) {
                        throw Toastbox::RuntimeError("image library claims to have newer images than the device (libImgIdEnd: %ju, deviceImgIdEnd: %ju)",
                            (uintmax_t)libImgIdEnd,
                            (uintmax_t)deviceImgIdEnd
                        );
                    }
                    
                    const size_t addCount = deviceImgIdEnd-libImgIdEnd;
                    
                    const size_t region1Idx     = imgRingBuf.buf.widx - std::min((size_t)imgRingBuf.buf.widx, addCount);
                    const size_t region1Count   = imgRingBuf.buf.widx - region1Idx;
                    
                    const size_t region0Count   = addCount - region1Count;
                    const size_t region0Idx     = state.img.cap - region0Count;
                    
                    
                }
            }
        
        } catch (const std::exception& e) {
            fprintf(stderr, "Failed to update image library: %s", e.what());
        }
    }
    
    struct {
        std::mutex lock;
        ImageLibraryPtr imgLib;
        std::thread updateImageLibraryThread;
    } _state;
};

using MDCDevicePtr = std::shared_ptr<MDCDevice>;
