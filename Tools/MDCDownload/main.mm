#import <Foundation/Foundation.h>
#import <chrono>
#import "Shared/MDCDeviceHard.h"
#import "Shared/ImageExporter/ImageExporter.h"
#import "Shared/JThread.h"
#import "Shared/MSPDebug.h"
#import "Lib/Toastbox/SignalQueue.h"
#import "Lib/Toastbox/String.h"
#import "Lib/Toastbox/NumForStr.h"
#import "Lib/Toastbox/FileDescriptor.h"
#import "Lib/Toastbox/Defer.h"
#import "STMApp.elf.h"
#import "ICEApp.bin.h"
using namespace MDCStudio;
namespace fs = std::filesystem;

using ImgIds = std::set<Img::Id, std::greater<Img::Id>>;

#define ProgramName "MDCDownload"
const fs::path ImageFileNameExtension = fs::path(".") += ImageExporter::Formats::DNG.extension;

static MDCDeviceHardPtr _DeviceGet() {
    auto usbDevs = MDCUSBDevice::DevicesGet();
    if (usbDevs.empty()) {
        throw Toastbox::RuntimeError("no devices connected");
    } else if (usbDevs.size() > 1) {
        throw Toastbox::RuntimeError("more than one device connected");
    }
    
    // Create our final MDCDevice instance
    try {
        return Object::Create<MDCDeviceHard>(std::move(usbDevs.at(0)));
    
    } catch (const MDCUSBDevice::IncompatibleVersion& e) {
        // Ignore failures to create MDCDevice
        throw Toastbox::RuntimeError("MDCUSBDevice has incompatible version: %s\n", e.what());
    
    } catch (const std::exception& e) {
        // Ignore failures to create MDCDevice
        throw Toastbox::RuntimeError("Failed to create MDCDeviceHard: %s\n", e.what());
    }
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
    if (fileName.extension() != ImageFileNameExtension) return std::nullopt;
    const fs::path stem = fs::path(fileName).stem();
    auto parts = Toastbox::String::Split(stem.c_str(), "-");
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

static fs::path _DesktopDir() {
    auto urls = [[NSFileManager defaultManager] URLsForDirectory:NSDesktopDirectory inDomains:NSUserDomainMask];
    if (![urls count]) throw Toastbox::RuntimeError("failed to get NSDesktopDirectory");
    return [urls[0] fileSystemRepresentation];
}

static fs::path _RootDir() {
    static fs::path Path = _DesktopDir() / ProgramName "-Data";
    return Path;
}

static fs::path _LogFilePath() {
    return _RootDir() / "Log.txt";
}

static fs::path _OutputDir(std::string_view serial) {
    return _RootDir() / ("Photon-" + std::string(serial));
}

struct Term {
    FILE* file = nullptr;
    Toastbox::FileDescriptor fd;
    bool tty = false;
};

static Term _LogAndTermOutputInit(const fs::path& logFilePath) {
    Term term;
    {
//        FILE* term2 = fopen("/dev/tty", "w");
//        if (!term2) throw Toastbox::RuntimeError("fopen failed: %s", strerror(errno));
//        setvbuf(term2, nullptr, _IOLBF, 0);
        
        // Move the terminal tty fd out of the way
        int ir = dup(STDOUT_FILENO);
        if (ir < 0) throw Toastbox::RuntimeError("dup failed: %s", strerror(errno));
        Toastbox::FileDescriptor fd(ir);
        const bool tty = isatty(fd);
        
        FILE* file = fdopen(fd, "w");
        if (!file) throw Toastbox::RuntimeError("fopen failed: %s", strerror(errno));
        setvbuf(file, nullptr, _IOLBF, 0);
        term = {
            .file = file,
            .fd = std::move(fd),
            .tty = tty,
        };
    }
    
    // Route stdout to `logFilePath`
    {
        std::filesystem::create_directories(logFilePath.parent_path());
        FILE* fr = freopen(logFilePath.c_str(), "a+", stdout);
        if (!fr) throw Toastbox::RuntimeError("freopen failed: %s", strerror(errno));
        // Ensure stdout is line-buffered
        setvbuf(stdout, nullptr, _IOLBF, 0);
    }
    
    return term;
    
//    constexpr int OpenFlags = O_RDWR|O_CREAT|O_APPEND|O_CLOEXEC;
//    constexpr int OpenPerm = (S_IRUSR|S_IWUSR) | (S_IRGRP) | (S_IROTH);
//    ir = openat(STDOUT_FILENO, logFilePath.c_str(), OpenFlags, OpenPerm);
//    if (ir < 0) throw Toastbox::RuntimeError("openat failed: %s", strerror(errno));
//    Toastbox::FileDescriptor stdoutFd(ir);
}

static std::string _CurrentDateTimeString() {
    return Time::StringForTimeInstant(Time::Clock::TimeInstantFromTimePoint(Time::Clock::now()));
}

static void _TermClearLine(const Term& term) {
    // Clear the current line if we're printing to a terminal
    if (term.tty) fprintf(term.file, "\033[A\33[2K\r");
}

template<typename ...Args>
static void _TermPrint(const Term& term, const char* fmt, Args&&... args) {
// Silence warning: "Format string is not a string literal (potentially insecure)"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat-security"
    printf(fmt, std::forward<Args>(args)...);
    // Check for term.file so we don't crash if our Term object wasn't fully created
    if (term.file) fprintf(term.file, fmt, std::forward<Args>(args)...);
#pragma clang diagnostic pop
}

int main(int argc, const char* argv[]) {
    constexpr size_t ImageQueueSlotCount = 32;
    using ImageQueue = Toastbox::SignalQueue<ImageDataPtr, ImageQueueSlotCount>;
    ImageQueue imageDataQueue;
    Term term;
    
    try {
        term = _LogAndTermOutputInit(_LogFilePath());
        
        printf("==================================================\n");
        printf(ProgramName " started at %s\n", _CurrentDateTimeString().c_str());
        printf("==================================================\n");
        
        // Configure MDCDeviceHard
        {
            MDCDeviceHard::Config(STMApp_elf, std::size(STMApp_elf), ICEApp_bin, std::size(ICEApp_bin));
        }
        
        _TermPrint(term, "Configuring Photon...\n");
        MDCDeviceHardPtr device = _DeviceGet();
        const fs::path outputDir = _OutputDir(device->serial());
        std::filesystem::create_directories(outputDir);
        _TermPrint(term, "-> Done\n\n");
        
        {
            printf("==================================================\n");
            printf("Device diagnostic data:\n");
            printf("%s\n", device->diagnosticData().c_str());
            printf("==================================================\n");
        }
        
        const MSP::State mspState = device->status().mspState;
        const MDCDeviceHard::ImageRange imgRange = MDCDeviceHard::_GetImageRange(mspState.sd.imgRingBuf(), mspState.sd.imgCap);
        const ImgIds existingImgIds = _GetExistingImgIdsInDir(outputDir);
        ImgIds imgIds;
        for (Img::Id id=imgRange.begin; id!=imgRange.end; id++) {
            if (existingImgIds.find(id) == existingImgIds.end()) {
                imgIds.insert(id);
            }
        }
        
        // Spawn workers that write the image files
        std::vector<JThread> workers;
        {
            const int threadCount = 4;
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
                            const fs::path fileName = ImageExporter::FileNameForImageRecord(rec).replace_extension(ImageFileNameExtension);
                            const fs::path filePath = outputDir / fileName;
                            const Image image = _ImageForImageDataPtr(img);
                            ImageExporter::ExportDNG(rec, image, filePath, filePath.parent_path());
                            
                            printf("Wrote image: %s\n", filePath.c_str());
                        }
                    } catch (const Toastbox::Signal::Stop&) {
                        return;
                    }
                });
            }
        }
        
        // Signal workers to exit when we leave our scope
        // Using Defer so that this works even when an exception is thrown
        Defer(imageDataQueue.push(nullptr));
        
        // Read data from the device and push it into imageDataQueue
        if (!imgIds.empty()) {
            auto cleanup = device->dataReadStart();
            
            _TermPrint(term, "\n");
            size_t imageIdx = 0;
            struct {
                size_t bytes = 0;
                std::chrono::steady_clock::time_point startTime = std::chrono::steady_clock::now();
            } throughput;
            float mbPerSec = 0;
            std::string timeRemaining = "...";
            for (Img::Id id : imgIds) {
                constexpr size_t MB = 1024*1024;
                constexpr size_t ThroughputThreshold = 32*MB;
                if (throughput.bytes > ThroughputThreshold) {
                    using namespace std::chrono;
                    const milliseconds ms = duration_cast<milliseconds>(steady_clock::now() - throughput.startTime);
                    mbPerSec = ((float)throughput.bytes / ms.count()) * (1000. / MB);
                    
                    const size_t imagesRemaining = imgIds.size()-(imageIdx+1);
                    const size_t bytesRemaining = imagesRemaining*ImgSD::Full::ImagePaddedLen;
                    const milliseconds msRemaining((bytesRemaining * ms.count()) / throughput.bytes);
                    const minutes minRemaining = duration_cast<minutes>(msRemaining);
                    const seconds secRemaining = duration_cast<seconds>(msRemaining);
                    if (minRemaining.count()) {
                        timeRemaining = std::to_string(minRemaining.count()) + "m";
                    } else {
                        timeRemaining = std::to_string(secRemaining.count()) + "s";
                    }
                    throughput = {};
                }
                
                const int percentage = (((float)(imageIdx+1) / imgIds.size()) * 100);
                _TermClearLine(term);
                _TermPrint(term, "Image %ju / %ju    %ju%%    %.1f MB/sec    %s remaining\n",
                    (uintmax_t)(imageIdx+1), (uintmax_t)imgIds.size(), (uintmax_t)percentage, mbPerSec, timeRemaining.c_str());
                
                ImageDataPtr img = std::make_unique<ImageData>();
                img->id = id;
                
                const SD::Block sdBlockBegin = _SDBlockForImgId(mspState.sd, id);
                const MDCDeviceHard::_SDRegion sdRegion = { sdBlockBegin, sdBlockBegin+ImgSD::Full::ImageBlockCount };
                const size_t len = std::size(img->data);
                device->_dataRead(sdRegion, img->data, len);
                
                imageDataQueue.push(std::move(img));
                imageIdx++;
                
                throughput.bytes += len;
            }
        }
        
        _TermPrint(term, "Images downloaded successfully!\n");
    
    } catch (std::exception& e) {
        _TermPrint(term, "Error: %s\n", e.what());
    }
    
    return 0;
}
