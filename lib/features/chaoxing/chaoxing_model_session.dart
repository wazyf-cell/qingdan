part of 'chaoxing_model.dart';

/// 会话生命周期：读偏好 / 存 cookie / 退出登录。
///
/// 拆成 part 而不是独立类：这些动作改的全是 [ChaoxingModel] 的私有状态
/// （`_secure` / `_prefs` / `_client`），独立类只会换来一堆 getter/setter。
extension ChaoxingModelSession on ChaoxingModel {
  /// 启动时读一次凭据库与本地偏好：有 cookie 就认为已登录（真伪由第一次拉取校验）。
  Future<void> restore() async {
    // 注意不能 `.toString().isNotEmpty`：null.toString() 得到字面量 "null"
    // （7 个字符），会让未登录被误判成已登录——真机第一轮就是这么露出来的。
    loggedIn = await _secure.read(ChaoxingModel.kCookieKey) != null;
    settings = await _prefs.load();
    hiddenEntries = await _prefs.loadHiddenMeta();
    now = _clock();
    _changed();
  }

  Future<void> saveCookie(String cookie) async {
    await _secure.write(ChaoxingModel.kCookieKey, cookie);
    loggedIn = true;
    error = null;
    pendingRelogin = false;
    _changed();
    await refresh();
  }

  /// 面板取走一次「该重新登录了」的信号（只弹一次，用户关掉后不再纠缠）。
  void consumeReloginRequest() {
    if (!pendingRelogin) return;
    pendingRelogin = false;
    _changed();
  }

  /// 退出登录：删凭据 + 清内存态。`clearHiddenList` 由确认框的第二个按钮决定
  /// （M6B §B4 三按钮：保留隐藏列表 / 清空 / 取消）。
  ///
  /// WebView cookie jar 的清理不在这里（模型不引 flutter_inappwebview，
  /// 纯 Dart 测试里也起不了平台通道），由 `chaoxing_actions.dart` 调
  /// `clearChaoxingCookieJar` 完成；已排通知的取消走 `chaoxing_notify_hook.dart`。
  Future<void> logout({bool clearHiddenList = false}) async {
    await _secure.delete(ChaoxingModel.kCookieKey);
    _client?.close();
    _client = null;
    _clientCookie = null;
    loggedIn = false;
    tasks = const <ChaoxingTask>[];
    _homework = _exams = _activities = const <ChaoxingTask>[];
    _courses = const <ChaoxingCourse>[];
    fetchedAt = null;
    error = null;
    errorAt = null;
    activitiesLoaded = false;
    pendingRelogin = false;
    if (clearHiddenList) {
      settings = settings.copyWith(hidden: const <String>{});
      hiddenEntries = const <ChaoxingHiddenEntry>[];
      await _prefs.clearHiddenList();
    }
    _changed();
  }
}
