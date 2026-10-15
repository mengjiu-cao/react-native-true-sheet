//
//  This source code is licensed under the MIT license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "TrueSheetRootView.h"
#import "TrueSheetChromeGeometry.h"

#import <QuartzCore/QuartzCore.h>

static CGPathRef TrueSheetCreateCornerPath(CGSize size, const truesheet::ChromeGeometry &geometry) {
  const CGFloat width = size.width, height = size.height;
  const CGFloat left = geometry.top.left, right = geometry.top.right, bottom = geometry.bottom;
  CGMutablePathRef path = CGPathCreateMutable();
  CGPathMoveToPoint(path, nullptr, 0, height - bottom);
  CGPathAddLineToPoint(path, nullptr, 0, left);
  if (left > 0) {
    CGPathAddArc(path, nullptr, left, left, left, M_PI, 1.5 * M_PI, false);
  }
  CGPathAddLineToPoint(path, nullptr, width - right, 0);
  if (right > 0) {
    CGPathAddArc(path, nullptr, width - right, right, right, 1.5 * M_PI, 2 * M_PI, false);
  }
  CGPathAddLineToPoint(path, nullptr, width, height - bottom);
  if (bottom > 0) {
    CGPathAddArc(path, nullptr, width - bottom, height - bottom, bottom, 0, M_PI_2, false);
  }
  CGPathAddLineToPoint(path, nullptr, bottom, height);
  if (bottom > 0) {
    CGPathAddArc(path, nullptr, bottom, height - bottom, bottom, M_PI_2, M_PI, false);
  }
  CGPathCloseSubpath(path);
  return path;
}

static CGPathRef TrueSheetCreateTopBorderPath(CGFloat width, const truesheet::ChromeGeometry &geometry) {
  const CGFloat inset = geometry.borderWidth / 2;
  const CGFloat left = geometry.top.left, right = geometry.top.right;
  const CGFloat leftStrokeRadius = fmax(left - inset, 0);
  const CGFloat rightStrokeRadius = fmax(right - inset, 0);
  CGMutablePathRef path = CGPathCreateMutable();
  CGPathMoveToPoint(path, nullptr, inset, fmax(left, inset));
  if (leftStrokeRadius > 0) {
    CGPathAddArc(path, nullptr, left, left, leftStrokeRadius, M_PI, 1.5 * M_PI, false);
  }
  CGPathAddLineToPoint(path, nullptr, width - fmax(right, inset), inset);
  if (rightStrokeRadius > 0) {
    CGPathAddArc(path, nullptr, width - right, right, rightStrokeRadius, 1.5 * M_PI, 2 * M_PI, false);
  }
  // Deliberately open: the stroke follows the top corners, never the sides/bottom.
  return path;
}

@interface TrueSheetRootView ()
- (void)initializeChrome;
- (void)updateChromeGeometry;
- (void)updateResolvedColors;
@end

@implementation TrueSheetRootView {
  UIView *_backgroundPlane;
  UIColor *_surfaceColor;
  UIColor *_borderColor;
  CAShapeLayer *_cornerMask;
  CAShapeLayer *_topBorderLayer;
  CGFloat _leftRadius;
  CGFloat _rightRadius;
  CGFloat _bottomRadius;
  CGFloat _borderWidth;
  BOOL _usesIndependentCorners;
  BOOL _hasGeometry;
  BOOL _cachedIndependentCorners;
  CGRect _cachedBounds;
  truesheet::ChromeGeometry _cachedGeometry;
}

- (instancetype)initWithFrame:(CGRect)frame {
  if (self = [super initWithFrame:frame]) {
    [self initializeChrome];
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  if (self = [super initWithCoder:coder]) {
    [self initializeChrome];
  }
  return self;
}

- (void)initializeChrome {
  // Matches NativeSheetContainerView.swift's NativeSheetViewController.loadView:
  // a native UIView root with an owned background below hosted content. Unlike
  // painting both surfaces, a single color plane preserves translucent colors.
  self.backgroundColor = UIColor.clearColor;
  self.opaque = NO;
  self.clipsToBounds = YES;
  _backgroundPlane = [[UIView alloc] initWithFrame:self.bounds];
  _backgroundPlane.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  _backgroundPlane.userInteractionEnabled = NO;
  _backgroundPlane.accessibilityElementsHidden = YES;
  _backgroundPlane.hidden = YES;
  [self addSubview:_backgroundPlane];
}

- (void)didAddSubview:(UIView *)subview {
  [super didAddSubview:subview];
  // TrueSheetBlurView inserts itself at index zero. Keep that native effect and
  // all content above our plane without coupling this view to the blur class.
  if (subview != _backgroundPlane && _backgroundPlane.superview == self) {
    [self sendSubviewToBack:_backgroundPlane];
  }
}

- (void)configureBackgroundColor:(UIColor *)color
                 topBorderWidth:(CGFloat)width
                 topBorderColor:(UIColor *)borderColor
            topLeftCornerRadius:(NSNumber *)left
           topRightCornerRadius:(NSNumber *)right
           fallbackCornerRadius:(CGFloat)radius
             bottomCornerRadius:(CGFloat)bottomRadius {
  BOOL colorsChanged = _surfaceColor != color || _borderColor != borderColor;
  _surfaceColor = color;
  _borderColor = borderColor;
  _usesIndependentCorners = left != nil || right != nil;
  _leftRadius = truesheet::nonnegative(left != nil ? left.doubleValue : radius);
  _rightRadius = truesheet::nonnegative(right != nil ? right.doubleValue : radius);
  _bottomRadius = _usesIndependentCorners ? truesheet::nonnegative(bottomRadius) : 0;
  _borderWidth = truesheet::nonnegative(width);
  [self updateChromeGeometry];
  if (colorsChanged) {
    [self updateResolvedColors];
  }
}

- (void)layoutSubviews {
  [super layoutSubviews];
  if (!CGRectEqualToRect(_backgroundPlane.frame, self.bounds)) {
    _backgroundPlane.frame = self.bounds;
  }
  [self updateChromeGeometry];
}

- (void)updateChromeGeometry {
  const CGRect bounds = self.bounds;
  const auto geometry = truesheet::chromeGeometry(CGRectGetWidth(bounds), CGRectGetHeight(bounds),
    _leftRadius, _rightRadius, _bottomRadius, _borderWidth);
  if (_hasGeometry && CGRectEqualToRect(_cachedBounds, bounds) &&
      _cachedIndependentCorners == _usesIndependentCorners &&
      _cachedGeometry.top.left == geometry.top.left && _cachedGeometry.top.right == geometry.top.right &&
      _cachedGeometry.bottom == geometry.bottom && _cachedGeometry.borderWidth == geometry.borderWidth) {
    return;
  }
  _hasGeometry = YES;
  _cachedBounds = bounds;
  _cachedIndependentCorners = _usesIndependentCorners;
  _cachedGeometry = geometry;

  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  if (_usesIndependentCorners) {
    if (!_cornerMask) {
      _cornerMask = [CAShapeLayer layer];
      _cornerMask.fillColor = UIColor.blackColor.CGColor;
    }
    _cornerMask.contentsScale = self.traitCollection.displayScale;
    _cornerMask.frame = bounds;
    CGPathRef path = TrueSheetCreateCornerPath(bounds.size, geometry);
    _cornerMask.path = path;
    CGPathRelease(path);
    self.layer.mask = _cornerMask;
  } else if (self.layer.mask == _cornerMask) {
    // Without explicit per-corner overrides, UIKit retains uniform clipping.
    self.layer.mask = nil;
  }

  if (geometry.borderWidth > 0) {
    if (!_topBorderLayer) {
      _topBorderLayer = [CAShapeLayer layer];
      _topBorderLayer.fillColor = nil;
      _topBorderLayer.lineCap = kCALineCapButt;
      _topBorderLayer.zPosition = 1;
      [self.layer addSublayer:_topBorderLayer];
      [self updateResolvedColors];
    }
    _topBorderLayer.hidden = NO;
    _topBorderLayer.contentsScale = self.traitCollection.displayScale;
    _topBorderLayer.frame = bounds;
    _topBorderLayer.lineWidth = geometry.borderWidth;
    CGPathRef path = TrueSheetCreateTopBorderPath(CGRectGetWidth(bounds), geometry);
    _topBorderLayer.path = path;
    CGPathRelease(path);
  } else {
    _topBorderLayer.hidden = YES;
  }
  [CATransaction commit];
}

- (void)updateResolvedColors {
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  _backgroundPlane.hidden = _surfaceColor == nil;
  _backgroundPlane.backgroundColor = _surfaceColor;
  _topBorderLayer.strokeColor = [(_borderColor ?: UIColor.separatorColor)
    resolvedColorWithTraitCollection:self.traitCollection].CGColor;
  [CATransaction commit];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
  [super traitCollectionDidChange:previousTraitCollection];
  [self updateResolvedColors];
  _cornerMask.contentsScale = self.traitCollection.displayScale;
  _topBorderLayer.contentsScale = self.traitCollection.displayScale;
}

- (BOOL)accessibilityPerformEscape {
  // VoiceOver walks from the focused content to this native root.
  return [self.accessibilityController accessibilityPerformEscape];
}

@end
