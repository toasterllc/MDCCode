#import <Cocoa/Cocoa.h>
#import "ImageSource.h"

NSPrintOperation* PrintImages(NSDictionary<NSPrintInfoAttributeKey,id>* printSettings,
    MDCStudio::ImageSourcePtr imageSource, const MDCStudio::ImageSet& recs, bool order);
