#pragma once
#import "ImageSource.h"
#import "Tools/Shared/Color.h"
#import "Tools/Shared/ImagePipeline/ImagePipeline.h"
#import "Calendar.h"

namespace MDCStudio {

static simd::float2 _TimestampPosition(ImageOptions::Corner corner) {
    using X = ImageOptions::Corner;
    switch (corner) {
    case X::BottomRight: return { 1, 0 };
    case X::BottomLeft:  return { 0, 0 };
    case X::TopLeft:     return { 0, 1 };
    case X::TopRight:    return { 1, 1 };
    }
    abort();
}

inline MDCTools::ImagePipeline::Pipeline::Options PipelineOptionsForImage(const ImageRecord& rec,
    const Image& image) {
    
    const ImageInfo& info = rec.info;
    const ImageOptions& opts = rec.options;
    
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
            .en                 = (opts.localContrast.amount!=0 && opts.localContrast.radius!=0),
            .amount             = (float)opts.localContrast.amount,
            .radius             = (float)opts.localContrast.radius,
        },
        
        .timestamp = {
            .string             = (opts.timestamp.show ? Calendar::TimestampString(info.timestamp) : ""),
            .position           = _TimestampPosition(opts.timestamp.corner),
        },
    };
}

} // namespace MDCStudio
