//
//  This source code is licensed under the MIT license found in the
//  LICENSE file in the root directory of this source tree.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The sheet controller's native root, separate from the Fabric content container.
@interface TrueSheetRootView : UIView

@property (nonatomic, weak, nullable) UIViewController *accessibilityController;

/// Nil background preserves the system surface and the content's native blur.
/// Nil top radii leave uniform clipping to the presentation controller. An explicit
/// radius of zero is square; a missing individual radius uses fallbackCornerRadius.
- (void)configureBackgroundColor:(nullable UIColor *)color
                 topBorderWidth:(CGFloat)width
                 topBorderColor:(nullable UIColor *)borderColor
            topLeftCornerRadius:(nullable NSNumber *)left
           topRightCornerRadius:(nullable NSNumber *)right
           fallbackCornerRadius:(CGFloat)radius
             bottomCornerRadius:(CGFloat)bottomRadius;

@end

NS_ASSUME_NONNULL_END
