#pragma once
#import "Shared/ImageSource.h"
#import "Shared/ImagePipeline/ImagePipeline.h"
#import "Shared/ImageCorner/ImageCorner.h"
#import "Shared/PrefsUtil.h"
#import "Lib/Toastbox/Mac/Color.h"
#import "Calendar.h"

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

inline ImagePipeline::Pipeline::Options PipelineOptionsForImage(const ImageRecord& rec, const Image& image) {
    const ImageInfo& info = rec.info;
    const ImageOptions& opts = rec.options;
    const bool includeTimestamp = PrefsUtil::Timestamp::Visible();
    const ImageCorner timestampCorner = PrefsUtil::Timestamp::Corner();
    
    return {
        .cfaDesc                = image.cfaDesc,
        
        .illum                  = ColorRaw(opts.whiteBalance.illum),
        .colorMatrix            = ColorMatrix((double*)opts.whiteBalance.colorMatrix),
        
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
