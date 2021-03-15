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
    
    id<MTLRenderPipelineState> CreatePipelineState(
        id<MTLDevice> device,
        id<MTLLibrary> lib,
        NSString* vname,
        NSString* fname,
        MTLPixelFormat fmt
    ) {
        NSParameterAssert(name);
        id<MTLFunction> vertexShader = [lib newFunctionWithName:vname];
        Assert(vertexShader, return nil);
        id<MTLFunction> fragmentShader = [lib newFunctionWithName:fname];
        Assert(fragmentShader, return nil);
        
        MTLRenderPipelineDescriptor* pipelineDescriptor = [MTLRenderPipelineDescriptor new];
        [pipelineDescriptor setVertexFunction:vertexShader];
        [pipelineDescriptor setFragmentFunction:fragmentShader];
        [[pipelineDescriptor colorAttachments][0] setPixelFormat:fmt];
        id<MTLRenderPipelineState> ps = [device newRenderPipelineStateWithDescriptor:pipelineDescriptor
            error:nil];
        Assert(ps, return nil);
        return ps;
    }
    
    template <typename Fn>
    void RenderPass(
        id<MTLCommandBuffer> cmdBuf,
        id<MTLTexture> txt,
        id<MTLRenderPipelineState> ps,
        Fn fn
    ) {
        
        NSParameterAssert(cmdBuf);
        NSParameterAssert(texture);
        NSParameterAssert(ps);
        
        MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor new];
        [[renderPassDescriptor colorAttachments][0] setTexture:txt];
        [[renderPassDescriptor colorAttachments][0] setLoadAction:MTLLoadActionLoad];
        [[renderPassDescriptor colorAttachments][0] setClearColor:{0,0,0,1}];
        [[renderPassDescriptor colorAttachments][0] setStoreAction:MTLStoreActionStore];
        id<MTLRenderCommandEncoder> encoder = [cmdBuf renderCommandEncoderWithDescriptor:renderPassDescriptor];
        
        [encoder setRenderPipelineState:ps];
        [encoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [encoder setCullMode:MTLCullModeNone];
        
        fn(encoder);
        
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle
            vertexStart:0 vertexCount:CFAViewer::MetalTypes::SquareVertIdxCount];
        
        [encoder endEncoding];
    }
};
