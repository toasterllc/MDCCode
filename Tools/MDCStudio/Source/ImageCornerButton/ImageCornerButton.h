#import <Cocoa/Cocoa.h>

namespace ImageCornerButtonTypes {

enum class Corner {
    BottomLeft,
    BottomRight,
    TopRight,
    TopLeft,
};

} // namespace ImageCornerButtonTypes

@interface ImageCornerButton : NSButton

- (ImageCornerButtonTypes::Corner)corner;
- (void)setCorner:(ImageCornerButtonTypes::Corner)corner;

@end
