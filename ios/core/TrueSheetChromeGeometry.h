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

// Only the small, axis-aligned resting iOS floating-sheet inset is eligible.
// Never invert rotation, a large drag translation, or a collapsed scale.
inline bool canCompensate(double a, double b, double c, double d, double tx, double ty) {
  return std::isfinite(a) && std::isfinite(d) && a >= 0.8 && a <= 1 &&
    d >= 0.8 && d <= 1 &&
    std::fabs(b) < 0.0001 && std::fabs(c) < 0.0001 &&
    std::fabs(tx) <= 40 && std::fabs(ty) <= 40;
}
} // namespace truesheet
