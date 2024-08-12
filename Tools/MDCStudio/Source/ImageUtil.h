#pragma once
#import "Lib/Toastbox/Mac/Renderer.h"
#import "ColorMatrix.h"
#import "ImageThumb.h"
#import "ImageLibrary.h"

namespace MDCStudio {

inline void ImageWhiteBalanceSet(ImageWhiteBalance& x, bool automatic, const CCM& ccm) {
    x.automatic = automatic;
    ccm.illum.m.get(x.illum);
    ccm.matrix.get(x.colorMatrix);
}

inline Toastbox::Renderer::Txt ThumbTextureForImageRecord(Toastbox::Renderer& renderer, const ImageRecord& rec) {
    using namespace Toastbox;
    const size_t w = ImageThumb::ThumbWidth;
    const size_t h = ImageThumb::ThumbHeight;
    Renderer::Txt thumbTxt = renderer.textureCreate(ImageThumb::PixelFormat, w, h);
    [thumbTxt replaceRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:0
        slice:0 withBytes:rec.thumb.data bytesPerRow:w*4 bytesPerImage:0];
    return thumbTxt;
}

} // namespace MDCStudio
