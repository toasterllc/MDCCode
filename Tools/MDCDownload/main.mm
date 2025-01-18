#import <Foundation/Foundation.h>
#import "Shared/MDCDevicesManager.h"
#import "Shared/ImageExporter/ImageExporter.h"
#import "Shared/JThread.h"
#import "Lib/Toastbox/SignalQueue.h"
#import "Lib/Toastbox/String.h"
#import "Lib/Toastbox/NumForStr.h"
#import "Lib/Toastbox/FileDescriptor.h"
#import "STMApp.elf.h"
#import "ICEApp.bin.h"
using namespace MDCStudio;
namespace fs = std::filesystem;

using ImgIds = std::set<Img::Id, std::greater<Img::Id>>;

static MDCDeviceHardPtr _DeviceGet() {
    MDCDevicesManagerPtr devicesManager = Object::Create<MDCDevicesManager>([] (const MDCUSBDevice::IncompatibleVersion& x) {
            printf("Incompatible device version: %s\n", x.what());
            exit(0);
        });
    
    auto devices = devicesManager->devices();
    if (devices.empty()) {
        throw std::runtime_error("no devices connected");
    } else if (devices.size() > 1) {
        throw std::runtime_error("more than one device connected");
    }
    return *devices.begin();
}

static uint32_t _IdxForImgId(const MSP::SDState& sd, Img::Id id) {
    const MSP::ImgRingBuf imgRingBuf = sd.imgRingBuf();
    assert(imgRingBuf.buf.id > id);
    const Img::Id off64 = imgRingBuf.buf.id-id;
    assert(off64 <= sd.imgCap); // Ensure the image is in range; ie we're not trying to read an image that's been overwritten
    const uint32_t off = (uint32_t)off64;
    const uint32_t idx = (imgRingBuf.buf.idx>=off ? imgRingBuf.buf.idx-off : sd.imgCap-(off-imgRingBuf.buf.idx));
    return idx;
}

static SD::Block _SDBlockForImgId(const MSP::SDState& sd, Img::Id id) {
    const uint32_t idx = _IdxForImgId(sd, id);
    return MSP::SDBlockStart(sd.baseFull, ImgSD::Full::ImageBlockCount, idx);
}

struct ImageData {
    Img::Id id = 0;
    uint8_t data[ImgSD::Full::ImagePaddedLen] = {};
};
using ImageDataPtr = std::unique_ptr<ImageData>;

static const Img::Header& _ImgHeaderForImageDataPtr(const ImageDataPtr& img) {
    const Img::Header& header = *(Img::Header*)&*img->data;
    assert(header.magic.u24 == Img::Header::MagicNumber.u24);
    assert(header.version == Img::Header::Version);
    return header;
}

static Image _ImageForImageDataPtr(const ImageDataPtr& img) {
    const Img::Header& header = _ImgHeaderForImageDataPtr(img);
    const size_t pixelCount = header.imageWidth*header.imageHeight;
    auto data = std::make_unique<Img::Pixel[]>(pixelCount);
    memcpy(data.get(), img->data+sizeof(Img::Header), pixelCount*sizeof(Img::Pixel));
    return {
        .width = header.imageWidth,
        .height = header.imageHeight,
        .cfaDesc = ImageSource::_CFADesc,
        .data = std::move(data),
    };
}

static ImageRecord _ImageRecordForImageDataPtr(const ImageDataPtr& img) {
    const auto illum = ColorMatrixForInterpolation(1).illum;
    const Img::Header& header = _ImgHeaderForImageDataPtr(img);
    assert(img->id == header.id); // Verify that the image id is what we expect
    return ImageRecord{
        .info = {
            .id = header.id,
            .timestamp = header.timestamp,
            .batteryLevelMv = header.batteryLevelMv,
        },
        .options = {
            .whiteBalance = {
                .illum = { illum[0], illum[1], illum[2] },
            },
        },
    };
}

static std::optional<Img::Id> _ImgIdForFileName(const fs::path& fileName) {
    const fs::path basename = fs::path(fileName).replace_extension();
    auto parts = Toastbox::String::Split(basename.c_str(), "-");
    if (parts.size() != 2) return std::nullopt;
    if (parts.at(0) != "Image") return std::nullopt;
    try {
        return Toastbox::IntForStr<Img::Id>(parts.at(1));
    } catch (...) {
        return std::nullopt;
    }
}

static ImgIds _GetExistingImgIdsInDir(const fs::path& dir) {
    ImgIds ids;
    for (const fs::path& p : fs::directory_iterator(dir)) {
        const std::optional<Img::Id> id = _ImgIdForFileName(p.filename());
        if (!id) continue;
        ids.insert(*id);
    }
    return ids;
}



static fs::path __DesktopDir() {
    auto urls = [[NSFileManager defaultManager] URLsForDirectory:NSDesktopDirectory inDomains:NSUserDomainMask];
    if (![urls count]) throw Toastbox::RuntimeError("failed to get NSDesktopDirectory");
    return [urls[0] fileSystemRepresentation];
}

static fs::path _DesktopDir() {
    static fs::path Path = __DesktopDir();
    return Path;
}

static fs::path _LogFilePath() {
    return _DesktopDir() / "MDCDownload-Log.txt";
}

static fs::path _OutputDir(std::string_view serial) {
    return _DesktopDir() / ("MDCDownload-" + std::string(serial));
}

struct Term {
    FILE* file = nullptr;
};

static Term _LogAndTermOutputInit(const fs::path& logFilePath) {
//    // Move the terminal tty fd out of the way
//    int ir = dup(STDOUT_FILENO);
//    if (ir < 0) throw Toastbox::RuntimeError("dup failed: %s", strerror(errno));
//    Toastbox::FileDescriptor termFd(ir);
    
    FILE* term = fopen("/dev/tty", "w+");
    if (!term) throw Toastbox::RuntimeError("fopen failed: %s", strerror(errno));
    setvbuf(term, nullptr, _IOLBF, 0);
    
    // Route stdout to `logFilePath`
    FILE* fr = freopen(logFilePath.c_str(), "a+", stdout);
    if (!fr) throw Toastbox::RuntimeError("freopen failed: %s", strerror(errno));
    // Ensure stdout is line-buffered
    setvbuf(stdout, nullptr, _IOLBF, 0);
    
    return { term };
    
//    constexpr int OpenFlags = O_RDWR|O_CREAT|O_APPEND|O_CLOEXEC;
//    constexpr int OpenPerm = (S_IRUSR|S_IWUSR) | (S_IRGRP) | (S_IROTH);
//    ir = openat(STDOUT_FILENO, logFilePath.c_str(), OpenFlags, OpenPerm);
//    if (ir < 0) throw Toastbox::RuntimeError("openat failed: %s", strerror(errno));
//    Toastbox::FileDescriptor stdoutFd(ir);
}

int main(int argc, const char* argv[]) {
    Term term = _LogAndTermOutputInit(_LogFilePath());
    
    // Configure MDCDeviceHard
    {
        MDCDeviceHard::Config(STMApp_elf, std::size(STMApp_elf), ICEApp_bin, std::size(ICEApp_bin));
    }
    
    try {
//        std::ofstream f;
//        f.exceptions(std::ofstream::failbit | std::ofstream::badbit);
//        f.open(_StatePath(dir));
//        f.write((char*)&state, sizeof(state));
        
        MDCDeviceHardPtr device = _DeviceGet();
        const fs::path outputDir = _OutputDir(device->serial());
        std::filesystem::create_directories(outputDir);
        
        MSP::State mspState = {};
        {
            auto lock = device->deviceLock();
            mspState = device->_device.device->mspStateRead();
        }
        
        const MDCDeviceHard::ImageRange imgRange = MDCDeviceHard::_GetImageRange(mspState.sd.imgRingBuf(), mspState.sd.imgCap);
        const ImgIds existingImgIds = _GetExistingImgIdsInDir(outputDir);
        ImgIds imgIds;
        for (Img::Id id=imgRange.begin; id!=imgRange.end; id++) {
            if (existingImgIds.find(id) == existingImgIds.end()) {
                imgIds.insert(id);
            }
        }
        
        constexpr size_t ImageQueueSlotCount = 32;
        using ImageQueue = Toastbox::SignalQueue<ImageDataPtr, ImageQueueSlotCount>;
        ImageQueue imageDataQueue;
        
        // Spawn workers that write the image files
        std::vector<JThread> workers;
        {
            const int threadCount = std::thread::hardware_concurrency();
            for (int i=0; i<threadCount; i++) {
                workers.emplace_back([&](){
                    try {
                        for (;;) {
                            const ImageDataPtr img = imageDataQueue.pop();
                            
                            // Check for our signal to bail
                            if (!img) {
                                // Call stop() on the read end, not on the write end!
                                // If we called stop() on the write end, there could
                                // still be unread elements in the queue.
                                imageDataQueue.stop();
                                break;
                            }
                            
                            const ImageRecord rec = _ImageRecordForImageDataPtr(img);
                            const fs::path fileName = ImageExporter::FileNameForImageRecord(rec).replace_extension(ImageExporter::Formats::DNG.extension);
                            const fs::path filePath = outputDir / fileName;
                            const Image image = _ImageForImageDataPtr(img);
                            ImageExporter::ExportDNG(rec, image, filePath);
                            
                            printf("Wrote image: %s\n", filePath.c_str());
                        }
                    } catch (const Toastbox::Signal::Stop&) {
                        return;
                    }
                });
            }
        }
        
        {
            auto cleanup = device->dataReadStart();
            
            for (Img::Id id : imgIds) {
                printf("Downloading image id %ju\n", (uintmax_t)id);
                
                ImageDataPtr img = std::make_unique<ImageData>();
                img->id = id;
                
                const SD::Block sdBlockBegin = _SDBlockForImgId(mspState.sd, id);
                const MDCDeviceHard::_SDRegion sdRegion = { sdBlockBegin, sdBlockBegin+ImgSD::Full::ImageBlockCount };
                device->_dataRead(sdRegion, img->data, std::size(img->data));
                
                imageDataQueue.push(std::move(img));
            }
            
            // Signal workers to exit
            imageDataQueue.push(nullptr);
        }
    
    } catch (std::exception& e) {
        printf("Error: %s\n", e.what());
    }
    
    return 0;
}
