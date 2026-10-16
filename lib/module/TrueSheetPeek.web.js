"use strict";

import { createContext, useContext, useEffect, useRef } from 'react';
import { View } from 'react-native';

/**
 * Reports the measured peek content height to the owning TrueSheet.
 * @internal
 */
import { jsx as _jsx } from "react/jsx-runtime";
export const TrueSheetPeekContext = /*#__PURE__*/createContext(null);

/**
 * Distance from the top of the content view to the bottom of the peek view,
 * so the peek view's offset within the content (padding, views above it)
 * counts toward the peek detent. Both rects live in the drawer's transformed
 * subtree, so an in-flight translate cancels out of the delta.
 * @internal
 */
export const measurePeekContentHeight = (peekElement, contentElement) => peekElement.getBoundingClientRect().bottom - contentElement.getBoundingClientRect().top;

/**
 * Wrapper component that marks its children as the sheet's peek content.
 * When rendered within a `TrueSheet`, the `"peek"` detent reveals everything
 * from the top of the sheet through the bottom of this component — content
 * below it stays hidden until the sheet is expanded.
 */
export const TrueSheetPeek = ({
  onLayout,
  ...rest
}) => {
  const context = useContext(TrueSheetPeekContext);
  const localRef = useRef(null);

  // Register into the sheet's peek ref so it can measure the peek live
  // during detent geometry computation (state lags the first willPresent).
  const viewRef = context?.peekRef ?? localRef;
  useEffect(() => () => context?.setPeekContentHeight(0), [context]);
  const handleLayout = event => {
    if (context) {
      // On web, View refs resolve to the underlying DOM elements.
      const peekElement = viewRef.current;
      const contentElement = context.contentRef.current;
      const bottom = peekElement && contentElement ? measurePeekContentHeight(peekElement, contentElement) : event.nativeEvent.layout.height;
      context.setPeekContentHeight(bottom);
    }
    onLayout?.(event);
  };
  return /*#__PURE__*/_jsx(View, {
    ...rest,
    ref: viewRef,
    onLayout: handleLayout
  });
};
//# sourceMappingURL=TrueSheetPeek.web.js.map