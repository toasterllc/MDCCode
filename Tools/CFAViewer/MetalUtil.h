#import <Metal/Metal.h>
#import "Assert.h"
#import "MetalTypes.h"

namespace MetalUtil {
    id<MTLTexture> CreateTexture(
        id deviceOrHeap,
        MTLPixelFormat fmt,
        NSUInteger width, NSUInteger height,
        MTLTextureUsage usage=(MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead)
    ) {
        MTLTextureDescriptor* desc = [MTLTextureDescriptor new];
        [desc setTextureType:MTLTextureType2D];
        [desc setStorageMode:MTLStorageModePrivate];
        [desc setWidth:width];
        [desc setHeight:height];
        [desc setPixelFormat:fmt];
        [desc setUsage:usage];
        id<MTLTexture> txt = [deviceOrHeap newTextureWithDescriptor:desc];
        Assert(txt, return nil);
        return txt;
    }
};
