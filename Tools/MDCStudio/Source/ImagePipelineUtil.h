#pragma once
#import "ImageSource.h"
#import "Tools/Shared/Color.h"
#import "Tools/Shared/ImagePipeline/ImagePipeline.h"

namespace MDCStudio {

inline MDCTools::ImagePipeline::Pipeline::Options PipelineOptionsForImage(const ImageOptions& opts, const Image& image) {
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
    };
}

} // namespace MDCStudio
