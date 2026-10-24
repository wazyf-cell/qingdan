// ignore_for_file: prefer_initializing_formals — 命名参数不能以 _ 开头
/// 学习通待办模型：会话存取 + 拉取 + 工具栏偏好（开关/排序/页签/隐藏标记）。
///
/// **刻意不落本地库、不参与同步**（2026-10-17 定案）：这些条目是外部只读快照，
/// 写进 `tasks` 会让用户的删除/完成动作跨设备同步到一台「没登录学习通」的设备上，
/// 而抓取失败也不该污染对端。所以每次进面板现拉，头部带「什么时候刷的」。
/// 完成状态以作业页服务端原文为准（未提交/已完成），本地只记「隐藏」便签。
///
/// 2026-10-23 起分三段落地（作业 → 考试 → 按需的活动），见 [refresh]。
///
/// Cookie 只进系统凭据库（与云盘密码同一铁律），键 `chaoxing.cookie`。
library;

import 'package:flutter/foundation.dart';

import 'package:qingdan/sync/secure_store.dart';
import 'package:qingdan/import/chaoxing/chaoxing_client.dart';
import 'package:qingdan/import/chaoxing/chaoxing_work_detail.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';

import 'chaoxing_counts.dart';
import 'chaoxing_grouping.dart';
import 'chaoxing_hidden_entry.dart';
import 'chaoxing_prefs.dart';

// 会话生命周期与工具栏/隐藏项写操作各自成 part：同一个库才能碰私有字段，
// 而 300 行上限只按单份文件算。
part 'chaoxing_model_session.dart';
part 'chaoxing_model_settings.dart';

class ChaoxingModel extends ChangeNotifier {
  ChaoxingModel({
    required SecureStore secure,
    ChaoxingPrefs? prefs,
    DateTime Function()? clock,
    ChaoxingClient Function(String cookie)? clientFactory,
  })  : _secure = secure,
        _prefs = prefs ?? ChaoxingPrefs(),
        _clock = clock ?? DateTime.now,
        _clientFactory = clientFactory ?? _defaultClientFactory,
        now = (clock ?? DateTime.now)();

  /// 测试注入点：真机走 `ChaoxingClient`（dart:io HttpClient），widget 测试
  /// 里必须换成假实现，否则刷新会真的打网络。
  static ChaoxingClient _defaultClientFactory(String cookie) =>
      ChaoxingClient(cookie: cookie);

  static const String kCookieKey = 'chaoxing.cookie';

  /// 超过这个时长，头部的时间后面追加「建议刷新」。
  static const Duration kStaleAfter = Duration(minutes: 15);

  final SecureStore _secure;
  final ChaoxingPrefs _prefs;
  final DateTime Function() _clock;
  final ChaoxingClient Function(String cookie) _clientFactory;

  bool loading = false;
  bool loggedIn = false;

  /// 本次刷新/拉活动失败的原因；成功后清空。**旧数据与 [fetchedAt] 都不动**——
  /// 失败时把列表清空会让「连不上」长得跟「今天没作业」一模一样（2026-10-23）。
  Object? error;
  DateTime? errorAt;

  /// 拉回来的全部条目（作业 + 考试 + 活动，含已结束/已完成）；筛选在视图层做。
  List<ChaoxingTask> tasks = const <ChaoxingTask>[];
  DateTime? fetchedAt;

  /// 三段分开存：渐进渲染时它们先后到齐，合并只发生在 [_publish] 一处。
  List<ChaoxingTask> _homework = const <ChaoxingTask>[];
  List<ChaoxingTask> _exams = const <ChaoxingTask>[];
  List<ChaoxingTask> _activities = const <ChaoxingTask>[];
  List<ChaoxingCourse> _courses = const <ChaoxingCourse>[];

  /// 课堂活动按需拉：切到该页签才发那批请求（54 个班 = 11 批，原本占 3 秒）。
  bool activitiesLoading = false;
  bool activitiesLoaded = false;

  /// 跨刷新复用同一个客户端，keep-alive 才用得上；换 cookie 才重建。
  ChaoxingClient? _client;
  String? _clientCookie;

  /// 拉到过多少门课 / 多少条。空列表时分得清「会话没通」与「确实没待办」。
  int courseCount = 0;
  int activityCount = 0;

  ChaoxingViewSettings settings = const ChaoxingViewSettings();

  /// 隐藏项的展示元数据（隐藏列表页靠它渲染，M6B §B6）。
  List<ChaoxingHiddenEntry> hiddenEntries = const <ChaoxingHiddenEntry>[];

  /// 会话失效标记：面板看到它就自动弹一次 WebView 登录，不用用户点。
  bool pendingRelogin = false;

  /// 倒计时的时间基准。面板每分钟 [tick] 一次推进，否则「剩23小时49分」会停住。
  DateTime now;

  /// C4 §2 钩子：[refresh] 成功后落一份「学习通提醒快照」。筛选与序列化全在装配根
  /// （`main.dart`）给的回调里；未注入时空操作。
  Future<void> Function(
      List<ChaoxingTask> tasks, Set<String> hidden, DateTime now)? onReminderSnapshot;

  /// **进程内**是否已经自动刷过（M6B §B7：刷新收敛到两处）。刻意不落 prefs：
  /// 杀掉应用重开就该再自动刷一次。
  bool _autoRefreshedSinceLaunch = false;
  bool get autoRefreshedThisLaunch => _autoRefreshedSinceLaunch;

  bool get stale =>
      fetchedAt != null && now.difference(fetchedAt!) > kStaleAfter;

  /// 头部那一句：刷新中 / 未刷新 / `22:20 更新`（跨天带日期）/ 过期后缀。
  /// 本体在 `chaoxing_counts.dart`，这边只转发。
  String get fetchedAtLabel => fetchedLabel(
      fetchedAt: fetchedAt, now: now, loading: loading, stale: stale);

  /// 本次失败的短文案（`null` = 没有失败）。本体同上。
  String? get errorText => refreshErrorText(error);

  /// 头部实际渲染的那一句。失败时用红字，并把「上次成功」的时间缀上——
  /// 否则「刷新失败」看不出你正看着的是几分钟前还是昨天下午的数据。
  String get statusText {
    final String? cause = refreshErrorText(error);
    if (cause == null) return fetchedAtLabel;
    final DateTime? at = fetchedAt;
    return at == null ? '刷新失败：$cause' : '刷新失败：$cause · ${hhmm(at)}';
  }

  /// 放不下完整句时用的短版：只留时间（没有时间就留状态）。
  String get statusTextCompact => compactLabel(
      fetchedAt: fetchedAt, loading: loading, hasError: statusIsError);

  bool get statusIsError => error != null;

  /// 待办总条数（底部页签角标，M5 定案第 10 条）。没有截止时间的待办也数进来。
  int get todoCount => _countTodos();

  /// 24 小时内到期的待办条数（「今天」页顶部提示条，M5 定案第 7 条）。
  int get dueSoonCount => _countTodos(within: const Duration(hours: 24));

  int _countTodos({Duration? within}) => countTodos(
        tasks: tasks,
        hidden: settings.hidden,
        now: now,
        fetched: fetchedAt != null,
        within: within,
      );

  /// 每次进程只有一次自动刷新机会（M6B §B7）：进面板时若距上次拉取不足
  /// [kStaleAfter] 就跳过，但**这次机会照样用掉**，否则每次切页签都要重新判断、
  /// 用户看到的却是同一个「N 分钟前」。
  Future<void> autoRefreshOnce() async {
    if (!loggedIn || loading || _autoRefreshedSinceLaunch) return;
    _autoRefreshedSinceLaunch = true;
    final DateTime? at = fetchedAt;
    if (at != null && _clock().difference(at) <= kStaleAfter) return;
    await refresh();
  }

  Future<void> refresh() async {
    _autoRefreshedSinceLaunch = true; // 手动点也占用这次机会
    final String? cookie = await _secure.read(kCookieKey);
    if (cookie == null) {
      loggedIn = false;
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final ChaoxingEager eager = await _clientFor(cookie).fetchEager(
        // 作业一到就先上屏，考试随后补——这是用户点名的优先级。
        onHomework: (ChaoxingEager w) {
          _homework = w.homework;
          _courses = w.courses;
          courseCount = w.courses.length;
          _publish();
        },
      );
      _homework = eager.homework;
      _exams = eager.exams;
      _courses = eager.courses;
      // 新一次刷新后活动要重新按需拉（旧的活动属于上一次快照）。
      _activities = const <ChaoxingTask>[];
      activitiesLoaded = false;
      courseCount = eager.courses.length;
      // 时间只在**整次刷新都齐了**之后写（D1）：作业到了就写会骗考试那一栏。
      fetchedAt = _clock();
      now = _clock();
      loggedIn = true;
      _publish();
      await _syncHiddenMeta();
      await _writeReminderSnapshot();
    } catch (e) {
      // 保留旧列表与旧时间戳：失败要看得见，但不能伪装成「没有待办」。
      error = e;
      errorAt = _clock();
      if (e is ChaoxingAuthException) {
        loggedIn = false;
        pendingRelogin = true;
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// 切到「课堂活动」页签时调一次；已拉过或正在拉就什么都不做。
  Future<void> ensureActivitiesLoaded() async {
    if (!loggedIn || loading || activitiesLoaded || activitiesLoading) return;
    final String? cookie = await _secure.read(kCookieKey);
    if (cookie == null) {
      loggedIn = false;
      notifyListeners();
      return;
    }
    activitiesLoading = true;
    notifyListeners();
    try {
      _activities = await _clientFor(cookie).fetchActivities(_courses);
      activitiesLoaded = true;
      error = null;
      _publish();
    } catch (e) {
      error = e;
      errorAt = _clock();
      if (e is ChaoxingAuthException) {
        loggedIn = false;
        pendingRelogin = true;
      }
    } finally {
      activitiesLoading = false;
      notifyListeners();
    }
  }

  ChaoxingClient _clientFor(String cookie) {
    if (_client == null || _clientCookie != cookie) {
      _client?.close();
      _client = _clientFactory(cookie);
      _clientCookie = cookie;
    }
    return _client!;
  }

  /// 供 part 里的扩展用：`notifyListeners` 是 protected 成员，扩展里调不了。
  void _changed() => notifyListeners();

  /// 三段合并成对外的 [tasks]。顺序沿用「作业 → 考试 → 活动」：作业是
  /// 「我现在要做什么」的真源，其余是补充（与脚本 :1509 的顺序一致）。
  void _publish() {
    tasks = ChaoxingTask.mergeRepublished(ChaoxingTask.dedupe(<ChaoxingTask>[
      ..._homework,
      ..._exams,
      ..._activities,
    ]));
    activityCount = tasks.length;
    notifyListeners();
  }

  /// 测试专用：把一批条目当作「作业」段灌进去。
  ///
  /// [tasks] 是派生视图，任何写入都必须经过 [_publish]，否则下一次按需拉活动
  /// 会用它自己那三份（空的）分段把直接赋值的列表覆盖成空表——面板测试就是
  /// 这么红过一次的。生产代码没有调用点。
  @visibleForTesting
  void seedTasksForTest(List<ChaoxingTask> seeded) {
    _homework = seeded;
    _publish();
  }

  /// 点开详情才取正文：**每次现取，不缓存**。正文只在人想看的时候有用，缓存
  /// 会让「老师改了题目」看不见，而这条链路只有两个请求。
  /// 返回 null = 这一条抽不出正文（非作业、已提交、已过时效），界面退回真实网页。
  Future<ChaoxingWorkDetail?> loadWorkDetail(ChaoxingTask task) async {
    final String? entry = task.detailEntryUrl;
    if (entry == null) return null;
    final String? cookie = await _secure.read(kCookieKey);
    if (cookie == null) {
      loggedIn = false;
      return null;
    }
    // 复用同一个客户端：详情是一次点两跳，复用能省一次握手。
    return _clientFor(cookie).fetchWorkDetail(entry);
  }

  /// C4 §2 写入点。异常吞这里而不是 [refresh] 的 catch：写盘失败不该把成功抓取说成失败。
  Future<void> _writeReminderSnapshot() async {
    try {
      await onReminderSnapshot?.call(tasks, settings.hidden, _clock());
    } catch (e) {
      debugPrint('学习通提醒快照写入失败：${e.runtimeType}');
    }
  }

  /// 刷新后跟着更新隐藏项：还存在的把标题/截止同步成最新值（截止可能被老师改），
  /// 不再出现的标 `dead`（**不删**，让隐藏列表页给用户自己决定）。
  /// 对齐本体在 `syncHiddenMetaWithTasks`（隐藏项元数据那一域，纯函数可单测）。
  Future<void> _syncHiddenMeta() async {
    await _saveHiddenMeta(syncHiddenMetaWithTasks(hiddenEntries, tasks));
  }
}

