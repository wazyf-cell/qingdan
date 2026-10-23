/// 更新通道：向 GitHub Releases 查一次「有没有新版本」。
///
/// 为什么只查不装：本项目没有服务端（需求定死），能借的公开渠道只有 GitHub 的
/// 发布页；而 Android 覆盖安装要求签名一致、换签名又必须卸载（卸载会清空
/// `files/qingdan.db`，任务课表全在里面）。所以「点一下就自己升级」在这台设备
/// 上做不到诚实，界面只承诺它能做到的事：告诉你有没有新版，把你送到发布页。
///
/// 用的是 `/releases/latest`，GitHub 自己保证它**不含草稿与预发布**，
/// 所以 CI 彩排跑出来的那种非正式包不会被当成新版本推给用户。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 仓库地址：换仓库时只有这一处要改，测试与界面都从这里取。
const String kRepoSlug = 'wazyf-cell/qingdan';
const String kRepoUrl = 'https://github.com/$kRepoSlug';

class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.url,
    this.tagName = '',
    this.publishedAt,
    this.assetNames = const <String>[],
    this.notes,
  });

  /// 规范化后的版本号（去掉前缀 `v` 与 `+build`）。
  final String version;
  final String url;
  final String tagName;
  final DateTime? publishedAt;
  final List<String> assetNames;

  /// 发布说明原文（GitHub Release 的 `body`）。只有空白时按 null 处理：
  /// 「没写说明」与「写了一堆空格」在界面上是同一件事，调用方只想判一次空。
  final String? notes;

  /// 拿不到 `tag_name` 就返回 null，由调用方报「发布页里没有版本号」——
  /// 退化成 v0.0.0 会让界面显示「发现新版本 v0.0.0」这种自相矛盾的话。
  static ReleaseInfo? fromJson(Map<String, dynamic> json) {
    final String tag = (json['tag_name'] as String?)?.trim() ?? '';
    if (tag.isEmpty) return null;
    final Object? assets = json['assets'];
    // `body` 可能是 null（发布时没填说明）、空串，或带首尾空白的多行文本。
    final String body = (json['body'] as String?)?.trim() ?? '';
    return ReleaseInfo(
      version: normalizeVersion(tag),
      tagName: tag,
      notes: body.isEmpty ? null : body,
      url: (json['html_url'] as String?)?.trim().isNotEmpty == true
          ? (json['html_url'] as String).trim()
          : '$kRepoUrl/releases',
      publishedAt: DateTime.tryParse((json['published_at'] as String?) ?? ''),
      assetNames: assets is List
          ? assets
              .whereType<Map<String, dynamic>>()
              .map((Map<String, dynamic> a) => (a['name'] as String?) ?? '')
              .where((String n) => n.isNotEmpty)
              .toList()
          : const <String>[],
    );
  }
}

enum UpdateStatus { upToDate, available, failed }

class UpdateResult {
  const UpdateResult(this.status, this.currentVersion, {this.latest, this.error});

  final UpdateStatus status;
  final String currentVersion;
  final ReleaseInfo? latest;
  final String? error;

  /// 行内副文案与弹层标题共用这一句，避免出现两处说法对不上。
  String get summary => switch (status) {
        UpdateStatus.upToDate => '已是最新版 v$currentVersion',
        UpdateStatus.available =>
          '发现新版本 v${latest!.version}（当前 v$currentVersion）',
        UpdateStatus.failed => '检查失败：$error',
      };
}

/// 抛给用户看的失败原因（中文、可执行）；非本类的异常统一折算成「出了点意外」。
class UpdateFetchException implements Exception {
  const UpdateFetchException(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

typedef ReleaseJsonFetcher = Future<Map<String, dynamic>> Function(String url);

class UpdateChecker {
  UpdateChecker({String repoSlug = kRepoSlug, ReleaseJsonFetcher? fetch})
      : _api = 'https://api.github.com/repos/$repoSlug',
        _fetch = fetch ?? _httpFetch;

  final String _api;
  final ReleaseJsonFetcher _fetch;

  Future<UpdateResult> check(String currentVersion) async {
    try {
      final ReleaseInfo? latest =
          ReleaseInfo.fromJson(await _fetch('$_api/releases/latest'));
      if (latest == null) {
        return UpdateResult(UpdateStatus.failed, currentVersion,
            error: '发布页里没有版本号');
      }
      return compareVersions(latest.version, currentVersion) > 0
          ? UpdateResult(UpdateStatus.available, currentVersion, latest: latest)
          : UpdateResult(UpdateStatus.upToDate, currentVersion, latest: latest);
    } on UpdateFetchException catch (e) {
      return UpdateResult(UpdateStatus.failed, currentVersion, error: e.reason);
    } catch (e) {
      return UpdateResult(UpdateStatus.failed, currentVersion,
          error: '出了点意外（${e.runtimeType}）');
    }
  }
}

/// `v1.0.10` 与 `1.0.2+3` 都归一到 `1.0.10` / `1.0.2`。
String normalizeVersion(String raw) => raw
    .replaceFirst(RegExp(r'^v', caseSensitive: false), '')
    .split(RegExp(r'[-+]'))
    .first
    .trim();

/// 逐段按**数字**比。用 String.compareTo 会得到 `1.0.10 < 1.0.2`，
/// 那正好是「发布了第 10 个小版本却告诉用户没更新」的形状。
int compareVersions(String a, String b) {
  final List<int> x = _segments(a), y = _segments(b);
  final int n = x.length > y.length ? x.length : y.length;
  for (int i = 0; i < n; i++) {
    final int c = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
    if (c != 0) return c;
  }
  return 0;
}

List<int> _segments(String v) =>
    normalizeVersion(v).split('.').map((String s) => int.tryParse(s) ?? 0).toList();

Future<Map<String, dynamic>> _httpFetch(String url) async {
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);
  try {
    final HttpClientRequest req = await client.getUrl(Uri.parse(url));
    // GitHub API 没有 User-Agent 直接 403，这是它文档里写明的硬性要求。
    req.headers.set(HttpHeaders.userAgentHeader, 'qingdan-app');
    req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final HttpClientResponse res =
        await req.close().timeout(const Duration(seconds: 12));
    final String body =
        await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 12));
    if (res.statusCode != HttpStatus.ok) {
      throw UpdateFetchException(githubStatusReason(res.statusCode));
    }
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const UpdateFetchException('GitHub 返回的内容看不懂');
    }
    return decoded;
  } on TimeoutException {
    throw const UpdateFetchException('GitHub 响应超时，稍后再试');
  } on SocketException {
    throw const UpdateFetchException('连不上 GitHub（这台设备当前没有网络）');
  } on FormatException {
    throw const UpdateFetchException('GitHub 返回的内容看不懂');
  } on HttpException {
    throw const UpdateFetchException('连不上 GitHub（地址解析或握手失败）');
  } finally {
    client.close(force: true);
  }
}

/// HTTP 状态码 → 用户看得懂、且知道下一步该做什么的一句话。
///
/// 单独暴露是为了能在离线测试里逐条钉住：真实网络失败（超时 / 连不上）
/// 只有设备能验，但「GitHub 说了 403 时界面该讲什么」不该也一起靠肉眼。
String githubStatusReason(int code) => switch (code) {
      404 => 'GitHub 上找不到这个仓库的发布（可能还没发过版，或仓库改过名）',
      403 || 429 => 'GitHub 拒绝了请求（同一个网络一小时内查太多次，等一会儿再试）',
      _ => 'GitHub 返回 HTTP $code',
    };
