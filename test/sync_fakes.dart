// ignore_for_file: prefer_initializing_formals — 命名参数不能以 _ 开头
import "dart:async";

import "package:qingdan/sync/sync_config_store.dart";
import "package:qingdan/sync/sync_coordinator.dart";
import "package:qingdan/sync/sync_report.dart";
import "package:qingdan/sync/sync_runner.dart";

/// 同步测试共享假件（协调器测试 + 状态 UI 测试共用）。
/// 全部离线：假时钟推进时间，假 runner 不碰网络。

/// 假时钟：只在 [advance] 时推进；到期 timer 按时刻顺序触发。
/// periodic 的重排基准用「上次到期时刻」，与 dart:async 语义一致。
class FakeTimers implements SyncTimers {
  final List<_Entry> _entries = <_Entry>[];
  Duration _elapsed = Duration.zero;
  final DateTime _origin = DateTime(2026, 1, 1);

  @override
  DateTime now() => _origin.add(_elapsed);

  @override
  Cancelable after(Duration delay, void Function() callback) {
    final _Entry e = _Entry(_elapsed + delay, callback, null);
    _entries.add(e);
    return _Handle(e);
  }

  @override
  Cancelable periodic(Duration interval, void Function() callback) {
    final _Entry e = _Entry(_elapsed + interval, callback, interval);
    _entries.add(e);
    return _Handle(e);
  }

  Future<void> advance(Duration delta) async {
    final Duration target = _elapsed + delta;
    while (true) {
      _Entry? next;
      for (final _Entry e in _entries) {
        if (e.cancelled || e.due > target) continue;
        if (next == null || e.due < next.due) next = e;
      }
      if (next == null) break;
      _elapsed = next.due;
      next.callback();
      await flushMicrotasks();
      if (next.interval != null && !next.userCancelled) {
        next.due = next.due + next.interval!;
      } else {
        next.cancelled = true;
      }
    }
    _elapsed = target;
    await flushMicrotasks();
  }
}

class _Entry {
  _Entry(this.due, this.callback, this.interval);

  Duration due;
  final void Function() callback;
  final Duration? interval;
  bool cancelled = false;
  bool userCancelled = false;
}

class _Handle implements Cancelable {
  _Handle(this._entry);

  final _Entry _entry;

  @override
  void cancel() {
    _entry.cancelled = true;
    _entry.userCancelled = true;
  }
}

/// 推进异步链到底（不依赖真实时间）。
Future<void> flushMicrotasks() async {
  for (int i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// 网络类失败的替身（不 import dart:io，避免测试平台差异）。
class SocketFailure implements Exception {
  const SocketFailure();
}

/// 每次 run 立即返回成功报告（或按 onRun 抛错），记录调用次数。
class CountingRunner implements SyncRunner {
  CountingRunner({void Function()? onRun}) : _onRun = onRun;

  final void Function()? _onRun;
  int runs = 0;

  @override
  Future<SyncReport> run() async {
    runs++;
    _onRun?.call();
    return SyncReport();
  }

  @override
  int get requestsUsedInWindow => 0;

  @override
  Future<void> dispose() async {}
}

/// 每次 run 返回由测试手动完成的 Future（验证单飞）。
class DeferredRunner implements SyncRunner {
  final List<Completer<SyncReport>> _pending = <Completer<SyncReport>>[];
  int started = 0;

  void complete(int index) => _pending[index].complete(SyncReport());

  @override
  Future<SyncReport> run() {
    started++;
    final Completer<SyncReport> c = Completer<SyncReport>();
    _pending.add(c);
    return c.future;
  }

  @override
  int get requestsUsedInWindow => 0;

  @override
  Future<void> dispose() async {}
}

/// 固定返回同一个 runner 的工厂。
class FakeFactory implements SyncRunnerFactory {
  FakeFactory(this.runner);

  final SyncRunner runner;

  @override
  SyncRunner create(SyncConfig config) => runner;

  @override
  int get requestsUsedInWindow => runner.requestsUsedInWindow;

  @override
  Future<void> dispose() async {}
}
