#import <Foundation/Foundation.h>
#import "Shared/MDCDevicesManager.h"
#import "Shared/ImageExporter/ImageExporter.h"
#import "Lib/Toastbox/SignalQueue.h"
#import "Lib/Toastbox/String.h"
#import "Lib/Toastbox/NumForStr.h"
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

static fs::path _OutputDir(std::string_view serial) {
    auto urls = [[NSFileManager defaultManager] URLsForDirectory:NSDesktopDirectory inDomains:NSUserDomainMask];
    if (![urls count]) throw Toastbox::RuntimeError("failed to get NSDesktopDirectory");
    return fs::path([urls[0] fileSystemRepresentation]) / ("MDCDownload-" + std::string(serial));
}

//static void _ImageExport(const ImageDataPtr& img, const fs::path& path) {
//    const Image image = _ImageForImageDataPtr(img);
//    ImageExporter::ExportDNG(rec, image, path);
//    
//}

int main(int argc, const char* argv[]) {
    // Configure MDCDeviceHard
    {
        MDCDeviceHard::Config(STMApp_elf, std::size(STMApp_elf), ICEApp_bin, std::size(ICEApp_bin));
    }
    
    try {
        MDCDeviceHardPtr device = _DeviceGet();
        const fs::path outputDir = _OutputDir(device->serial());
        std::filesystem::create_directories(outputDir);
        
        MSP::State mspState = {};
//        MSP::ImgRingBuf imgRingBuf;
        {
            auto lock = device->deviceLock();
            mspState = device->_device.device->mspStateRead();
        }
        
//        imgRingBuf = MDCDeviceHard::_GetImgRingBuf(mspState.sd);
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
        
        std::vector<std::thread> workers;
        const int threadCount = std::thread::hardware_concurrency();
        for (int i=0; i<threadCount; i++) {
            workers.emplace_back([&](){
                try {
                    for (;;) {
                        const ImageDataPtr img = imageDataQueue.pop();
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
        }
        
//        const uint32_t idxBegin = (imgRingBuf.buf.idx>mspState.sd.imgCap ? imgRingBuf.buf.idx-mspState.sd.imgCap : 0);
//        const uint32_t idxEnd = imgRingBuf.buf.idx;
//        const SD::Block addrBegin = MSP::SDBlockStart(mspState.sd.baseFull, ImgSD::Full::ImageBlockCount, idxBegin);
//        const SD::Block addrEnd = MSP::SDBlockStart(mspState.sd.baseFull, ImgSD::Full::ImageBlockCount, idxEnd);
//        const size_t imageCount = idxEnd-idxBegin;
        
        
//        struct [[gnu::packed]] SDState {
//            // cardId: the SD card's CID, used to determine when the SD card has been
//            // changed, and therefore we need to update `imgCap` and reset `ringBufs`
//            SD::CardId cardId;
//            // imgCap: image capacity; the number of images that bounds the ring buffer
//            uint32_t imgCap;
//            // baseFull / baseThumb: the first block of the full-size and thumb image regions.
//            // The SD card is broken into 2 regions (fullSize, thumbnails), to allow the host
//            // to quickly read the thumbnails.
//            SD::Block baseFull;
//            SD::Block baseThumb;
//            // ringBufs: tracks captured images on the SD card; 2 copies in case there's a
//            // power failure while updating one
//            ImgRingBuf imgRingBufs[2];
//            bool valid;
//            uint8_t _pad;
//        };
        
        
        {
            auto cleanup = device->dataReadStart();
        }
//        device->
        
//        device->
    
    } catch (std::exception& e) {
        printf("Error: %s\n", e.what());
    }
    
    return 0;
}
