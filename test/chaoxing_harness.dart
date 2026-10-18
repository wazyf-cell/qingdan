import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/features/chaoxing/chaoxing_actions.dart';
import 'package:qingdan/features/chaoxing/chaoxing_detail_page.dart';
import 'package:qingdan/features/chaoxing/chaoxing_keys.dart';
import 'package:qingdan/features/chaoxing/chaoxing_login.dart';
import 'package:qingdan/features/chaoxing/chaoxing_model.dart';
import 'package:qingdan/features/chaoxing/chaoxing_pane.dart';
import 'package:qingdan/features/chaoxing/chaoxing_prefs.dart';
import 'package:qingdan/import/chaoxing/chaoxing_client.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/sync/secure_store.dart';
import 'package:qingdan/theme/app_theme.dart';

/// 占位串：只用来让 `loggedIn` 成立。**不是任何真实凭据的形状**（项目铁律：
/// 测试数据里不得出现 cookie / `_uid` 值）。
const String kFakeCookie = 'placeholder-not-a-credential';

/// 计次的假客户端：`ChaoxingModel` 的 `clientFactory` 注入点用它替代真实
/// `dart:io HttpClient`，这样「刷新收敛到两处」能被数着请求次数验证。
class FakeChaoxingClient extends ChaoxingClient {
  FakeChaoxingClient() : super(cookie: kFakeCookie);

  List<ChaoxingTask> tasks = const <ChaoxingTask>[];
  int fetches = 0;
  bool failAuth = false;

  @override
  Future<List<ChaoxingTask>> fetchAllTasks() async {
    fetches++;
    if (failAuth) throw ChaoxingAuthException();
    courseCount = 1;
    return tasks;
  }

  @override
  void close() {}
}

/// 固定时钟，让「N 分钟前 / 紧急度」的期望值可以写死。
final DateTime kCxNow = DateTime(2026, 10, 18, 12);

/// 作业页条目（带 serverStatus 才会进「全部作业」页签）。
ChaoxingTask cxHomework(String id,
    {String courseId = 'c1',
    String? clazzId = 'z1',
    String title = '作业',
    String course = '课程甲',
    DateTime? dueAt,
    bool ongoing = true,
    bool serverDone = false,
    String? status = '未提交'}) {
  final ChaoxingTask t = ChaoxingTask(
      id: id,
      courseId: courseId,
      courseName: course,
      title: '$title$id',
      kind: '作业',
      ongoing: ongoing,
      dueAt: dueAt,
      serverStatus: status,
      serverDone: serverDone,
      clazzId: clazzId);
  return t;
}

/// 课堂活动条目（没有 serverStatus）。
ChaoxingTask cxActivity(String id,
    {String courseId = 'c1',
    String? clazzId,
    DateTime? dueAt,
    bool ongoing = true,
    String kind = '签到'}) {
  return ChaoxingTask(
      id: id,
      courseId: courseId,
      courseName: '课程甲',
      title: '活动$id',
      kind: kind,
      ongoing: ongoing,
      dueAt: dueAt,
      clazzId: clazzId);
}

/// 学习通面板的 widget 测试环境（只装 `ChaoxingModel`，不碰数据库）。
class ChaoxingHarness {
  ChaoxingHarness();

  late ChaoxingModel model;
  late FakeChaoxingClient client;
  late InMemorySecureStore store;
  late SharedPreferences prefs;

  /// 面板里换掉的假 launcher，`tearDown` 用 [restoreSeams] 还原。
  int detailLaunches = 0;
  int loginLaunches = 0;
  int jarClears = 0;

  Future<void> start({
    List<ChaoxingTask> tasks = const <ChaoxingTask>[],
    bool loggedIn = true,

    /// true = 已经拉过一次（fetchedAt = 时钟当前值），首帧不会再自动刷新。
    /// 测「自动刷新一次」时传 false。
    bool seeded = true,
    Map<String, Object> seed = const <String, Object>{},
  }) async {
    SharedPreferences.setMockInitialValues(seed);
    prefs = await SharedPreferences.getInstance();
    client = FakeChaoxingClient()..tasks = tasks;
    store = InMemorySecureStore(<String, String>{
      if (loggedIn) ChaoxingModel.kCookieKey: kFakeCookie,
    });
    model = ChaoxingModel(
      secure: store,
      prefs: ChaoxingPrefs(prefs: prefs),
      clock: () => kCxNow,
      clientFactory: (String _) => client,
    );
    await model.restore();
    if (seeded) {
      model.tasks = tasks;
      model.fetchedAt = kCxNow;
      model.courseCount = 1;
      model.activityCount = tasks.length;
    }
  }

  /// 面板的启动路径（`ChaoxingPane` 只依赖 `ChaoxingModel`，所以不装真库）。
  Future<void> pump(WidgetTester tester,
      {double width = 411, double height = 915, bool visible = true}) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<ChaoxingModel>.value(value: model),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: visible ? const ChaoxingPane() : const SizedBox()),
      ),
    ));
    await tester.pump();
  }

  /// 装好三个 WebView 注入点（真实实现会 push WebView，测试环境没有平台实现）。
  void stubSeams() {
    chaoxingDetailLauncher = (BuildContext _, ChaoxingTask t) => detailLaunches++;
    chaoxingLoginLauncher = (BuildContext _) async {
      loginLaunches++;
      return null;
    };
    chaoxingCookieJarCleaner = () async => jarClears++;
  }

  /// 还原成生产实现，避免污染同文件后面的用例。
  void restoreSeams() {
    chaoxingDetailLauncher = showChaoxingDetail;
    chaoxingLoginLauncher = showChaoxingLogin;
    chaoxingCookieJarCleaner = clearChaoxingCookieJar;
  }

  Finder key(String id) => find.byKey(ValueKey<String>(id));
  Finder cardOf(ChaoxingTask t) => key(ChaoxingKeys.card(t.key));
  Finder detailOf(ChaoxingTask t) => key(ChaoxingKeys.actDetail(t.key));
  Finder hideOf(ChaoxingTask t) => key(ChaoxingKeys.actHide(t.key));

  /// 从右往左滑一张卡片（揭示右侧两个按钮）。
  Future<void> swipeLeft(WidgetTester tester, ChaoxingTask t,
      {double dx = -200}) async {
    await tester.drag(cardOf(t), Offset(dx, 0));
    await tester.pumpAndSettle();
  }

  /// 点一下并等真实异步落地（弹层/对话框回调跑在路由 pop 的续体里）。
  Future<void> tapIo(WidgetTester tester, Finder target) async {
    await tester.runAsync(() async {
      await tester.tap(target);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();
    });
    await tester.pumpAndSettle();
  }
}
