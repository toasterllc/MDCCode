#import <Cocoa/Cocoa.h>

namespace ImageCornerButtonTypes {

enum class Corner {
    BottomRight,
    BottomLeft,
    TopLeft,
    TopRight,
};

} // namespace ImageCornerButtonTypes

@interface ImageCornerButton : NSButton

- (ImageCornerButtonTypes::Corner)corner;
- (void)setCorner:(ImageCornerButtonTypes::Corner)corner;

@end
