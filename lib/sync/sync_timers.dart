/// 定时器与时钟抽象（M3 §1.2/§1.3）。
///
/// 抽出来的唯一目的：让协调器的单测注入假时钟，离线推进 30 分钟兜底与
/// 分钟级退避，不必真等。生产实现只是 dart:async Timer 的薄包装。
library;

import "dart:async";

/// 可取消的定时器句柄。不让测试去实现 dart:async 的 Timer，只暴露 cancel。
abstract class Cancelable {
  void cancel();
}

/// 定时与取时：测试注入假实现即可控制时间推进。
abstract class SyncTimers {
  Cancelable after(Duration delay, void Function() callback);

  Cancelable periodic(Duration interval, void Function() callback);

  DateTime now();
}

/// 生产实现：dart:async Timer + DateTime.now。
class RealSyncTimers implements SyncTimers {
  const RealSyncTimers();

  @override
  Cancelable after(Duration delay, void Function() callback) =>
      _TimerHandle(Timer(delay, callback));

  @override
  Cancelable periodic(Duration interval, void Function() callback) =>
      _TimerHandle(Timer.periodic(interval, (_) => callback()));

  @override
  DateTime now() => DateTime.now();
}

class _TimerHandle implements Cancelable {
  _TimerHandle(this._timer);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}
