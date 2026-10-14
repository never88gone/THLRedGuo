/// 连点计数门：同一入口连续点击达到阈值时触发一次，切换入口即清零。
class RepeatTapGate {
  RepeatTapGate({this.threshold = 6}) : assert(threshold > 0);
  final int threshold;
  Object? _last;
  int _taps = 0;

  /// 当前已累计的连续点击数。
  int get taps => _taps;

  /// 记录一次对 [id] 的点击。连续点击同一入口达到阈值时返回 true 并重置计数。
  bool register(Object id) {
    if (id == _last) {
      _taps++;
    } else {
      _last = id;
      _taps = 1;
    }
    if (_taps >= threshold) {
      reset();
      return true;
    }
    return false;
  }

  void reset() {
    _taps = 0;
    _last = null;
  }
}
