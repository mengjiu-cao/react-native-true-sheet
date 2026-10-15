// Pure geometry shared by native chrome and host-only smoke checks.
#pragma once

#include <cmath>

namespace truesheet {
struct TopCorners {
  double left;
  double right;
};

inline double nonnegative(double value) {
  return std::isfinite(value) && value > 0 ? value : 0;
}

inline TopCorners topCorners(double width, double height, double left, double right) {
  width = nonnegative(width);
  height = nonnegative(height);
  left = std::fmin(nonnegative(left), height);
  right = std::fmin(nonnegative(right), height);
  const double sum = left + right;
  const double scale = sum > width && sum > 0 ? width / sum : 1;
  return {left * scale, right * scale};
}

struct ChromeGeometry {
  TopCorners top;
  double bottom;
  double borderWidth;
};

inline ChromeGeometry chromeGeometry(double width, double height, double left, double right,
                                     double bottom, double borderWidth) {
  width = nonnegative(width);
  height = nonnegative(height);
  const TopCorners top = topCorners(width, height, left, right);
  return {
    top,
    std::fmin(nonnegative(bottom),
              std::fmin(width / 2, height - std::fmax(top.left, top.right))),
    std::fmin(nonnegative(borderWidth), std::fmin(width, height))
  };
}

} // namespace truesheet
