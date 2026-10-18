// ignore_for_file: prefer_initializing_formals — 命名参数不能以 _ 开头
/// 学习通待办模型：会话存取 + 拉取 + 工具栏偏好（开关/排序/页签/隐藏标记）。
///
/// **刻意不落本地库、不参与同步**（2026-10-17 定案）：这些条目是外部只读快照，
/// 写进 `tasks` 会让用户的删除/完成动作跨设备同步到一台「没登录学习通」的设备上，
/// 而抓取失败也不该污染对端。所以每次进面板现拉，头部带「N 分钟前」。
/// 完成状态以作业页服务端原文为准（未提交/已完成），本地只记「隐藏」便签。
///
/// Cookie 只进系统凭据库（与云盘密码同一铁律），键 `chaoxing.cookie`。
library;

import 'package:flutter/foundation.dart';

import 'package:qingdan/sync/secure_store.dart';
import 'package:qingdan/import/chaoxing/chaoxing_client.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';

import 'chaoxing_grouping.dart';
import 'chaoxing_hidden_entry.dart';
import 'chaoxing_prefs.dart';

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

  /// 超过这个时长，头部的「N 分钟前」后面追加「建议刷新」。
  static const Duration kStaleAfter = Duration(minutes: 15);

  final SecureStore _secure;
  final ChaoxingPrefs _prefs;
  final DateTime Function() _clock;
  final ChaoxingClient Function(String cookie) _clientFactory;

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

  /// 隐藏项的展示元数据（隐藏列表页靠它渲染，M6B §B6）。
  List<ChaoxingHiddenEntry> hiddenEntries = const <ChaoxingHiddenEntry>[];

  /// 会话失效标记：面板看到它就自动弹一次 WebView 登录，不用用户点。
  bool pendingRelogin = false;

  /// 倒计时的时间基准。面板每分钟 [tick] 一次推进，否则「剩23小时49分」会停住。
  DateTime now;

  /// **进程内**是否已经自动刷过（M6B §B7：刷新收敛到两处）。刻意不落 prefs：
  /// 杀掉应用重开就该再自动刷一次。
  bool _autoRefreshedSinceLaunch = false;
  bool get autoRefreshedThisLaunch => _autoRefreshedSinceLaunch;

  bool get stale =>
      fetchedAt != null && now.difference(fetchedAt!) > kStaleAfter;

  /// 「数据 · N 分钟前」文案；未抓取过时说「未刷新」。
  String get fetchedAgoText {
    final DateTime? at = fetchedAt;
    if (at == null) return '未刷新';
    final int m = now.difference(at).inMinutes;
    final String base = m < 1 ? '刚刚' : '$m 分钟前';
    return stale ? '$base · 建议刷新' : base;
  }

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
    hiddenEntries = await _prefs.loadHiddenMeta();
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

  /// 退出登录：删凭据 + 清内存态。`clearHiddenList` 由确认框的第二个按钮决定
  /// （M6B §B4 三按钮：保留隐藏列表 / 清空 / 取消）。
  ///
  /// WebView cookie jar 的清理不在这里（模型不引 flutter_inappwebview，
  /// 纯 Dart 测试里也起不了平台通道），由 `chaoxing_actions.dart` 调
  /// [clearChaoxingCookieJar] 完成；已排通知的取消走 `chaoxing_notify_hook.dart`。
  Future<void> logout({bool clearHiddenList = false}) async {
    await _secure.delete(kCookieKey);
    loggedIn = false;
    tasks = const <ChaoxingTask>[];
    fetchedAt = null;
    error = null;
    pendingRelogin = false;
    if (clearHiddenList) {
      settings = settings.copyWith(hidden: const <String>{});
      hiddenEntries = const <ChaoxingHiddenEntry>[];
      await _prefs.clearHiddenList();
    }
    notifyListeners();
  }

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
    final ChaoxingClient client = _clientFactory(cookie);
    try {
      tasks = await client.fetchAllTasks();
      courseCount = client.courseCount;
      activityCount = tasks.length;
      fetchedAt = _clock();
      now = _clock();
      loggedIn = true;
      await _syncHiddenMeta();
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

  /// 刷新后跟着更新隐藏项：还存在的把标题/截止同步成最新值（截止可能被老师改），
  /// 不再出现的标 `dead`（**不删**，让隐藏列表页给用户自己决定）。
  /// 对齐本体在 `syncHiddenMetaWithTasks`（隐藏项元数据那一域，纯函数可单测）。
  Future<void> _syncHiddenMeta() async {
    await _saveHiddenMeta(syncHiddenMetaWithTasks(hiddenEntries, tasks));
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

  /// 筛选弹层的「重置」：只清筛选，页签与隐藏集是两回事，不能顺手抹掉。
  Future<void> resetFilters() => _mutate(ChaoxingViewSettings(
        hidden: settings.hidden,
        tab: settings.tab,
      ));

  /// 隐藏一条：key 进隐藏集，展示元数据进 `chaoxing.hidden.meta`。
  Future<void> hide(ChaoxingTask t) async {
    await _mutate(
        settings.copyWith(hidden: Set<String>.of(settings.hidden)..add(t.key)));
    final List<ChaoxingHiddenEntry> next = List<ChaoxingHiddenEntry>.of(
            hiddenEntries.where((ChaoxingHiddenEntry e) => e.key != t.key))
          ..add(ChaoxingHiddenEntry.of(t, now));
    await _saveHiddenMeta(next);
  }

  /// 恢复单条（隐藏列表页的「恢复」）。
  Future<void> unhide(String key) async {
    await _mutate(settings.copyWith(
        hidden: Set<String>.of(settings.hidden)..remove(key)));
    await _saveHiddenMeta(List<ChaoxingHiddenEntry>.of(hiddenEntries)
      ..removeWhere((ChaoxingHiddenEntry e) => e.key == key));
  }

  Future<void> unhideAll() async {
    await _mutate(settings.copyWith(hidden: const <String>{}));
    await _saveHiddenMeta(const <ChaoxingHiddenEntry>[]);
  }

  /// 清掉「本次刷新里已经不再出现」的隐藏项（隐藏列表页的「清理已失效」）。
  /// 隐藏键也一并删掉：条目本身都没了，留着键只会挡住将来同 id 的新待办。
  Future<void> purgeDead() async {
    final List<String> deadKeys = hiddenEntries
        .where((ChaoxingHiddenEntry e) => e.dead)
        .map((ChaoxingHiddenEntry e) => e.key)
        .toList();
    if (deadKeys.isEmpty) return;
    await _mutate(settings.copyWith(
        hidden: Set<String>.of(settings.hidden)..removeAll(deadKeys)));
    await _saveHiddenMeta(List<ChaoxingHiddenEntry>.of(hiddenEntries)
      ..removeWhere((ChaoxingHiddenEntry e) => e.dead));
  }

  Future<void> _saveHiddenMeta(List<ChaoxingHiddenEntry> next) async {
    hiddenEntries = next;
    notifyListeners();
    await _prefs.saveHiddenMeta(next);
  }

  Future<void> _mutate(ChaoxingViewSettings next) async {
    settings = next;
    notifyListeners();
    await _prefs.save(next);
  }
}
