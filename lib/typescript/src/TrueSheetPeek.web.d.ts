import { type RefObject } from 'react';
import { View, type ViewProps } from 'react-native';
/**
 * Reports the measured peek content height to the owning TrueSheet.
 * @internal
 */
export interface TrueSheetPeekContextValue {
    contentRef: RefObject<View | null>;
    peekRef: RefObject<View | null>;
    setPeekContentHeight: (height: number) => void;
}
export declare const TrueSheetPeekContext: import("react").Context<TrueSheetPeekContextValue | null>;
/**
 * Distance from the top of the content view to the bottom of the peek view,
 * so the peek view's offset within the content (padding, views above it)
 * counts toward the peek detent. Both rects live in the drawer's transformed
 * subtree, so an in-flight translate cancels out of the delta.
 * @internal
 */
export declare const measurePeekContentHeight: (peekElement: HTMLElement, contentElement: HTMLElement) => number;
/**
 * Wrapper component that marks its children as the sheet's peek content.
 * When rendered within a `TrueSheet`, the `"peek"` detent reveals everything
 * from the top of the sheet through the bottom of this component — content
 * below it stays hidden until the sheet is expanded.
 */
export declare const TrueSheetPeek: ({ onLayout, ...rest }: ViewProps) => import("react/jsx-runtime").JSX.Element;
//# sourceMappingURL=TrueSheetPeek.web.d.ts.map