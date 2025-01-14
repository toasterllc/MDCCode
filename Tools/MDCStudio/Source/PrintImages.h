#import <Cocoa/Cocoa.h>
#import "Shared/ImageSource.h"

NSPrintOperation* PrintImages(NSDictionary<NSPrintInfoAttributeKey,id>* printSettings,
    MDCStudio::ImageSourcePtr imageSource, const MDCStudio::ImageSet& recs, bool order);
