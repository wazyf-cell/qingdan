// ignore_for_file: prefer_initializing_formals — 命名参数不能以 _ 开头
import 'package:shared_preferences/shared_preferences.dart';

import 'update_checker.dart';

/// GitHub Releases 的 HTTP 缓存：ETag + 上次响应体。
///
/// 为什么值得存：GitHub 对匿名请求按 IP 限 60 次/小时，而条件请求返回 304
/// **不计入额度**。每次冷启动都查一次更新时，只要发布页没变，后续检查几乎免费，
/// 不再把共享网络的额度耗光。
class UpdateHttpCache {
  UpdateHttpCache({SharedPreferences? prefs, this.repoSlug = kRepoSlug})
      : _prefs = prefs;

  final SharedPreferences? _prefs;
  final String repoSlug;

  String get _etagKey => 'update.http.$repoSlug.etag';
  String get _bodyKey => 'update.http.$repoSlug.body';

  Future<({String etag, String body})?> read() async {
    try {
      final SharedPreferences p = _prefs ?? await SharedPreferences.getInstance();
      final String? etag = p.getString(_etagKey);
      final String? body = p.getString(_bodyKey);
      if (etag == null || etag.isEmpty || body == null || body.isEmpty) {
        return null;
      }
      return (etag: etag, body: body);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String etag, String body) async {
    try {
      final SharedPreferences p = _prefs ?? await SharedPreferences.getInstance();
      await p.setString(_etagKey, etag);
      await p.setString(_bodyKey, body);
    } catch (_) {
      // 缓存写失败只影响下一次是否省额度，不影响本次结果。
    }
  }
}
