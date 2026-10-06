/// The time limit a response-time test or a baseline allows, from how long one response took.
///
/// Three times what was measured, rounded up to a tidy number, and never below [floorMs]: one measurement says
/// little about the next, a CI machine is slower than a laptop, and a test that fails on a slow afternoon is
/// worse than none.
abstract final class ResponseTimeBound {
  static const factor = 3;
  static const floorMs = 500;

  static int forMeasured(int measuredMs) {
    final measured = measuredMs < 0 ? 0 : measuredMs;
    final raw = measured * factor;
    final step = raw < 5000
        ? 100
        : raw < 30000
            ? 500
            : 1000;
    final rounded = ((raw + step - 1) ~/ step) * step;
    return rounded < floorMs ? floorMs : rounded;
  }
}
