#import "ImageView.h"
#import "ImageLayer.h"
//using namespace MDCStudio;

@implementation ImageView {
    ImageLayer* _layer;
}

- (instancetype)initWithFrame:(NSRect)rect {
    if (!(self = [super initWithFrame:rect])) return nil;
    
//    CALayer* l = [CALayer new];
////    [l setBackgroundColor:[[NSColor windowBackgroundColor] CGColor]];
//    [self setLayer:l];
//    [self setWantsLayer:true];
    
    _layer = [ImageLayer new];
    [self setLayer:_layer];
    [self setWantsLayer:true];
    return self;
}

//- (void)viewDidMoveToWindow {
//    [super viewDidMoveToWindow];
//    [[self layer] setBackgroundColor:[[[self window] backgroundColor] CGColor]];
//    [NSTimer scheduledTimerWithTimeInterval:1 repeats:true block:^(NSTimer * _Nonnull timer) {
//        NSLog(@"%@", [[self window] backgroundColor]);
//    }];
//    
//    [NSColor windowBackgroundColor]
//}

@end
