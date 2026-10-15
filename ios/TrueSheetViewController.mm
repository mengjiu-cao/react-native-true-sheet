//
//  Created by Jovanni Lo (@lodev09)
//  Copyright (c) 2024-present. All rights reserved.
//
//  This source code is licensed under the MIT license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "TrueSheetViewController.h"
#import "TrueSheetContainerView.h"
#import "TrueSheetContentView.h"
#import "core/TrueSheetBlurView.h"
#import "core/TrueSheetDetentCalculator.h"
#import "core/TrueSheetGrabberView.h"
#import "core/TrueSheetChromeGeometry.h"
#import "core/TrueSheetRootView.h"
#import "utils/BlurUtil.h"
#import "utils/GestureUtil.h"
#import "utils/PlatformUtil.h"
#import "utils/UIView+FirstResponder.h"
#import "utils/WindowUtil.h"

#import <React/RCTLog.h>
#import <React/RCTScrollViewComponentView.h>
#import <objc/runtime.h>
#import <react/renderer/components/TrueSheetSpec/Props.h>

using namespace facebook::react;

typedef struct {
  CGFloat position;
  CGFloat detent;
  CGFloat index;
} TrueSheetPositionState;

static BOOL TrueSheetPositionStateEquals(TrueSheetPositionState a, TrueSheetPositionState b) {
  return fabs(a.position - b.position) <= 0.01 && fabs(a.detent - b.detent) <= 0.01 && fabs(a.index - b.index) <= 0.01;
}

static char TrueSheetAccessibilityWindowOwnerKey;
static char TrueSheetAccessibilityWindowPreviousElementsKey;

@interface TrueSheetViewController ()

- (UIViewController *)accessibilityPresentingViewController;
- (void)restoreWindowAccessibilityElements;
- (void)setSheetAccessibilityElementsHidden:(BOOL)hidden;
- (void)setAccessibilityContentElement:(UIView *)contentView;
- (NSArray *)accessibilityGrabberElements;
- (void)endInteractiveDismissState;
- (void)emitInteractivePosition;
- (void)updateSheetChrome;
- (void)updateEdgeCompensation;
- (void)restoreEdgeCompensation;
- (void)removeOwnedChrome;
- (void)updateOwnedDimmer;
- (void)animateOwnedDimmerVisible:(BOOL)visible;
- (void)animateInteractiveContainerToTransform:(CGAffineTransform)transform
                                      duration:(NSTimeInterval)duration
                          allowUserInteraction:(BOOL)allowUserInteraction
                                    completion:(void (^)(void))completion;

@end

// A snapshot belongs only to this sheet's bounded ancestor chain. Restore each
// property only while it still contains our override; UIKit may reclaim it.
@interface TrueSheetShadowState : NSObject
@property (nonatomic, weak) UIView *view;
@property (nonatomic) float opacity;
@property (nonatomic) CGFloat radius;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, strong) UIBezierPath *path;
@end

@implementation TrueSheetShadowState
@end

// Inverse scaling can expose content outside UIKit's wrapper hit bounds.
// Forward only that strip; the returned view keeps its original recognizers.
@interface TrueSheetEdgeTouchView : UIView
@property (nonatomic, weak) UIView *contentView;
@property (nonatomic, weak) UIView *wrapperView;
@end

@implementation TrueSheetEdgeTouchView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
  UIView *content = self.contentView;
  UIView *wrapper = self.wrapperView;
  if (!content || !wrapper || !self.userInteractionEnabled || self.hidden || self.alpha < 0.01) return nil;
  for (UIView *view = content; view && view != self.superview; view = view.superview) {
    if (!view.userInteractionEnabled || view.hidden || view.alpha < 0.01) return nil;
  }
  CGPoint wrapperPoint = [wrapper convertPoint:point fromView:self];
  if (CGRectContainsPoint(wrapper.bounds, wrapperPoint)) return nil;
  return [content hitTest:[content convertPoint:point fromView:self] withEvent:event];
}
@end

@implementation TrueSheetViewController {
  TrueSheetPositionState _lastEmittedPositionState;
  CGFloat _lastWidth;
  NSInteger _pendingDetentIndex;
  BOOL _pendingContentSizeChange;
  BOOL _pendingDetentsChange;

  CADisplayLink *_transitioningTimer;
  UIView *_transitionFakeView;
  NSUInteger _transitionGeneration;
  BOOL _isDragging;
  BOOL _isTransitioning;
  BOOL _isTransitionSnapping;
  BOOL _isTrackingPositionFromLayout;
  BOOL _isWillDismissEmitted;

  BOOL _isInteractiveDismiss;
  CGFloat _interactiveStartPosition;
  UIView *_interactiveContainerView;
  CADisplayLink *_interactivePositionLink;
  NSUInteger _interactiveGeneration;

  __weak TrueSheetViewController *_parentSheetController;
  __weak UIView *_presenterFirstResponder;

  UIView *_anchorView;

  __weak UIWindow *_accessibilityWindow;

  TrueSheetBlurView *_blurView;
  TrueSheetGrabberView *_grabberView;
  TrueSheetDetentCalculator *_detentCalculator;

  NSMutableArray<TrueSheetShadowState *> *_shadowStates;
  CGFloat _systemCornerRadius;
  BOOL _chromeLayoutQueued;

  UIView *_dimHost;
  UIView *_dimFill;
  BOOL _dimmerDisappearing;
  BOOL _dimmerTransitioning;
  NSUInteger _dimmerGeneration;

  __weak UIView *_compensatedSurface;
  CGAffineTransform _surfaceOriginalTransform;
  CGAffineTransform _surfaceAppliedTransform;
  TrueSheetEdgeTouchView *_edgeTouchView;
}

#pragma mark - Initialization

- (instancetype)init {
  if (self = [super initWithNibName:nil bundle:nil]) {
    self.modalPresentationStyle = UIModalPresentationPageSheet;
    _detents = @[ @0.5, @1 ];
    _contentHeight = @(0);
    _headerHeight = @(0);
    _footerHeight = @(0);
    _peekContentHeight = @(0);
    _grabber = YES;
    _draggable = YES;
    _scrollingExpandsSheet = YES;
    _dismissible = YES;
    _dimmed = YES;
    _dimmedDetentIndex = @(0);
    _presentation = facebook::react::TrueSheetViewPresentation::Page;
    _lastEmittedPositionState = (TrueSheetPositionState){0, 0, 0};
    _isDragging = NO;
    _isPresented = NO;
    _isTransitioning = NO;
    _isWillDismissEmitted = NO;
    _pendingContentSizeChange = NO;
    _activeDetentIndex = -1;
    _pendingDetentIndex = -1;

    _transitionFakeView = [UIView new];
    _isTrackingPositionFromLayout = NO;

    _blurInteraction = YES;
    _insetAdjustment = TrueSheetViewInsetAdjustment::Automatic;
    _detentCalculator = [[TrueSheetDetentCalculator alloc] init];
    _detentCalculator.delegate = self;
  }
  return self;
}

- (void)dealloc {
  [self removeOwnedChrome];
  [self restoreWindowAccessibilityElements];
  [_transitioningTimer invalidate];
  _transitioningTimer = nil;
  [_interactivePositionLink invalidate];
  _interactivePositionLink = nil;
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Computed Properties

- (UISheetPresentationController *)sheet {
  return self.sheetPresentationController;
}

- (BOOL)isTopmostPresentedController {
  if (!self.isViewLoaded || self.view.window == nil) {
    return NO;
  }
  return self.presentedViewController == nil;
}

- (UIView *)presentedView {
  return self.sheet.presentedView;
}

- (CGFloat)currentPosition {
  UIView *presentedView = self.presentedView;
  return presentedView ? presentedView.frame.origin.y : 0.0;
}

- (CGFloat)screenHeight {
  UIWindow *window = self.view.window;
  return window ? window.bounds.size.height : UIScreen.mainScreen.bounds.size.height;
}

- (CGFloat)detentBottomAdjustmentForHeight:(CGFloat)height {
  if (_insetAdjustment == TrueSheetViewInsetAdjustment::Automatic) {
    return 0;
  }

  if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPhone) {
    return 0;
  }

  // On iOS 26+, returns 0 for small detents (height <= 150)
  // Floating sheets don't need adjustment
  if (@available(iOS 26.0, *)) {
    if (height <= 150) {
      return 0;
    }
  }

  UIWindow *window = [WindowUtil keyWindow];
  return window ? window.safeAreaInsets.bottom : 0;
}

- (BOOL)isDesignCompatibilityMode {
  if (@available(iOS 26.0, *)) {
    NSNumber *value = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"UIDesignRequiresCompatibility"];
    return value.boolValue;
  }
  return NO;
}

- (NSInteger)currentDetentIndex {
  UISheetPresentationController *sheet = self.sheet;
  if (!sheet)
    return -1;

  UISheetPresentationControllerDetentIdentifier selectedIdentifier = sheet.selectedDetentIdentifier;
  if (!selectedIdentifier)
    return -1;

  NSArray<UISheetPresentationControllerDetent *> *detents = sheet.detents;
  for (NSInteger i = 0; i < detents.count; i++) {
    if (@available(iOS 16.0, *)) {
      if ([detents[i].identifier isEqualToString:selectedIdentifier]) {
        return i;
      }
    } else {
      if ([selectedIdentifier isEqualToString:UISheetPresentationControllerDetentIdentifierMedium]) {
        return 0;
      } else if ([selectedIdentifier isEqualToString:UISheetPresentationControllerDetentIdentifierLarge]) {
        return detents.count - 1;
      }
    }
  }

  return -1;
}

#pragma mark - View Lifecycle

- (void)loadView {
  TrueSheetRootView *view = [[TrueSheetRootView alloc] init];
  view.accessibilityController = self;
  self.view = view;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;

  _blurView = [[TrueSheetBlurView alloc] init];
  [_blurView addToView:self.view];

  _grabberView = [[TrueSheetGrabberView alloc] init];
  _grabberView.hidden = YES;
  [_grabberView addToView:self.view];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];

  _blurView.alpha = 1;

  if (!_isPresented) {
    UIViewController *presenter = self.presentingViewController;
    if ([presenter isKindOfClass:[TrueSheetViewController class]]) {
      _parentSheetController = (TrueSheetViewController *)presenter;
      [_parentSheetController.delegate viewControllerWillBlur];
      [_parentSheetController setAccessibilityContentElement:self.accessibilityContentView ?: self.view];
    }

    // Custom dimming disables UIKit's dimmer, including its keyboard preservation.
    if ([self usesOwnedDimmer] && self.dimmed && self.dimmedDetentIndex.integerValue == 0) {
      UIView *firstResponder = [presenter.view findFirstResponder];
      if ([firstResponder resignFirstResponder]) _presenterFirstResponder = firstResponder;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      NSInteger index = self.currentDetentIndex;
      CGFloat position = self.currentPosition;
      CGFloat detent = [self detentValueForIndex:index];

      [self.delegate viewControllerWillPresentAtIndex:index position:position detent:detent];
      [self.delegate viewControllerWillFocus];
    });
  }

  [self setupTransitionTracker];
  _dimmerDisappearing = NO;
  [self updateOwnedDimmer];
  if (!_isPresented) {
    [self animateOwnedDimmerVisible:YES];
  }
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  [self setSheetAccessibilityElementsHidden:NO];

  if (!_isPresented) {
    [_parentSheetController.delegate viewControllerDidBlur];

    dispatch_async(dispatch_get_main_queue(), ^{
      NSInteger index = [self currentDetentIndex];
      CGFloat detent = [self detentValueForIndex:index];
      [self.delegate viewControllerDidPresentAtIndex:index position:self.currentPosition detent:detent];
      [self.delegate viewControllerDidFocus];

      [self->_grabberView updateAccessibilityValueWithIndex:index detentCount:self->_detents.count];
      [self settleAtDetentIndex:index debug:@"did present"];
    });

    [self setupGestureRecognizer];
    _isPresented = YES;
  }

  [self setupAccessibilityContainer];
  [self updateSheetChrome];
  [self updateOwnedDimmer];
}

- (void)setupAccessibilityContainer {
  UIView *contentView = self.accessibilityContentView;
  if (!contentView) {
    return;
  }

  [self setAccessibilityContentElement:contentView];
}

- (UIViewController *)accessibilityPresentingViewController {
  UIViewController *presentingViewController = self.presentingViewController;
  while ([presentingViewController isKindOfClass:[TrueSheetViewController class]] &&
         presentingViewController.presentingViewController) {
    presentingViewController = presentingViewController.presentingViewController;
  }
  return presentingViewController;
}

- (void)restoreWindowAccessibilityElements {
  UIWindow *window = _accessibilityWindow;
  if (window) {
    // The active sheet may temporarily own window accessibility traversal. Only
    // restore the previous value when this controller still owns that override.
    NSValue *ownerValue = objc_getAssociatedObject(window, &TrueSheetAccessibilityWindowOwnerKey);
    if (ownerValue && ownerValue.nonretainedObjectValue == self) {
      id previousElements = objc_getAssociatedObject(window, &TrueSheetAccessibilityWindowPreviousElementsKey);
      window.accessibilityElements = previousElements == [NSNull null] ? nil : previousElements;
      objc_setAssociatedObject(window, &TrueSheetAccessibilityWindowOwnerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      objc_setAssociatedObject(
        window, &TrueSheetAccessibilityWindowPreviousElementsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    _accessibilityWindow = nil;
  }
}

- (void)setSheetAccessibilityElementsHidden:(BOOL)hidden {
  self.view.accessibilityElementsHidden = hidden;

  UIView *presentedView = self.presentationController.presentedView;
  if (presentedView) {
    presentedView.accessibilityElementsHidden = hidden;
  }
}

- (NSArray *)accessibilityGrabberElements {
  if (_grabberView && !_grabberView.hidden) {
    return @[ _grabberView ];
  }

  // The system grabber is an accessibility element UIKit adds to the presented view
  // (a sibling of our root view). Expose it so VoiceOver can resize or dismiss with it.
  // UIKit also keeps a transparent bottom grabber there, so skip invisible views.
  NSMutableArray *elements = [NSMutableArray array];
  for (UIView *subview in self.presentationController.presentedView.subviews) {
    if (subview != self.view && subview.isAccessibilityElement && !subview.hidden && subview.alpha > 0) {
      [elements addObject:subview];
    }
  }
  return elements;
}

- (BOOL)accessibilityPerformEscape {
  if (!_isPresented || !self.dismissible) {
    return NO;
  }

  [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
  return YES;
}

- (void)setAccessibilityContentElement:(UIView *)contentView {
  BOOL hasAccessibilityFooterElements = [contentView isKindOfClass:[TrueSheetContainerView class]] &&
                                        [(TrueSheetContainerView *)contentView hasAccessibilityFooterElements];
  // Footer controls exposed as separate accessibility elements can be skipped
  // by XCTest when the presented sheet is a hard modal accessibility boundary.
  BOOL isAccessibilityModal = _dimmed && !hasAccessibilityFooterElements;

  // At a hard modal boundary XCTest skips nested elements, so flatten the
  // container's children into the array. Otherwise expose the container itself:
  // its accessibilityElements getter recomputes live, so a footer/content subtree
  // that remounts (e.g. swapping a footer button on a state change) stays
  // discoverable instead of leaving this snapshot pointing at destroyed views.
  NSMutableArray *accessibilityElements = [[self accessibilityGrabberElements] mutableCopy];
  if (isAccessibilityModal) {
    NSArray *contentElements = contentView.accessibilityElements;
    [accessibilityElements addObjectsFromArray:contentElements.count > 0 ? contentElements : @[ contentView ]];
  } else {
    [accessibilityElements addObject:contentView];
  }

  self.view.isAccessibilityElement = NO;
  self.view.accessibilityViewIsModal = YES;
  self.view.accessibilityElements = accessibilityElements;

  UIView *presentedView = self.presentationController.presentedView;
  if (presentedView) {
    presentedView.isAccessibilityElement = NO;
    presentedView.accessibilityViewIsModal = isAccessibilityModal;
    presentedView.accessibilityElements = accessibilityElements;

    // The system grabber is a sibling of our root view, so an escape performed while it
    // is focused walks presentedView → window and never reaches TrueSheetRootView.
    if (@available(iOS 17.0, *)) {
      __weak __typeof(self) weakSelf = self;
      presentedView.accessibilityPerformEscapeBlock = ^BOOL {
        return [weakSelf accessibilityPerformEscape];
      };
    }

    UIWindow *window = self.view.window;
    UIViewController *presentingViewController = [self accessibilityPresentingViewController];
    if (window && presentingViewController.view) {
      if (!_accessibilityWindow) {
        _accessibilityWindow = window;
        id previousElements = objc_getAssociatedObject(window, &TrueSheetAccessibilityWindowPreviousElementsKey);
        if (!previousElements) {
          previousElements = window.accessibilityElements ?: [NSNull null];
          objc_setAssociatedObject(window, &TrueSheetAccessibilityWindowPreviousElementsKey, previousElements,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
      }
      objc_setAssociatedObject(window, &TrueSheetAccessibilityWindowOwnerKey, [NSValue valueWithNonretainedObject:self],
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      window.accessibilityElements =
        isAccessibilityModal ? @[ presentedView ] : @[ presentingViewController.view, presentedView ];
      return;
    }
  }

  [self restoreWindowAccessibilityElements];
}

#pragma mark - Presentation

- (void)presentViewController:(UIViewController *)viewControllerToPresent
                     animated:(BOOL)flag
                   completion:(void (^)(void))completion {
  // A non-sheet controller (e.g. an action sheet, alert, or image picker) is about
  // to present over us. Clear our window accessibility override so UIKit's default
  // traversal surfaces it for XCTest and assistive technologies; we reclaim the
  // override when it dismisses. Nested sheets claim their own override.
  if (![viewControllerToPresent isKindOfClass:[TrueSheetViewController class]]) {
    self.view.window.accessibilityElements = nil;
  }

  // UIKit owns the parent scale while stacking another controller.
  [self restoreEdgeCompensation];
  [super presentViewController:viewControllerToPresent animated:flag completion:completion];
}

- (void)dismissViewControllerAnimated:(BOOL)flag completion:(void (^)(void))completion {
  [super dismissViewControllerAnimated:flag
                            completion:^{
                              if (completion) {
                                completion();
                              }

                              // Reclaim the window accessibility override once nothing
                              // else is presented over us.
                              if (self.isPresented && self.presentedViewController == nil) {
                                [self setupAccessibilityContainer];
                                [self updateSheetChrome];
                                [self updateOwnedDimmer];
                              }
                            }];
}

- (void)emitWillDismissEvents {
  if (self.isBeingDismissed && !_isWillDismissEmitted) {
    _isWillDismissEmitted = YES;

    [self.delegate viewControllerWillBlur];
    [self.delegate viewControllerWillDismiss];
    [_parentSheetController.delegate viewControllerWillFocus];

    UIView *firstResponder = _presenterFirstResponder;
    _presenterFirstResponder = nil;
    if (!self.presentingViewController.isBeingDismissed) [firstResponder becomeFirstResponder];
  }
}

- (void)emitDidDismissEvents {
  if (self.isBeingDismissed) {
    [self removeOwnedChrome];
    [self restoreWindowAccessibilityElements];
    _isPresented = NO;
    _isWillDismissEmitted = NO;

    [_anchorView removeFromSuperview];
    _anchorView = nil;

    [_parentSheetController.delegate viewControllerDidFocus];
    [_parentSheetController setSheetAccessibilityElementsHidden:NO];
    [_parentSheetController setupAccessibilityContainer];
    __weak TrueSheetViewController *parentSheet = _parentSheetController;
    dispatch_async(dispatch_get_main_queue(), ^{
      // Interactive UIKit dismissal does not pass through the parent's dismiss
      // completion. Reclaim its decoration only after UIKit unlinks the child.
      if (parentSheet.isPresented && !parentSheet.presentedViewController) {
        [parentSheet updateSheetChrome];
        [parentSheet updateOwnedDimmer];
      }
    });
    _parentSheetController = nil;

    [self.delegate viewControllerDidBlur];
    [self.delegate viewControllerDidDismiss];
  }
}

- (void)viewWillDisappear:(BOOL)animated {
  [super viewWillDisappear:animated];
  BOOL dismissing = self.isBeingDismissed;
  for (UIViewController *presenter = self.presentingViewController; presenter; presenter = presenter.presentingViewController) {
    dismissing = dismissing || presenter.isBeingDismissed;
  }
  if (dismissing) [self animateOwnedDimmerVisible:NO];
  [self restoreWindowAccessibilityElements];
  [self setSheetAccessibilityElementsHidden:YES];

  // Dispatch to allow pan gesture to set _isDragging before checking
  // handleTransitionTracker will emit when sheet is transitioning to dismiss
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!self->_isDragging) {
      [self emitWillDismissEvents];
    }
  });

  [self setupTransitionTracker];
}

- (void)viewDidDisappear:(BOOL)animated {
  [super viewDidDisappear:animated];
  if (_dimmerDisappearing || !self.presentingViewController) [self removeOwnedChrome];

  // Backstop: if the sheet is torn down mid-gesture (e.g. owning view deallocated),
  // the observer can't reach us through its weak delegate, so end here to invalidate
  // _interactivePositionLink — which otherwise retains this controller indefinitely.
  if (_isInteractiveDismiss) {
    [self endInteractiveDismissState];
  }

  // Dismissing with the keyboard up skips the hide notification — don't let
  // the stale flag block learning on the next present.
  _keyboardSheetGrown = NO;

  [self emitDidDismissEvents];
}

- (void)viewWillLayoutSubviews {
  [super viewWillLayoutSubviews];

  // Skip during an interactive nav dismiss; emitInteractivePosition owns position then,
  // and currentPosition (presentedView frame) stays at rest since we move the container.
  if (!_isTransitioning && !_isInteractiveDismiss) {
    _isTrackingPositionFromLayout = YES;

    if (_pendingContentSizeChange || _pendingDetentsChange) {
      _pendingContentSizeChange = NO;
      _pendingDetentsChange = NO;
      [self settleAtDetentIndex:self.currentDetentIndex debug:@"layout"];
    } else {
      UIViewController *presented = self.presentedViewController;
      BOOL hasPresentedController = presented != nil && !presented.isBeingPresented && !presented.isBeingDismissed;

      // A layout pass at rest can nudge the frame by a sub-pixel amount
      // (pixel-grid snapping after present), leaving the interpolated index
      // slightly off the whole number. Re-learn when the frame is effectively
      // at the current detent so the drift is absorbed instead of emitted.
      // The tight threshold keeps real movement from being absorbed.
      if (presented == nil && !_isDragging) {
        NSInteger index = self.currentDetentIndex;
        CGFloat expectedHeight = [_detentCalculator resolvedHeightForIndex:index];
        CGFloat actualHeight = self.screenHeight - self.currentPosition;
        if (expectedHeight > 0 && fabs(actualHeight - expectedHeight) < 2) {
          [self learnOffsetForDetentIndex:index];
        }
      }

      [self emitChangePositionDelegateWithPosition:self.currentPosition
                                          realtime:!hasPresentedController
                                             debug:@"layout"];
    }
  }
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  [self updateSheetChrome];
  [self updateOwnedDimmer];
  // UIKit may set its resting container scale after our layout callback.
  // Coalesce one deferred pass; never run a permanent display link or tree walk.
  if (self.edgeToEdge && !_chromeLayoutQueued) {
    _chromeLayoutQueued = YES;
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong __typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) return;
      strongSelf->_chromeLayoutQueued = NO;
      if (strongSelf.view.window) [strongSelf updateSheetChrome];
    });
  }

  // Update state on rotation (width change)
  CGFloat width = self.view.frame.size.width;
  if (_lastWidth != width) {
    _lastWidth = width;
    [self.delegate viewControllerDidChangeSize:self.view.frame.size];
  }

  if (_pendingDetentIndex >= 0) {
    NSInteger pendingIndex = _pendingDetentIndex;
    _pendingDetentIndex = -1;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      CGFloat detent = [self detentValueForIndex:pendingIndex];
      [self.delegate viewControllerDidChangeDetent:pendingIndex position:self.currentPosition detent:detent];
      [self->_grabberView updateAccessibilityValueWithIndex:pendingIndex detentCount:self->_detents.count];
      [self settleAtDetentIndex:pendingIndex debug:@"pending detent change"];
    });
  }

  _isTrackingPositionFromLayout = NO;
}

#pragma mark - Position & Gesture Handling

- (TrueSheetContentView *)findContentView:(UIView *)view {
  if ([view isKindOfClass:[TrueSheetContentView class]]) {
    return (TrueSheetContentView *)view;
  }

  for (UIView *subview in view.subviews) {
    TrueSheetContentView *found = [self findContentView:subview];
    if (found) {
      return found;
    }
  }

  return nil;
}

- (void)setupGestureRecognizer {
  UIView *presentedView = self.presentedView;
  if (!presentedView)
    return;

  if (!self.draggable) {
    [GestureUtil setPanGesturesEnabled:NO forView:presentedView];
    return;
  }

  [GestureUtil attachPanGestureHandler:presentedView target:self selector:@selector(handlePanGesture:)];

  TrueSheetContentView *contentView = [self findContentView:presentedView];
  if (contentView) {
    RCTScrollViewComponentView *scrollViewComponent = [contentView findScrollView];
    if (scrollViewComponent && scrollViewComponent.scrollView) {
      [GestureUtil attachPanGestureHandler:scrollViewComponent.scrollView
                                    target:self
                                  selector:@selector(handlePanGesture:)];
    }
  }
}

- (void)setupDraggable {
  UIView *presentedView = self.presentedView;
  if (!presentedView)
    return;

  [GestureUtil setPanGesturesEnabled:self.draggable forView:presentedView];
}

- (void)handlePanGesture:(UIPanGestureRecognizer *)gesture {
  NSInteger index = self.currentDetentIndex;
  CGFloat detent = [self detentValueForIndex:index];

  [self.delegate viewControllerDidDrag:gesture.state index:index position:self.currentPosition detent:detent];

  switch (gesture.state) {
    case UIGestureRecognizerStateBegan:
      _isDragging = YES;
      break;
    case UIGestureRecognizerStateChanged:
      if (!_isTrackingPositionFromLayout) {
        [self emitChangePositionDelegateWithPosition:self.currentPosition realtime:YES debug:@"drag change"];
      }
      break;
    case UIGestureRecognizerStateEnded:
    case UIGestureRecognizerStateCancelled: {
      if (!_isTransitioning) {
        dispatch_async(dispatch_get_main_queue(), ^{
          NSInteger index = self.currentDetentIndex;
          [self->_grabberView updateAccessibilityValueWithIndex:index detentCount:self->_detents.count];
          [self settleAtDetentIndex:index debug:@"drag end"];
        });
      }

      _isDragging = NO;
      [self updateSheetChrome];
      [self updateOwnedDimmer];
      break;
    }
    default:
      break;
  }
}

- (void)setupTransitionTracker {
  if (!self.transitionCoordinator || _isInteractiveDismiss || _isTransitioning)
    return;

  _isTransitioning = YES;
  NSUInteger generation = ++_transitionGeneration;

  // Learn the resolver-vs-actual offset before emitting transition positions so
  // the interpolated index lands exactly on the target detent. The presented
  // frame is already final here (UIKit animates the layer, not the frame).
  if (!self.isBeingDismissed) {
    [self learnOffsetForDetentIndex:self.currentDetentIndex];
  }

  CGRect dismissedFrame = CGRectMake(0, self.screenHeight, 0, 0);
  CGRect presentedFrame = CGRectMake(0, self.currentPosition, 0, 0);

  _transitionFakeView.frame = self.isBeingDismissed ? presentedFrame : dismissedFrame;

  __weak __typeof(self) weakSelf = self;

  [self.transitionCoordinator
    animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> _Nonnull context) {
      __strong __typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf || generation != strongSelf->_transitionGeneration)
        return;

      [[context containerView] addSubview:strongSelf->_transitionFakeView];
      strongSelf->_transitionFakeView.frame = strongSelf.isBeingDismissed ? dismissedFrame : presentedFrame;

      strongSelf->_transitioningTimer = [CADisplayLink displayLinkWithTarget:strongSelf
                                                                    selector:@selector(handleTransitionTracker)];
      [strongSelf->_transitioningTimer addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    }
    completion:^(id<UIViewControllerTransitionCoordinatorContext> _Nonnull context) {
      __strong __typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf || generation != strongSelf->_transitionGeneration)
        return;

      [strongSelf->_transitioningTimer setPaused:YES];
      [strongSelf->_transitioningTimer invalidate];
      strongSelf->_transitioningTimer = nil;
      [strongSelf->_transitionFakeView removeFromSuperview];
      strongSelf->_isTransitioning = NO;
      if (context.isCancelled) {
        strongSelf->_isWillDismissEmitted = NO;
        strongSelf->_blurView.alpha = 1;
        [strongSelf setSheetAccessibilityElementsHidden:NO];
        [strongSelf setupAccessibilityContainer];
      }
      [strongSelf updateSheetChrome];
      [strongSelf updateOwnedDimmer];
      strongSelf->_isTransitionSnapping = NO;

      // Settle after a present or detent-snap transition.
      // Uses dispatch_after because presentedView frame isn't final until UIKit
      // completes its layout pass after the transition animation — learning
      // here absorbs any sub-pixel drift since the earlier learns.
      if (strongSelf->_isPresented) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          [strongSelf settleAtDetentIndex:strongSelf.currentDetentIndex debug:@"transition end"];
        });
      }
    }];
}

- (void)handleTransitionTracker {
  [self updateEdgeCompensation];
  if (!_isDragging && _transitionFakeView.layer) {
    CALayer *layer = _transitionFakeView.layer;
    CGFloat layerPosition = layer.presentationLayer.frame.origin.y;

    if (self.currentPosition >= self.screenHeight) {
      CGFloat position = fmax(_lastEmittedPositionState.position, layerPosition);

      // Hide blur at the end of dismiss to prevent UIVisualEffectView
      // from causing a flicker/flash at the bottom edge of the sheet.
      if (self.screenHeight - position < 1) {
        _blurView.alpha = 0;
      }

      [self emitWillDismissEvents];
      [self emitChangePositionDelegateWithPosition:position realtime:YES debug:@"transition out"];

    } else {
      CGFloat position = fmax(self.currentPosition, layerPosition);
      // Detect drag → snap transition jump; stay non-realtime for the rest of the animation
      if (!_isTransitionSnapping && _isPresented && _lastEmittedPositionState.position > 0 &&
          fabs(_lastEmittedPositionState.position - position) > 20) {
        _isTransitionSnapping = YES;
      }
      BOOL realtime = !_isTransitionSnapping;
      [self emitChangePositionDelegateWithPosition:position realtime:realtime debug:@"transition in"];
    }
  }
}

#pragma mark - Interactive Navigation Dismiss

- (void)beginInteractiveDismiss {
  if (_isInteractiveDismiss) {
    // A settle animation from a prior gesture is still running. Stop it and reset so
    // this gesture tracks from a clean state; its stale completion is ignored via the
    // generation check in animateInteractiveContainerToTransform.
    [_interactiveContainerView.layer removeAllAnimations];
    [self endInteractiveDismissState];
  }

  _interactiveGeneration += 1;
  _isInteractiveDismiss = YES;
  _interactiveStartPosition = self.currentPosition;
  _interactiveContainerView = self.sheet.containerView;

  // Emit position from the container's presentation layer for the whole gesture, so
  // both the direct-set drag and the settle animation report a live, smooth position.
  _interactivePositionLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(emitInteractivePosition)];
  [_interactivePositionLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)emitInteractivePosition {
  CALayer *presentation = _interactiveContainerView.layer.presentationLayer;
  CGFloat offset = presentation ? presentation.affineTransform.ty : 0;
  [self emitChangePositionDelegateWithPosition:_interactiveStartPosition + offset realtime:YES debug:@"nav swipe"];
}

// Translate the presentation container, not the sheet's presentedView (whose transform
// UISheetPresentationController owns for the floating-sheet inset). Only runs for undimmed
// sheets — a dimmed sheet's dimming view intercepts the edge-swipe so the pop never starts.
- (void)updateInteractiveDismiss:(CGFloat)progress {
  if (!_isInteractiveDismiss) {
    return;
  }
  CGFloat clamped = fmin(1, fmax(0, progress));
  CGFloat dy = clamped * (self.screenHeight - _interactiveStartPosition);
  _interactiveContainerView.transform = CGAffineTransformMakeTranslation(0, dy);
}

- (void)cancelInteractiveDismissWithDuration:(NSTimeInterval)duration {
  if (!_isInteractiveDismiss) {
    return;
  }
  [self animateInteractiveContainerToTransform:CGAffineTransformIdentity
                                      duration:duration
                          allowUserInteraction:YES
                                    completion:nil];
}

- (void)finishInteractiveDismissWithDuration:(NSTimeInterval)duration completion:(void (^)(void))completion {
  if (!_isInteractiveDismiss) {
    if (completion) {
      completion();
    }
    return;
  }
  // Leave the sheet translated off-screen; the caller tears it down non-animated
  // from here so there is no second slide.
  CGFloat dy = self.screenHeight - _interactiveStartPosition;
  [self animateInteractiveContainerToTransform:CGAffineTransformMakeTranslation(0, dy)
                                      duration:duration
                          allowUserInteraction:NO
                                    completion:completion];
}

- (void)animateInteractiveContainerToTransform:(CGAffineTransform)transform
                                      duration:(NSTimeInterval)duration
                          allowUserInteraction:(BOOL)allowUserInteraction
                                    completion:(void (^)(void))completion {
  UIView *container = _interactiveContainerView;
  NSUInteger generation = _interactiveGeneration;

  UIViewAnimationOptions options = UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState;
  if (allowUserInteraction) {
    options |= UIViewAnimationOptionAllowUserInteraction;
  }

  [UIView animateWithDuration:fmax(duration, 0.2)
    delay:0
    options:options
    animations:^{
      container.transform = transform;
    }
    completion:^(BOOL finished) {
      // A newer gesture superseded this settle and owns teardown now.
      if (generation != self->_interactiveGeneration) {
        return;
      }
      [self endInteractiveDismissState];
      if (completion) {
        completion();
      }
    }];
}

- (void)endInteractiveDismissState {
  _isInteractiveDismiss = NO;
  _interactiveContainerView = nil;
  _interactiveStartPosition = 0;
  [_interactivePositionLink invalidate];
  _interactivePositionLink = nil;
}

- (void)emitChangePositionDelegateWithPosition:(CGFloat)position realtime:(BOOL)realtime debug:(NSString *)debug {
  UIViewController *presented = self.presentedViewController;
  if (presented) {
    UIModalPresentationStyle style = presented.modalPresentationStyle;
    if (style == UIModalPresentationFullScreen || style == UIModalPresentationOverFullScreen ||
        style == UIModalPresentationCurrentContext || style == UIModalPresentationOverCurrentContext) {
      return;
    }
  }

  TrueSheetPositionState state = {
    .position = position,
    .detent = [self interpolatedDetentForPosition:position],
    .index = [self interpolatedIndexForPosition:position],
  };

  // Settle (non-realtime) emits are authoritative and bypass the dedupe — a
  // learn right before them can correct the interpolated index by less than
  // the tolerance, and the corrected value must still reach JS.
  if (!realtime || !TrueSheetPositionStateEquals(_lastEmittedPositionState, state)) {
    _lastEmittedPositionState = state;

    [self.delegate viewControllerDidChangePosition:state.index
                                          position:state.position
                                            detent:state.detent
                                          realtime:realtime];
  }
}

- (void)learnOffsetForDetentIndex:(NSInteger)index {
  if (_keyboardSheetGrown) {
    return;
  }
  [_detentCalculator learnOffsetForDetentIndex:index];
}

- (void)setKeyboardSheetGrown:(BOOL)keyboardSheetGrown {
  BOOL wasGrown = _keyboardSheetGrown;
  _keyboardSheetGrown = keyboardSheetGrown;

  // Settles are skipped or measure a mid-animation frame while the keyboard
  // has the sheet grown (e.g. a drag-end during the shrink-back) — re-settle
  // at the resting detent once the keyboard is fully away.
  if (wasGrown && !keyboardSheetGrown && self.isPresented && !_isDragging) {
    [self settleAtDetentIndex:self.currentDetentIndex debug:@"keyboard settled"];
  }
}

/**
 * Learn the resolver-vs-actual offset at a settled detent, then emit the corrected
 * position. Only valid when presentedView's frame is final — never mid-drag or
 * mid-animation, where learning would store a bogus offset.
 */
- (void)settleAtDetentIndex:(NSInteger)index debug:(NSString *)debug {
  [self learnOffsetForDetentIndex:index];
  [self emitChangePositionDelegateWithPosition:self.currentPosition realtime:NO debug:debug];
}

- (BOOL)findSegmentForPosition:(CGFloat)position outIndex:(NSInteger *)outIndex outProgress:(CGFloat *)outProgress {
  return [_detentCalculator findSegmentForPosition:position outIndex:outIndex outProgress:outProgress];
}

- (CGFloat)interpolatedIndexForPosition:(CGFloat)position {
  return [_detentCalculator interpolatedIndexForPosition:position];
}

- (CGFloat)interpolatedDetentForPosition:(CGFloat)position {
  return [_detentCalculator interpolatedDetentForPosition:position];
}

- (CGFloat)detentValueForIndex:(NSInteger)index {
  return [_detentCalculator detentValueForIndex:index];
}

#pragma mark - Sheet Configuration

- (void)setupSheetDetentsForSizeChange {
  [self.sheet animateChanges:^{
    _pendingContentSizeChange = YES;
    [self setupSheetDetents];
  }];
}

- (void)setupSheetDetentsForDetentsChange {
  _pendingDetentsChange = YES;
  [self setupSheetDetents];
}

- (void)setupSheetDetents {
  UISheetPresentationController *sheet = self.sheet;
  if (!sheet) {
    RCTLogError(@"TrueSheet: sheetPresentationController is nil in setupSheetDetents");
    return;
  }

  NSMutableArray<UISheetPresentationControllerDetent *> *detents = [NSMutableArray array];
  [_detentCalculator clearResolvedHeights];

  CGFloat autoHeight = [self.contentHeight floatValue] + [self.headerHeight floatValue];

  for (NSInteger index = 0; index < self.detents.count; index++) {
    id detent = self.detents[index];
    UISheetPresentationControllerDetent *sheetDetent = [self detentForValue:detent
                                                             withAutoHeight:autoHeight
                                                                    atIndex:index];
    [detents addObject:sheetDetent];
  }

  [_detentCalculator setDetentCount:self.detents.count];
  sheet.detents = detents;

  if ([self usesOwnedDimmer]) {
    // Public API disables UIKit's dimmer; our owned sibling supplies color/taps.
    sheet.largestUndimmedDetentIdentifier = sheet.detents.lastObject.identifier;
  } else if (self.dimmed && [self.dimmedDetentIndex integerValue] == 0) {
    sheet.largestUndimmedDetentIdentifier = nil;
  } else {
    sheet.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;

    if (@available(iOS 16.0, *)) {
      if (self.dimmed && self.dimmedDetentIndex) {
        NSInteger dimmedIdx = [self.dimmedDetentIndex integerValue];
        if (dimmedIdx > 0 && dimmedIdx - 1 < sheet.detents.count) {
          sheet.largestUndimmedDetentIdentifier = sheet.detents[dimmedIdx - 1].identifier;
        } else if (sheet.detents.lastObject) {
          sheet.largestUndimmedDetentIdentifier = sheet.detents.lastObject.identifier;
        }
      } else if (sheet.detents.lastObject) {
        sheet.largestUndimmedDetentIdentifier = sheet.detents.lastObject.identifier;
      }
    }
  }
  [self updateOwnedDimmer];
}

- (UISheetPresentationControllerDetent *)detentForValue:(id)detent
                                         withAutoHeight:(CGFloat)autoHeight
                                                atIndex:(NSInteger)index {
  if (![detent isKindOfClass:[NSNumber class]]) {
    return [UISheetPresentationControllerDetent mediumDetent];
  }

  CGFloat value = [detent doubleValue];

  if (value == -1) {
    if (@available(iOS 16.0, *)) {
      return [self customDetentWithIdentifier:@"custom-auto" height:autoHeight atIndex:index];
    } else {
      return [UISheetPresentationControllerDetent mediumDetent];
    }
  }

  if (value == -2) {
    if (@available(iOS 16.0, *)) {
      return [self customDetentWithIdentifier:@"custom-peek" height:[_detentCalculator peekHeight] atIndex:index];
    } else {
      return [UISheetPresentationControllerDetent mediumDetent];
    }
  }

  if (value <= 0 || value > 1) {
    RCTLogError(@"TrueSheet: detent fraction (%f) must be between 0 and 1", value);
    return [UISheetPresentationControllerDetent mediumDetent];
  }

  if (@available(iOS 16.0, *)) {
    NSString *detentId = [NSString stringWithFormat:@"custom-%f", value];
    CGFloat sheetHeight = value * self.screenHeight;
    return [self customDetentWithIdentifier:detentId height:sheetHeight atIndex:index];
  } else if (value >= 0.5) {
    return [UISheetPresentationControllerDetent largeDetent];
  } else {
    return [UISheetPresentationControllerDetent mediumDetent];
  }
}

- (UISheetPresentationControllerDetent *)customDetentWithIdentifier:(NSString *)identifier
                                                             height:(CGFloat)height
                                                            atIndex:(NSInteger)index API_AVAILABLE(ios(16.0)) {
  CGFloat bottomAdjustment = [self detentBottomAdjustmentForHeight:height];
  return [UISheetPresentationControllerDetent
    customDetentWithIdentifier:identifier
                      resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
                        CGFloat maxDetentValue = context.maximumDetentValue;
                        self->_detentCalculator.maxDetentHeight = maxDetentValue;

                        CGFloat maxValue = self.maxContentHeight
                                             ? fmin(maxDetentValue, [self.maxContentHeight floatValue])
                                             : maxDetentValue;
                        CGFloat adjustedHeight = height - bottomAdjustment;
                        CGFloat resolved = fmin(adjustedHeight, maxValue);

                        NSMutableArray *heights = self->_detentCalculator.resolvedDetentHeights;
                        if (heights && index >= 0 && index < (NSInteger)heights.count) {
                          heights[index] = @(resolved);
                        }

                        return resolved;
                      }];
}

- (UISheetPresentationControllerDetentIdentifier)detentIdentifierForIndex:(NSInteger)index {
  UISheetPresentationController *sheet = self.sheet;
  if (!sheet) {
    RCTLogError(@"TrueSheet: sheetPresentationController is nil in detentIdentifierForIndex");
    return UISheetPresentationControllerDetentIdentifierMedium;
  }

  UISheetPresentationControllerDetentIdentifier identifier = UISheetPresentationControllerDetentIdentifierMedium;
  if (index >= 0 && index < (NSInteger)sheet.detents.count) {
    UISheetPresentationControllerDetent *detent = sheet.detents[index];
    if (@available(iOS 16.0, *)) {
      identifier = detent.identifier;
    } else {
      if (detent == [UISheetPresentationControllerDetent largeDetent]) {
        identifier = UISheetPresentationControllerDetentIdentifierLarge;
      }
    }
  }

  return identifier;
}

- (void)applyActiveDetent {
  if (!self.sheet) {
    RCTLogError(@"TrueSheet: sheetPresentationController is nil in applyActiveDetent");
    return;
  }

  NSInteger detentCount = _detents.count;
  if (detentCount == 0)
    return;

  NSInteger clampedIndex = _activeDetentIndex;
  if (clampedIndex < 0) {
    clampedIndex = 0;
  } else if (clampedIndex >= detentCount) {
    clampedIndex = detentCount - 1;
  }

  if (clampedIndex != _activeDetentIndex) {
    _activeDetentIndex = clampedIndex;
  }

  UISheetPresentationControllerDetentIdentifier identifier = [self detentIdentifierForIndex:clampedIndex];
  if (identifier) {
    self.sheet.selectedDetentIdentifier = identifier;
  }
}

- (void)setupActiveDetentWithIndex:(NSInteger)index {
  _activeDetentIndex = index;
  [self applyActiveDetent];
}

- (void)resizeToDetentIndex:(NSInteger)index {
  if (index == _activeDetentIndex) {
    return;
  }

  _pendingDetentIndex = index;
  _activeDetentIndex = index;
  [self applyActiveDetent];
}

#pragma mark - Owned Presentation Chrome

- (BOOL)usesOwnedDimmer {
  return self.dimColor != nil || self.dimOpacity != nil;
}

- (BOOL)ownedDimmerIsActive {
  NSInteger index = self.currentDetentIndex;
  if (index < 0) index = MAX(0, self.activeDetentIndex);
  return self.dimmed && index >= self.dimmedDetentIndex.integerValue;
}

- (CGFloat)ownedDimmerOpacity {
  return self.dimOpacity ? fmin(1, truesheet::nonnegative(self.dimOpacity.doubleValue)) : 0.5;
}

- (void)handleOwnedBackdropTap:(UITapGestureRecognizer *)gesture {
  if (gesture.state == UIGestureRecognizerStateEnded && self.dismissible &&
      self.isTopmostPresentedController && [self ownedDimmerIsActive]) {
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
  }
}

- (void)updateOwnedDimmer {
  if (![self usesOwnedDimmer]) {
    _dimmerGeneration++;
    _dimmerTransitioning = NO;
    [_dimHost removeFromSuperview];
    _dimHost = nil;
    _dimFill = nil;
    return;
  }
  UIView *container = self.sheet.containerView;
  UIView *sheetBranch = self.presentedView;
  // Only inspect this sheet's ancestor chain, never another presentation's views.
  for (NSUInteger depth = 0; sheetBranch && sheetBranch.superview != container && depth < 8; depth++) {
    sheetBranch = sheetBranch.superview;
  }
  if (!container || !sheetBranch || sheetBranch.superview != container) return;
  if (!_dimHost) {
    _dimHost = [[UIView alloc] initWithFrame:container.bounds];
    _dimHost.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _dimHost.accessibilityElementsHidden = YES;
    [_dimHost addGestureRecognizer:[[UITapGestureRecognizer alloc]
      initWithTarget:self action:@selector(handleOwnedBackdropTap:)]];
    _dimFill = [[UIView alloc] initWithFrame:_dimHost.bounds];
    _dimFill.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _dimFill.userInteractionEnabled = NO;
    [_dimHost addSubview:_dimFill];
  }
  if (_dimHost.superview != container) {
    [container insertSubview:_dimHost belowSubview:sheetBranch];
  }
  _dimHost.frame = container.bounds;
  _dimFill.backgroundColor = self.dimColor ?: UIColor.blackColor;
  BOOL active = [self ownedDimmerIsActive];
  // Keep the host at alpha=1 even for a transparent configured dimmer: a modal
  // backdrop must block touches, while dimmed=false must pass them through.
  _dimHost.userInteractionEnabled = active && !self.presentedViewController;
  if (!_dimmerTransitioning || !active) {
    _dimHost.hidden = !active || _dimmerDisappearing;
    _dimFill.alpha = active && !_dimmerDisappearing ? [self ownedDimmerOpacity] : 0;
  }
}

- (void)animateOwnedDimmerVisible:(BOOL)visible {
  [self updateOwnedDimmer];
  _dimmerDisappearing = !visible;
  if (!_dimHost) return;
  _dimmerTransitioning = YES;
  NSUInteger generation = ++_dimmerGeneration;
  BOOL active = [self ownedDimmerIsActive];
  _dimHost.hidden = !active;
  if (visible) _dimFill.alpha = 0;
  CGFloat target = visible && active ? [self ownedDimmerOpacity] : 0;
  __weak __typeof(self) weakSelf = self;
  BOOL queued = [self.transitionCoordinator
    animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
      __strong __typeof(weakSelf) strongSelf = weakSelf;
      if (strongSelf) strongSelf->_dimFill.alpha = target;
    }
    completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
      __strong __typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf || generation != strongSelf->_dimmerGeneration) return;
      strongSelf->_dimmerTransitioning = NO;
      strongSelf->_dimmerDisappearing = context.isCancelled ? visible : !visible;
      if (!visible && !context.isCancelled) {
        [strongSelf->_dimHost removeFromSuperview];
        strongSelf->_dimHost = nil;
        strongSelf->_dimFill = nil;
      } else {
        [strongSelf updateOwnedDimmer];
      }
    }];
  if (!queued) {
    _dimmerTransitioning = NO;
    _dimFill.alpha = target;
    _dimHost.hidden = !visible || !active;
    _dimHost.userInteractionEnabled = visible && active && !self.presentedViewController;
  }
}

- (void)restoreEdgeCompensation {
  [_edgeTouchView removeFromSuperview];
  _edgeTouchView = nil;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  if (_compensatedSurface && CGAffineTransformEqualToTransform(_compensatedSurface.transform, _surfaceAppliedTransform)) {
    _compensatedSurface.transform = _surfaceOriginalTransform;
  }
  _compensatedSurface = nil;
  for (TrueSheetShadowState *state in _shadowStates) {
    CALayer *layer = state.view.layer;
    if (!layer) continue;
    if (layer.shadowOpacity == 0) layer.shadowOpacity = state.opacity;
    if (layer.shadowRadius == 0) layer.shadowRadius = state.radius;
    if (layer.shadowColor && CGColorGetAlpha(layer.shadowColor) == 0) layer.shadowColor = state.color.CGColor;
    if (!layer.shadowPath) layer.shadowPath = state.path.CGPath;
  }
  [_shadowStates removeAllObjects];
  [CATransaction commit];
}

- (BOOL)usesEdgeToEdgePage {
  CGFloat availableWidth = CGRectGetWidth((self.view.window ?: self.presentingViewController.view.window).bounds);
  if (availableWidth <= 0) availableWidth = CGRectGetWidth(UIScreen.mainScreen.bounds);
  BOOL narrowerWidth = self.maxContentWidth && self.maxContentWidth.doubleValue < availableWidth - 0.5;
  return self.edgeToEdge && UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone &&
    self.presentation == TrueSheetViewPresentation::Page && !narrowerWidth;
}

- (void)updateEdgeCompensation {
  if (![self usesEdgeToEdgePage] || self.presentedViewController) {
    [self restoreEdgeCompensation];
    return;
  }
  UIView *container = self.sheet.containerView;
  if (!container) return;
  UIView *surface = self.view;
  BOOL compensatedScale = NO;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  for (NSUInteger depth = 0; surface.superview && surface.superview != container && depth < 8; depth++) {
    UIView *ancestor = surface.superview;
    TrueSheetShadowState *snapshot = nil;
    for (TrueSheetShadowState *state in _shadowStates) {
      if (state.view == ancestor) {
        snapshot = state;
        break;
      }
    }
    if (!snapshot) {
      snapshot = [TrueSheetShadowState new];
      snapshot.view = ancestor;
      snapshot.opacity = ancestor.layer.shadowOpacity;
      snapshot.radius = ancestor.layer.shadowRadius;
      if (ancestor.layer.shadowColor) snapshot.color = [UIColor colorWithCGColor:ancestor.layer.shadowColor];
      if (ancestor.layer.shadowPath) snapshot.path = [UIBezierPath bezierPathWithCGPath:ancestor.layer.shadowPath];
      if (!_shadowStates) _shadowStates = [NSMutableArray array];
      [_shadowStates addObject:snapshot];
    }
    ancestor.layer.shadowOpacity = 0;
    ancestor.layer.shadowRadius = 0;
    ancestor.layer.shadowColor = UIColor.clearColor.CGColor;
    ancestor.layer.shadowPath = nil;
    if (@available(iOS 26.0, *)) {
      // Cancel the wrapper's decorative scale AND translation. Scale alone
      // leaves short sheets above the bottom edge. UIKit still owns the
      // wrapper's bounds/center and the outer presentation container's motion.
      if (!compensatedScale && [NSStringFromClass(ancestor.class) containsString:@"UIDropShadowView"]) {
        CGAffineTransform t = ancestor.transform;
        BOOL scaleOnly = isfinite(t.a) && isfinite(t.d) && t.a > 0.001 && t.d > 0.001 &&
          fabs(t.b) < 0.001 && fabs(t.c) < 0.001 && isfinite(t.tx) && isfinite(t.ty);
        BOOL ownsTransform = surface == _compensatedSurface &&
          CGAffineTransformEqualToTransform(surface.transform, _surfaceAppliedTransform);
        CGAffineTransform current = surface.transform;
        BOOL surfaceScaleOnly = isfinite(current.a) && isfinite(current.d) &&
          fabs(current.b) < 0.001 && fabs(current.c) < 0.001 &&
          fabs(current.tx) < 0.001 && fabs(current.ty) < 0.001;
        if (scaleOnly && (ownsTransform || surfaceScaleOnly)) {
          if (!ownsTransform) {
            if (_compensatedSurface != surface &&
                CGAffineTransformEqualToTransform(_compensatedSurface.transform, _surfaceAppliedTransform)) {
              _compensatedSurface.transform = _surfaceOriginalTransform;
            }
            _compensatedSurface = surface;
            _surfaceOriginalTransform = surface.transform;
          }
          // Autoresizing adds frame-space deltas while we counter-transform.
          // Resynchronize the clipping surface and our root, including pixel rounding.
          CGRect bounds = ancestor.bounds;
          if (!CGRectEqualToRect(surface.bounds, bounds)) surface.bounds = bounds;
          CGPoint center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
          if (!CGPointEqualToPoint(surface.center, center)) surface.center = center;
          UIView *rootView = self.view;
          if (rootView.superview == surface && !CGRectEqualToRect(rootView.frame, bounds)) {
            rootView.frame = bounds;
          }
          _surfaceAppliedTransform = CGAffineTransformInvert(t);
          surface.transform = _surfaceAppliedTransform;
          compensatedScale = YES;
          if (fabs(t.a - 1) > 0.0001 || fabs(t.d - 1) > 0.0001 ||
              fabs(t.tx) > 0.0001 || fabs(t.ty) > 0.0001) {
            if (!_edgeTouchView) {
              _edgeTouchView = [TrueSheetEdgeTouchView new];
              _edgeTouchView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
              _edgeTouchView.accessibilityElementsHidden = YES;
            }
            _edgeTouchView.contentView = self.view;
            _edgeTouchView.wrapperView = ancestor;
            if (_edgeTouchView.superview != container) {
              _edgeTouchView.frame = container.bounds;
              [container addSubview:_edgeTouchView];
            }
          } else {
            [_edgeTouchView removeFromSuperview];
          }
        }
      }
    }
    surface = ancestor;
  }
  if (!compensatedScale) [_edgeTouchView removeFromSuperview];
  [CATransaction commit];
}

- (void)removeOwnedChrome {
  [self restoreEdgeCompensation];
  _dimmerGeneration++;
  _dimmerTransitioning = NO;
  [_dimHost removeFromSuperview];
  _dimHost = nil;
  _dimFill = nil;
  _systemCornerRadius = 0;
}

- (void)updateSheetChrome {
  if (!self.isViewLoaded) return;
  BOOL independent = self.topLeftCornerRadius != nil || self.topRightCornerRadius != nil;
  if (!independent || _systemCornerRadius == 0) {
    if (!independent) _systemCornerRadius = 0;
    // Observe the system's uniform radius without installing masks/backgrounds
    // on its views. Only our root owns the custom geometry.
    UIView *ancestor = self.view.superview;
    for (NSUInteger depth = 0; ancestor && ancestor != self.sheet.containerView && depth < 8; depth++) {
      _systemCornerRadius = fmax(_systemCornerRadius, ancestor.layer.cornerRadius);
      ancestor = ancestor.superview;
    }
  }
  CGFloat fallback = self.cornerRadius ? self.cornerRadius.doubleValue : _systemCornerRadius;
  BOOL floatingBottom = UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPhone ||
    self.presentation == TrueSheetViewPresentation::Form;
  if (@available(iOS 26.0, *)) floatingBottom = ![self usesEdgeToEdgePage];
  self.sheet.preferredCornerRadius = independent ? 0 :
    (self.cornerRadius ? self.cornerRadius.doubleValue : UISheetPresentationControllerAutomaticDimension);
  [(TrueSheetRootView *)self.view configureBackgroundColor:self.backgroundColor
                                          topBorderWidth:self.topBorderWidth
                                          topBorderColor:self.topBorderColor
                                     topLeftCornerRadius:self.topLeftCornerRadius
                                    topRightCornerRadius:self.topRightCornerRadius
                                    fallbackCornerRadius:fallback
                                      bottomCornerRadius:floatingBottom ? fallback : 0];
  [self updateEdgeCompensation];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
  [super traitCollectionDidChange:previousTraitCollection];
  [self updateSheetChrome];
  [self updateOwnedDimmer];
}

- (void)setupBackground {
  auto effectiveBackgroundBlur = self.backgroundBlur;
  if (@available(iOS 26.0, *)) {
    // iOS 26+ has default liquid glass effect
  } else if (effectiveBackgroundBlur == TrueSheetViewBackgroundBlur::None && !self.backgroundColor) {
    effectiveBackgroundBlur = TrueSheetViewBackgroundBlur::SystemMaterial;
  }

  BOOL hasBlur = effectiveBackgroundBlur != TrueSheetViewBackgroundBlur::None;

  _blurView.backgroundBlur = hasBlur ? effectiveBackgroundBlur : TrueSheetViewBackgroundBlur::None;
  _blurView.blurIntensity = self.blurIntensity;
  _blurView.blurInteraction = self.blurInteraction;
  [_blurView applyBlurEffect];

#if RNTS_IPHONE_OS_VERSION_AVAILABLE(26_1) && !TARGET_OS_MACCATALYST
  if (@available(iOS 26.1, *)) {
    if (!self.isDesignCompatibilityMode) {
      if (self.backgroundColor || hasBlur) {
        BOOL independent = self.topLeftCornerRadius != nil || self.topRightCornerRadius != nil;
        self.sheet.backgroundEffect = [UIColorEffect effectWithColor:
          independent ? UIColor.clearColor : (self.backgroundColor ?: UIColor.clearColor)];
      } else {
        self.sheet.backgroundEffect = nil;
      }
    }
  }
#endif

  [self updateSheetChrome];
}

- (void)setupGrabber {
  BOOL showGrabber = self.grabber && self.draggable;

  if (self.grabberOptions) {
    self.sheet.prefersGrabberVisible = NO;

    GrabberOptions *options = self.grabberOptions;
    _grabberView.accessibilityOptions = self.accessibilityOptions;
    _grabberView.grabberWidth = options.width;
    _grabberView.grabberHeight = options.height;
    _grabberView.topMargin = options.topMargin;
    _grabberView.cornerRadius = options.cornerRadius;
    _grabberView.color = options.color;
    _grabberView.adaptive = @(options.adaptive);
    [_grabberView applyConfiguration];
    _grabberView.hidden = !showGrabber;

    __weak __typeof(self) weakSelf = self;
    _grabberView.onTap = ^{
      [weakSelf handleGrabberTap];
    };
    _grabberView.onIncrement = ^{
      __strong __typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf)
        return;
      NSInteger current = strongSelf.currentDetentIndex;
      NSInteger count = strongSelf->_detents.count;
      if (current >= 0 && current < count - 1) {
        [strongSelf.sheet animateChanges:^{
          [strongSelf resizeToDetentIndex:current + 1];
        }];
      }
    };
    _grabberView.onDecrement = ^{
      __strong __typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf)
        return;
      NSInteger current = strongSelf.currentDetentIndex;
      if (current > 0) {
        [strongSelf.sheet animateChanges:^{
          [strongSelf resizeToDetentIndex:current - 1];
        }];
      } else if (strongSelf.dismissible) {
        [strongSelf.presentingViewController dismissViewControllerAnimated:YES completion:nil];
      }
    };

    [self.view bringSubviewToFront:_grabberView];
  } else {
    self.sheet.prefersGrabberVisible = showGrabber;
    _grabberView.hidden = YES;
    _grabberView.onTap = nil;
    _grabberView.onIncrement = nil;
    _grabberView.onDecrement = nil;
  }

  // Only the topmost sheet may refresh, or a parent's prop update would steal the
  // window accessibility override from the child presented over it.
  if (_isPresented && self.isTopmostPresentedController) {
    [self setupAccessibilityContainer];
  }
}

- (void)handleGrabberTap {
  NSInteger detentCount = _detents.count;
  if (detentCount == 0)
    return;

  NSInteger currentIndex = self.currentDetentIndex;
  if (currentIndex < 0)
    return;

  NSInteger nextIndex = (currentIndex + 1) % detentCount;
  if (nextIndex == 0 && detentCount == 1 && self.dismissible) {
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
  } else {
    [self.sheet animateChanges:^{
      [self resizeToDetentIndex:nextIndex];
    }];
  }
}

- (BOOL)isAnchored {
  return self.anchor == TrueSheetViewAnchor::Left || self.anchor == TrueSheetViewAnchor::Right;
}

- (void)setupAnchorViewInView:(UIView *)parentView {
  if (!parentView)
    return;

  [_anchorView removeFromSuperview];
  _anchorView = nil;

  if (!self.isAnchored) {
    self.sheetPresentationController.sourceView = nil;
    return;
  }

  _anchorView = [[UIView alloc] init];
  _anchorView.userInteractionEnabled = NO;
  _anchorView.translatesAutoresizingMaskIntoConstraints = NO;
  [parentView addSubview:_anchorView];

  NSLayoutAnchor *horizontalAnchor =
    self.anchor == TrueSheetViewAnchor::Right ? parentView.trailingAnchor : parentView.leadingAnchor;

  [NSLayoutConstraint activateConstraints:@[
    [_anchorView.bottomAnchor constraintEqualToAnchor:parentView.bottomAnchor],
    [horizontalAnchor constraintEqualToAnchor:_anchorView.leadingAnchor],
  ]];

  self.sheetPresentationController.sourceView = _anchorView;
}

- (void)setupSheetSizing {
  UISheetPresentationController *sheet = self.sheet;
  if (!sheet)
    return;

  // `presentation` is absolute on the form side: 'form' always renders a
  // centered form sheet and ignores `maxContentWidth`. For 'page' with a
  // custom `maxContentWidth`, prefersPageSizing has to flip to NO since
  // `widthFollowsPreferredContentSizeWhenEdgeAttached` only takes effect
  // when the sheet is edge-attached (Apple API constraint).
  BOOL formSheet = self.presentation == facebook::react::TrueSheetViewPresentation::Form;
  // A phone page's full-window cap is not a request for a narrow floating sheet.
  // Keep that cap meaningful on iPad and when edge-to-edge is not requested.
  BOOL hasMaxWidth = self.maxContentWidth != nil && !formSheet && ![self usesEdgeToEdgePage];

  if (@available(iOS 17.0, *)) {
    sheet.prefersPageSizing = !formSheet && !hasMaxWidth;
  }

  sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = hasMaxWidth;

  if (hasMaxWidth) {
    CGFloat height = self.maxContentHeight ? [self.maxContentHeight floatValue] : self.screenHeight;
    self.preferredContentSize = CGSizeMake([self.maxContentWidth floatValue], height);
  } else {
    self.preferredContentSize = CGSizeZero;
  }
}

- (void)setupSheetProps {
  UISheetPresentationController *sheet = self.sheet;
  if (!sheet)
    return;

  sheet.delegate = self;
  sheet.prefersEdgeAttachedInCompactHeight = YES;
  sheet.prefersScrollingExpandsWhenScrolledToEdge = self.draggable && self.scrollingExpandsSheet;

  if (self.cornerRadius) {
    sheet.preferredCornerRadius = [self.cornerRadius floatValue];
  } else {
    sheet.preferredCornerRadius = UISheetPresentationControllerAutomaticDimension;
  }

  [self setupBackground];
  [self setupGrabber];
  [self updateOwnedDimmer];
}

#pragma mark - UISheetPresentationControllerDelegate

- (BOOL)presentationControllerShouldDismiss:(UIPresentationController *)presentationController {
  return self.dismissible;
}

- (void)sheetPresentationControllerDidChangeSelectedDetentIdentifier:
  (UISheetPresentationController *)sheetPresentationController {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self updateOwnedDimmer];
    NSInteger index = self.currentDetentIndex;
    if (index >= 0) {
      CGFloat detent = [self detentValueForIndex:index];
      [self.delegate viewControllerDidChangeDetent:index position:self.currentPosition detent:detent];
    }
  });
}

#pragma mark - RNSDismissibleModalProtocol

#if RNS_DISMISSIBLE_MODAL_PROTOCOL_AVAILABLE
- (BOOL)isDismissible {
  return NO;
}

- (UIViewController *)newPresentingViewController {
  UIViewController *topmost = self;
  while (topmost.presentedViewController != nil && !topmost.presentedViewController.isBeingDismissed &&
         [topmost.presentedViewController isKindOfClass:[TrueSheetViewController class]]) {
    topmost = topmost.presentedViewController;
  }
  return topmost;
}
#endif

@end
