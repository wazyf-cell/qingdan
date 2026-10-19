/// 退出学习通要**真的**取消已排的到期提醒（M6B §B4 对话框那句「已排的到期提醒
/// 会一并取消」的兑现测试）。
///
/// 这条测试写出来时是红的：`cancelAllChaoxingNotifications` 是没人赋值的空实现，
/// `chaoxing.notify.snapshot` 不随 logout 清，协调器下一次重排照旧读同一份快照 →
/// 用户退了学习通，「课程甲 · 作业1 截止前 2 小时」照样会响（课程名是合成值，
/// 形状取自真实条目）。
///
/// 夹具刻意把**清单提醒**也排进去，是为了钉死另一头：只许摘掉学习通那一路的数据源，
/// 不许把无关的清单提醒一起 cancel 掉（`NotificationService.rescheduleAll` 是
/// 「先 cancelAll 再全量重排」，所以判据只能是「重排后还剩哪些 kind」）。
///
/// 全程不碰数据库：任务侧走 `TaskReminderSource` 注入的内存表，通知侧走假 sink，
/// 学习通侧走 mock prefs + 假凭据库 + 假客户端。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/domain/task.dart';
import 'package:qingdan/features/chaoxing/chaoxing_actions.dart';
import 'package:qingdan/features/chaoxing/chaoxing_keys.dart';
import 'package:qingdan/features/chaoxing/chaoxing_model.dart';
import 'package:qingdan/features/chaoxing/chaoxing_pane.dart';
import 'package:qingdan/features/chaoxing/chaoxing_prefs.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/notify/chaoxing_snapshot.dart';
import 'package:qingdan/notify/notification_service.dart';
import 'package:qingdan/notify/notify_settings.dart';
import 'package:qingdan/notify/reminder_coordinator.dart';
import 'package:qingdan/notify/reminder_plan.dart' show kChaoxingReminderKind,
    kTaskReminderKind;
import 'package:qingdan/sync/secure_store.dart';
import 'package:qingdan/theme/app_theme.dart';

import 'chaoxing_harness.dart' show FakeChaoxingClient, cxHomework;
import 'reminder_coordinator_harness.dart' show FakeNotificationSink, kFast;

/// 一份「学习通 + 清单」双域都排好了提醒的环境。
class _Env {
  _Env._(this.prefs, this.sink, this.snapshot, this.model, this.coordinator);

  static Future<_Env> create({bool withCoordinator = true}) async {
    // 免打扰显式关掉：默认 23:00–07:00 会把「提前量已过期」的提醒顺延到次日 07:00，
    // 条数就随墙上钟漂了（同 reminder_coordinator_harness 的理由）。
    SharedPreferences.setMockInitialValues(
        <String, Object>{'notify.quietHoursEnabled': false});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final FakeNotificationSink sink = FakeNotificationSink();
    final ChaoxingSnapshotStore snapshot = ChaoxingSnapshotStore(prefs: prefs);
    final NotifySettingsStore settings = NotifySettingsStore(prefs: prefs);
    await settings.load();
    final FakeChaoxingClient client = FakeChaoxingClient()
      ..tasks = <ChaoxingTask>[
        cxHomework('1', dueAt: DateTime.now().add(const Duration(hours: 3)))
      ];
    final ChaoxingModel model = ChaoxingModel(
      secure: InMemorySecureStore(<String, String>{
        ChaoxingModel.kCookieKey: 'placeholder-not-a-credential',
      }),
      prefs: ChaoxingPrefs(prefs: prefs),
      clientFactory: (String _) => client,
    );
    // fetchedAt 置为当下：面板的 autoRefreshOnce 会因此跳过首刷，快照由这里直接写，
    // 免得「排了几条」要看面板的自动刷新什么时候跑。
    model.tasks = client.tasks;
    model.fetchedAt = DateTime.now();
    model.loggedIn = true;
    await snapshot.writeSnapshot(
        chaoxingSnapshotOf(client.tasks, const <String>{}, DateTime.now()));

    final _Env env = _Env._(prefs, sink, snapshot, model, null);
    if (withCoordinator) {
      env.coordinator = ReminderCoordinator(
        service: NotificationService(sink: sink, supported: () => true),
        settings: settings,
        snapshot: snapshot,
        taskSource: () async => env.taskTable,
        sources: <Listenable>[model],
        debounce: kFast,
      );
    }
    return env;
  }

  final SharedPreferences prefs;
  final FakeNotificationSink sink;
  final ChaoxingSnapshotStore snapshot;
  final ChaoxingModel model;
  ReminderCoordinator? coordinator;

  /// 清单侧一条 40 分钟后到期的任务：提前 30 分钟 + 到期时刻 = 2 条清单提醒。
  List<Task> taskTable = <Task>[
    Task(id: 't1', title: '交实验报告', dueDate: DateTime.now().add(
        const Duration(minutes: 40)))
  ];

  int get cxScheduled => sink.scheduled
      .where((ScheduledReminder r) => r.reminder.kind == kChaoxingReminderKind)
      .length;
  int get taskScheduled => sink.scheduled
      .where((ScheduledReminder r) => r.reminder.kind == kTaskReminderKind)
      .length;
}

void main() {
  late ChaoxingLoginLauncher realLogin;
  late ChaoxingDetailLauncher realDetail;
  late ChaoxingCookieJarCleaner realJar;
  setUp(() {
    realLogin = chaoxingLoginLauncher;
    realDetail = chaoxingDetailLauncher;
    realJar = chaoxingCookieJarCleaner;
    chaoxingLoginLauncher = (BuildContext _) async => null;
    chaoxingDetailLauncher = (BuildContext _, ChaoxingTask _) {};
    chaoxingCookieJarCleaner = () async {};
  });
  tearDown(() {
    chaoxingLoginLauncher = realLogin;
    chaoxingDetailLauncher = realDetail;
    chaoxingCookieJarCleaner = realJar;
  });

  Future<void> pump(WidgetTester tester, _Env env) async {
    tester.view.physicalSize = const Size(411, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final ReminderCoordinator? c = env.coordinator;
    await tester.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<ChaoxingModel>.value(value: env.model),
        if (c != null) Provider<ReminderCoordinator>.value(value: c),
      ],
      child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChaoxingPane())),
    ));
    await tester.pump();
  }

  /// 点一下并等真实异步落地（同 chaoxing_harness 的 tapIo：runAsync 区里跑真 future）。
  Future<void> tapIo(WidgetTester tester, Finder target) async {
    await tester.runAsync(() async {
      await tester.tap(target);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();
    });
    await tester.pumpAndSettle();
  }

  testWidgets('退出学习通：快照被清、学习通提醒消失、清单提醒照排',
      (WidgetTester tester) async {
    final _Env env = await _Env.create();
    await tester.runAsync(() async {
      await env.coordinator!.rescheduleNow();
    });
    expect(env.cxScheduled, 2, reason: '前置条件：两档提前量各排一条学习通提醒');
    expect(env.taskScheduled, 2, reason: '前置条件：清单提醒在场');
    expect(env.prefs.getString(kChaoxingSnapshotKey), isNotNull);

    await pump(tester, env);
    await tapIo(tester, find.byKey(ValueKey<String>(ChaoxingKeys.account)));
    await tapIo(
        tester, find.byKey(ValueKey<String>(ChaoxingKeys.menuLogout)));
    await tapIo(tester, find.widgetWithText(FilledButton, '退出并保留隐藏列表'));

    expect(env.model.loggedIn, isFalse, reason: '前置：确实走到了退出');
    // ① 界面承诺①：快照这份数据源被清掉
    expect(env.prefs.getString(kChaoxingSnapshotKey), isNull,
        reason: '退出登录必须清 chaoxing.notify.snapshot，否则下次重排照旧读它');
    // ② 界面承诺②：已排的学习通提醒真的不在了
    expect(env.cxScheduled, 0, reason: '「已排的到期提醒会一并取消」必须是真的');
    // ③ 不许顺手把清单提醒一起取消
    expect(env.taskScheduled, 2, reason: '只清学习通那一路，清单提醒不受影响');
    await env.coordinator?.dispose();
  });

  testWidgets('协调器没装配（建库失败的降级形态）：退出仍清快照、不抛',
      (WidgetTester tester) async {
    final _Env env = await _Env.create(withCoordinator: false);
    expect(env.prefs.getString(kChaoxingSnapshotKey), isNotNull);

    await pump(tester, env);
    await tapIo(tester, find.byKey(ValueKey<String>(ChaoxingKeys.account)));
    await tapIo(
        tester, find.byKey(ValueKey<String>(ChaoxingKeys.menuLogout)));
    await tapIo(tester, find.widgetWithText(FilledButton, '退出并保留隐藏列表'));

    expect(env.model.loggedIn, isFalse);
    expect(env.prefs.getString(kChaoxingSnapshotKey), isNull,
        reason: '协调器不在也要把快照清掉，否则下次成功启动会把已退出账号的提醒排回来');
  });
}
