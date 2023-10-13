#import "DeviceImageGridHeaderView.h"
#import "date/date.h"
#import "date/tz.h"
#import "Calendar.h"
#import "ImageLibraryStatus.h"
using namespace MDCStudio;

@implementation DeviceImageGridHeaderView {
    __weak id<DeviceImageGridHeaderViewDelegate> _delegate;
    IBOutlet NSLayoutConstraint* _hideLoadPhotosConstraint;
    IBOutlet NSTextField* _statusLabel;
    IBOutlet NSTextField* _loadPhotosCountLabel;
    IBOutlet NSProgressIndicator* _progressIndicator;
}

- (void)setDelegate:(id<DeviceImageGridHeaderViewDelegate>)x {
    _delegate = x;
}

- (void)setSelection:(MDCStudio::ImageSet)selection {
    
}

//__weak auto selfWeak = self;
//{
//    _device->observerAdd([=] {
//        dispatch_async(dispatch_get_main_queue(), ^{ [selfWeak _update]; });
//        return true;
//    });
//}
//
//// Add ourself as an observer of the image library
//{
//    auto lock = std::unique_lock(*_imageLibrary);
//    _imageLibrary->observerAdd([=](const ImageLibrary::Event& ev) {
//        dispatch_async(dispatch_get_main_queue(), ^{ [selfWeak _update]; });
//        return true;
//    });
//}
//
//static std::optional<size_t> _LoadCount(const MDCDevice::Status& status, ImageLibrary& imgLib) {
//    // Short-circut if syncing is in progress.
//    // In that case, we don't want to show the 'Load' button in the header
//    if (status.sync) return std::nullopt;
//    
//    {
//        auto lock = std::unique_lock(imgLib);
//        const Img::Id libImgIdEnd = (!imgLib.empty() ? imgLib.back()->info.id+1 : 0);
//        
//        // Calculate how many images to add to the end of the library: device has, lib doesn't
//        if (libImgIdEnd > status.imgIdEnd) {
//            #warning TODO: how do we properly handle this situation?
//            throw Toastbox::RuntimeError("image library claims to have newer images than the device (libImgIdEnd: %ju, status.imgIdEnd: %ju)",
//                (uintmax_t)libImgIdEnd,
//                (uintmax_t)status.imgIdEnd
//            );
//        }
//        
//        return status.imgIdEnd - std::max(status.imgIdBegin, libImgIdEnd);
//    }
//}

//static std::optional<size_t> _LoadCount(const MDCDevice::Status& status MDCDevicePtr device) {
//    return _LoadCount(device->status(), device->imageLibrary());
//}

- (void)setStatus:(NSString*)x {
    [_statusLabel setStringValue:x];
}

- (void)setLoadCount:(size_t)x {
    if (x) {
        [_loadPhotosCountLabel setStringValue:[NSString stringWithFormat:@"%ju", (uintmax_t)x]];
        [_hideLoadPhotosConstraint setPriority:NSLayoutPriorityDefaultLow];
    } else {
        [_hideLoadPhotosConstraint setPriority:NSLayoutPriorityRequired];
    }
}

- (void)setProgress:(float)x {
    [_progressIndicator setDoubleValue:x];
}

//- (void)_update {
//    const MDCDevice::Status status = _device->status();
//    
//    // Update status
//    {
//        [_statusLabel setStringValue:@(ImageLibraryStatus(*_imageLibrary, "No photos").c_str())];
//    }
//    
//    // Update unloaded photo count
//    {
//        const std::optional<size_t> loadCount = _LoadCount(status, *_imageLibrary);
//        if (loadCount && *loadCount) {
//            [_loadPhotosCountLabel setStringValue:[NSString stringWithFormat:@"%ju", (uintmax_t)*loadCount]];
//            [_hideLoadPhotosConstraint setPriority:NSLayoutPriorityDefaultLow];
//        } else {
//            [_hideLoadPhotosConstraint setPriority:NSLayoutPriorityRequired];
//        }
//    }
//    
//    // Upload load progress
//    {
//        const float progress = (status.sync ? status.sync->progress : 0);
//        [_progressIndicator setDoubleValue:progress];
//    }
//}

- (IBAction)load:(id)sender {
    [_delegate deviceImageGridHeaderViewLoad:self];
}

@end
