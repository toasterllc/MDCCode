#import <Cocoa/Cocoa.h>

namespace ImageCornerButtonTypes {

enum class Corner {
    BottomRight,
    BottomLeft,
    TopLeft,
    TopRight,
    // Mixed: represents multiple values (ie when multiple items are selected with different corners)
    Mixed,
};

} // namespace ImageCornerButtonTypes

@interface ImageCornerButton : NSButton

- (ImageCornerButtonTypes::Corner)corner;
- (void)setCorner:(ImageCornerButtonTypes::Corner)corner;

@end
