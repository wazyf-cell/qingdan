// 通知引擎层单测（M6-C2 的排程侧 + 设置侧）。
//
// 断言「先 cancelAll 再全量重排」的**调用序列**与 **id = 过滤后下标 0..N-1 连续**，
// 靠的是注入假 NotificationSink（真插件在没有平台通道的测试里跑不起来）。
// 另外覆盖：任何一次插件调用抛异常都不能冒出去（通知是增强功能）、平台闸门、
// 以及 11 个 notify.* key 的逐字读写。
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show AndroidScheduleMode, DidReceiveNotificationResponseCallback;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/notify/notification_service.dart';
import 'package:qingdan/notify/notify_settings.dart';
import 'package:qingdan/notify/reminder_plan.dart';

class _FakeSink implements NotificationSink {
  final List<String> calls = <String>[];
  final List<ScheduledReminder> scheduled = <ScheduledReminder>[];
  final Set<int> failScheduleIds = <int>{};
  bool failInitialize = false, failPermission = false, failEnabled = false,
      failCancel = false;
  bool permissionGranted = true, systemEnabled = true;

  @override
  Future<void> initialize(
      {DidReceiveNotificationResponseCallback? onResponse}) async {
    calls.add('initialize');
    if (failInitialize) throw StateError('平台不支持');
  }

  @override
  Future<bool> requestPermission() async {
    calls.add('requestPermission');
    if (failPermission) throw StateError('MissingPluginException');
    return permissionGranted;
  }

  @override
  Future<bool> isEnabled() async {
    calls.add('isEnabled');
    if (failEnabled) throw StateError('MissingPluginException');
    return systemEnabled;
  }

  @override
  Future<void> cancelAll() async {
    calls.add('cancelAll');
    if (failCancel) throw StateError('插件没接上');
  }

  @override
  Future<void> schedule(ScheduledReminder item) async {
    calls.add('schedule:${item.id}');
    if (failScheduleIds.contains(item.id)) throw StateError('闹钟数量已满');
    scheduled.add(item);
  }
}

Reminder _reminder(String key, DateTime at) => Reminder(
    kind: kTaskReminderKind,
    sourceKey: key,
    at: at,
    title: '待办提醒',
    body: key,
    subtext: '现在到期',
    payload: key);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeSink sink;
  late NotificationService service;

  setUp(() {
    sink = _FakeSink();
    service = NotificationService(sink: sink, supported: () => true);
  });

  group('排程策略', () {
    test('rescheduleAll 先 cancelAll，再按列表顺序逐条排', () async {
      final DateTime t = DateTime.now();
      final int n = await service.rescheduleAll(
          [_reminder('a', t.add(const Duration(minutes: 5))),
           _reminder('b', t.add(const Duration(minutes: 9)))]);
      expect(n, 2);
      expect(sink.calls,
          ['cancelAll', 'schedule:0', 'schedule:1'],
          reason: '一律全量重排，不做增量 diff');
      expect(sink.scheduled.map((ScheduledReminder e) => e.reminder.sourceKey),
          ['a', 'b'],
          reason: 'id 的顺序就是列表顺序');
    });

    test('id 是过滤后列表的连续下标 0..N-1（不是 hash）', () async {
      final DateTime t = DateTime.now();
      await service.rescheduleAll(<Reminder>[
        _reminder('a', t.add(const Duration(minutes: 1))),
        _reminder('b', t.add(const Duration(minutes: 2))),
        _reminder('c', t.add(const Duration(minutes: 3))),
      ]);
      expect(sink.scheduled.map((ScheduledReminder e) => e.id), <int>[0, 1, 2]);
    });

    test('已过去的提醒不排，且过滤后 id 仍然连续', () async {
      final DateTime t = DateTime.now();
      final int n = await service.rescheduleAll(<Reminder>[
        _reminder('过去1', t.subtract(const Duration(minutes: 30))),
        _reminder('将来1', t.add(const Duration(minutes: 1))),
        _reminder('过去2', t.subtract(const Duration(hours: 2))),
        _reminder('将来2', t.add(const Duration(hours: 1))),
      ]);
      expect(n, 2);
      expect(sink.scheduled.map((ScheduledReminder e) => e.id), <int>[0, 1],
          reason: '跳过历史条目后不能留下 id 空洞');
      expect(sink.scheduled.map((ScheduledReminder e) => e.reminder.sourceKey),
          ['将来1', '将来2']);
    });

    test('一次最多排 200 条', () async {
      final DateTime t = DateTime.now();
      final int n = await service.rescheduleAll(<Reminder>[
        for (int i = 0; i < 250; i++)
          _reminder('k$i', t.add(Duration(minutes: i + 1)))
      ]);
      expect(n, kMaxScheduledReminders);
      expect(sink.scheduled.length, kMaxScheduledReminders);
      expect(sink.scheduled.last.id, kMaxScheduledReminders - 1);
    });

    test('总开关关掉由调用层给空列表：这里断言空列表也会先 cancelAll', () async {
      final int n = await service.rescheduleAll(const <Reminder>[]);
      expect(n, 0);
      expect(sink.calls, ['cancelAll'], reason: '关掉提醒要能把已排的清干净');
    });

    test('平台不支持（Windows）时一个插件方法都不调', () async {
      final NotificationService off =
          NotificationService(sink: sink, supported: () => false);
      expect(await off.initialize(), isFalse);
      expect(await off.requestPermission(), isFalse);
      expect(await off.notificationsEnabled(), isFalse);
      await off.cancelAll();
      expect(await off.rescheduleAll([_reminder('a', DateTime.now())]), 0);
      expect(sink.calls, isEmpty);
      expect(off.supported, isFalse);
    });
  });

  group('异常必须被吞掉（通知不能拖垮启动）', () {
    test('initialize 抛异常 → 返回 false 而不是冒出去', () async {
      sink.failInitialize = true;
      expect(await service.initialize(), isFalse);
    });

    test('权限请求 / 状态查询抛异常 → false', () async {
      sink.failPermission = true;
      sink.failEnabled = true;
      expect(await service.requestPermission(), isFalse);
      expect(await service.notificationsEnabled(), isFalse);
    });

    test('权限与系统开关正常时透传真值', () async {
      expect(await service.requestPermission(), isTrue);
      expect(await service.notificationsEnabled(), isTrue);
      sink.permissionGranted = false;
      sink.systemEnabled = false;
      expect(await service.requestPermission(), isFalse);
      expect(await service.notificationsEnabled(), isFalse);
    });

    test('cancelAll 抛异常：继续往下排，不中断', () async {
      sink.failCancel = true;
      final int n = await service
          .rescheduleAll([_reminder('a', DateTime.now().add(const Duration(minutes: 3)))]);
      expect(n, 1);
      expect(sink.calls, ['cancelAll', 'schedule:0']);
    });

    test('单条排程失败不影响其余条，返回成功数', () async {
      sink.failScheduleIds.add(1);
      final DateTime t = DateTime.now();
      final int n = await service.rescheduleAll(<Reminder>[
        _reminder('a', t.add(const Duration(minutes: 1))),
        _reminder('b', t.add(const Duration(minutes: 2))),
        _reminder('c', t.add(const Duration(minutes: 3))),
      ]);
      expect(n, 2);
      expect(sink.scheduled.map((ScheduledReminder e) => e.id), <int>[0, 2]);
    });
  });

  group('平台闸门与常量', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('只有 Android 认为支持（§0.1）', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(notificationPlatformSupported(), isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(notificationPlatformSupported(), isFalse);
    });

    test('通道与闹钟模式常量按规格钉住（改了旧通道会残留）', () {
      expect(kTaskChannelId, 'qingdan_task');
      expect(kTaskChannelName, '清单提醒');
      expect(kChaoxingChannelId, 'qingdan_chaoxing');
      expect(kChaoxingChannelName, '学习通提醒');
      expect(kAndroidScheduleMode, AndroidScheduleMode.inexactAllowWhileIdle,
          reason: '非精确闹钟：不要引入 SCHEDULE_EXACT_ALARM / USE_EXACT_ALARM 权限');
    });
  });

  group('NotifySettings：11 个 key 逐字照抄总纲 §五', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
    });

    test('默认值：两域各两档都开、30/120/30 分钟、免打扰 23:00–07:00', () {
      final NotifySettings s = NotifySettings();
      expect(s.enabled, isTrue);
      expect(s.taskLeadEnabled, isTrue);
      expect(s.taskLeadMinutes, 30);
      expect(s.taskDueEnabled, isTrue);
      expect(s.chaoxingLead1Enabled, isTrue);
      expect(s.chaoxingLead1Minutes, 120);
      expect(s.chaoxingLead2Enabled, isTrue);
      expect(s.chaoxingLead2Minutes, 30);
      expect(s.quietHoursEnabled, isTrue);
      expect(s.quietStart, 1380);
      expect(s.quietEnd, 420);
      expect(s.quietStartText, '23:00');
      expect(s.quietEndText, '07:00');
    });

    test('prefs 里的 key 名与规格逐字一致，且写进去能原样读回', () async {
      await NotifySettings.fromPrefs(prefs).writeTo(prefs);
      expect(prefs.getBool('notify.enabled'), isTrue);
      expect(prefs.getBool('notify.task.leadEnabled'), isTrue);
      expect(prefs.getInt('notify.task.leadMinutes'), 30);
      expect(prefs.getBool('notify.task.dueEnabled'), isTrue);
      expect(prefs.getBool('notify.chaoxing.lead1Enabled'), isTrue);
      expect(prefs.getInt('notify.chaoxing.lead1Minutes'), 120);
      expect(prefs.getBool('notify.chaoxing.lead2Enabled'), isTrue);
      expect(prefs.getInt('notify.chaoxing.lead2Minutes'), 30);
      expect(prefs.getBool('notify.quietHoursEnabled'), isTrue);
      expect(prefs.getInt('notify.quietStart'), 1380);
      expect(prefs.getInt('notify.quietEnd'), 420);

      await prefs.setInt('notify.task.leadMinutes', 60);
      expect(NotifySettings.fromPrefs(prefs).taskLeadMinutes, 60);
    });

    test('缺项回落默认值（首启或用户清了应用数据）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'notify.enabled': false,
      });
      final SharedPreferences p = await SharedPreferences.getInstance();
      final NotifySettings s = NotifySettings.fromPrefs(p);
      expect(s.enabled, isFalse);
      expect(s.taskLeadMinutes, 30);
      expect(s.quietStart, 1380);
    });

    test('store.apply：改内存 + 落盘 + 通知监听者（重排挂在这里）', () async {
      final NotifySettingsStore store = NotifySettingsStore(prefs: prefs);
      await store.load();
      int notified = 0;
      store.addListener(() => notified++);
      await store.apply((NotifySettings s) => s.chaoxingLead2Minutes = 15);
      expect(store.value.chaoxingLead2Minutes, 15);
      expect(prefs.getInt('notify.chaoxing.lead2Minutes'), 15,
          reason: '不能只改 UI 状态不落盘');
      expect(notified, greaterThanOrEqualTo(1));
    });

    test('store.setEnabled 只动总开关', () async {
      final NotifySettingsStore store = NotifySettingsStore(prefs: prefs);
      await store.load();
      await store.setEnabled(false);
      expect(prefs.getBool('notify.enabled'), isFalse);
      expect(prefs.getInt('notify.task.leadMinutes'), 30, reason: '别把别的项写坏');
    });

    test('NotifySettings 可以直接当 ReminderConfig 用（规划器认它）', () {
      final DateTime now = DateTime(2026, 10, 18, 10, 0);
      final List<Reminder> got = planTaskReminders(
          [Task(id: 't1', title: '交周报', dueDate: now.add(const Duration(minutes: 40)))],
          now,
          NotifySettings());
      expect(got.map((Reminder r) => r.at),
          [now.add(const Duration(minutes: 10)), now.add(const Duration(minutes: 40))]);
    });
  });
}
