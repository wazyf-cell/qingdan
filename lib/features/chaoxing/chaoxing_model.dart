// ignore_for_file: prefer_initializing_formals — 命名参数不能以 _ 开头
/// 学习通待办模型：会话存取 + 拉取 + 工具栏偏好（开关/排序/页签/隐藏标记）。
///
/// **刻意不落本地库、不参与同步**（2026-10-17 定案）：这些条目是外部只读快照，
/// 写进 `tasks` 会让用户的删除/完成动作跨设备同步到一台「没登录学习通」的设备上，
/// 而抓取失败也不该污染对端。所以每次进面板现拉，工具栏带「数据 · N 分钟前」。
/// 完成状态以作业页服务端原文为准（未提交/已完成），本地只记「隐藏」便签。
///
/// Cookie 只进系统凭据库（与云盘密码同一铁律），键 `chaoxing.cookie`。
library;

import 'package:flutter/foundation.dart';

import 'package:qingdan/sync/secure_store.dart';
import 'package:qingdan/import/chaoxing/chaoxing_client.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';

import 'chaoxing_grouping.dart';
import 'chaoxing_prefs.dart';

class ChaoxingModel extends ChangeNotifier {
  ChaoxingModel({
    required SecureStore secure,
    ChaoxingPrefs? prefs,
    DateTime Function()? clock,
  })  : _secure = secure,
        _prefs = prefs ?? ChaoxingPrefs(),
        _clock = clock ?? DateTime.now,
        now = (clock ?? DateTime.now)();

  static const String kCookieKey = 'chaoxing.cookie';

  /// 超过这个时长，工具栏的「数据 · N 分钟前」后面追加「建议刷新」。
  static const Duration kStaleAfter = Duration(minutes: 15);

  final SecureStore _secure;
  final ChaoxingPrefs _prefs;
  final DateTime Function() _clock;

  bool loading = false;
  bool loggedIn = false;
  Object? error;

  /// 拉回来的全部条目（作业 + 活动，含已结束/已完成）；筛选在视图层做。
  List<ChaoxingTask> tasks = const <ChaoxingTask>[];
  DateTime? fetchedAt;

  /// 拉到过多少门课 / 多少条。空列表时分得清「会话没通」与「确实没待办」。
  int courseCount = 0;
  int activityCount = 0;

  ChaoxingViewSettings settings = const ChaoxingViewSettings();

  /// 会话失效标记：面板看到它就自动弹一次 WebView 登录，不用用户点。
  bool pendingRelogin = false;

  /// 倒计时的时间基准。面板每分钟 [tick] 一次推进，否则「剩23小时49分」会停住。
  DateTime now;

  bool get stale =>
      fetchedAt != null && now.difference(fetchedAt!) > kStaleAfter;

  /// 待办总条数（底部页签角标，M5 定案第 10 条）。没有截止时间的待办也数进来。
  int get todoCount => _countTodos();

  /// 24 小时内到期的待办条数（「今天」页顶部提示条，M5 定案第 7 条）。
  int get dueSoonCount => _countTodos(within: const Duration(hours: 24));

  /// 只数「状态仍为待办且未被隐藏」的条目；**没拉取过返回 0**——这个数据刻意
  /// 不落库、不后台刷，所以提示条与角标都停在上次拉取（定案风险第 4 条已接受）。
  int _countTodos({Duration? within}) {
    if (fetchedAt == null) return 0;
    int n = 0;
    for (final ChaoxingTask t in tasks) {
      if (settings.hidden.contains(t.key)) continue;
      if (t.stateAt(now, done: false) != ChaoxingTaskState.todo) continue;
      if (within != null) {
        final DateTime? due = t.dueAt;
        if (due == null) continue;
        final Duration left = due.difference(now);
        if (left.isNegative || left > within) continue;
      }
      n++;
    }
    return n;
  }

  /// 启动时读一次凭据库与本地偏好：有 cookie 就认为已登录（真伪由第一次拉取校验）。
  Future<void> restore() async {
    // 注意不能 `.toString().isNotEmpty`：null.toString() 得到字面量 "null"
    // （7 个字符），会让未登录被误判成已登录——真机第一轮就是这么露出来的。
    loggedIn = await _secure.read(kCookieKey) != null;
    settings = await _prefs.load();
    now = _clock();
    notifyListeners();
  }

  Future<void> saveCookie(String cookie) async {
    await _secure.write(kCookieKey, cookie);
    loggedIn = true;
    error = null;
    pendingRelogin = false;
    notifyListeners();
    await refresh();
  }

  /// 面板取走一次「该重新登录了」的信号（只弹一次，用户关掉后不再纠缠）。
  void consumeReloginRequest() {
    if (!pendingRelogin) return;
    pendingRelogin = false;
    notifyListeners();
  }

  Future<void> logout() async {
    await _secure.delete(kCookieKey);
    loggedIn = false;
    tasks = const <ChaoxingTask>[];
    notifyListeners();
  }

  Future<void> refresh() async {
    final String? cookie = await _secure.read(kCookieKey);
    if (cookie == null) {
      loggedIn = false;
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    final ChaoxingClient client = ChaoxingClient(cookie: cookie);
    try {
      tasks = await client.fetchAllTasks();
      courseCount = client.courseCount;
      activityCount = tasks.length;
      fetchedAt = DateTime.now();
      now = _clock();
      loggedIn = true;
    } catch (e) {
      error = e;
      if (e is ChaoxingAuthException) {
        loggedIn = false;
        pendingRelogin = true;
      }
    } finally {
      loading = false;
      client.close();
      notifyListeners();
    }
  }

  void tick() {
    now = _clock();
    notifyListeners();
  }

  // ---- 工具栏开关：改完立刻落盘，不等退出 ----

  Future<void> toggleOnlyUnfinished() =>
      _mutate(settings.copyWith(onlyUnfinished: !settings.onlyUnfinished));

  Future<void> toggleOnlySubmittable() =>
      _mutate(settings.copyWith(onlySubmittable: !settings.onlySubmittable));

  Future<void> setSortBy(ChaoxingSortBy s) =>
      _mutate(settings.copyWith(sortBy: s));

  Future<void> setTab(ChaoxingTab t) => _mutate(settings.copyWith(tab: t));

  Future<void> hide(String key) => _mutate(
      settings.copyWith(hidden: Set<String>.of(settings.hidden)..add(key)));

  Future<void> unhideAll() =>
      _mutate(settings.copyWith(hidden: const <String>{}));

  Future<void> _mutate(ChaoxingViewSettings next) async {
    settings = next;
    notifyListeners();
    await _prefs.save(next);
  }
}
