#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

@interface ImageLayer : CAMetalLayer
- (void)setTexture:(id<MTLTexture>)txt;
@end
