#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import "Toastbox/Mmap.h"

//void CreateThumbBuf() {
//    using ThumbFile = Mmap<uint8_t>;
//    auto dev = MTLCreateSystemDefaultDevice();
//    auto thumbFile = ThumbFile("/Users/dave/Desktop/Thumbs", MAP_PRIVATE);
//    
//    constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeManaged;
//    auto thumbBuf = [dev newBufferWithBytesNoCopy:thumbFile.data() length:thumbFile.byteLen() options:BufOpts deallocator:nil];
//    assert(thumbBuf);
//    
//    NSLog(@"thumbBuf: %p", thumbBuf);
//}

int main(int argc, const char* argv[]) {
    
//    CreateThumbBuf();
    
    return NSApplicationMain(argc, argv);
}
