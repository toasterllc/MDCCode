#pragma once
#import "ImageSource.h"
#import "Tools/Shared/ImagePipeline/ImagePipeline.h"
#import "Code/Lib/Toastbox/Mac/Color.h"
#import "ImageCorner/ImageCorner.h"
#import "Calendar.h"
#import "PrefsUtil.h"

namespace MDCStudio {

static simd::float2 _TimestampPosition(ImageCorner corner) {
    switch (corner) {
    case ImageCorner::BottomRight: return { 1, 0 };
    case ImageCorner::BottomLeft:  return { 0, 0 };
    case ImageCorner::TopLeft:     return { 0, 1 };
    case ImageCorner::TopRight:    return { 1, 1 };
    }
    abort();
}

inline ImagePipeline::Pipeline::Options PipelineOptionsForImage(const ImageRecord& rec,
    const Image& image, bool includeTimestamp) {
    
    const ImageInfo& info = rec.info;
    const ImageOptions& opts = rec.options;
    const ImageCorner timestampCorner = PrefsUtil::TimestampImageCorner();
    
    return {
        .cfaDesc                = image.cfaDesc,
        
        .illum                  = ColorRaw(opts.whiteBalance.illum),
        .colorMatrix            = ColorMatrix((double*)opts.whiteBalance.colorMatrix),
        
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
        
        .timestamp = {
            .string             = (includeTimestamp ? Calendar::TimestampString(info.timestamp) : ""),
            .position           = (includeTimestamp ? _TimestampPosition(timestampCorner) : simd::float2{}),
        },
    };
}

} // namespace MDCStudio
