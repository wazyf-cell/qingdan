/// WebDAV 协议细节层，从 webdav_backend.dart 拆出。
///
/// 拆分理由：任务规矩要求单文件 ≤300 行；[WebDavBackend] 保留
/// SyncBackend 语义映射（后端接口 ↔ WebDAV 动词），本文件放「与坚果云
/// 对话」的机械细节：URL 拼接、PROPFIND 取 etag、逐级 MKCOL、etag 剥引号。
library;

import 'dart:convert';

import 'sync_backend.dart';
import 'webdav_transport.dart';
import 'webdav_xml.dart';

/// etag 统一出口：剥引号（陷阱①）。
/// 坚果云 If-Match 只接受**不带引号的裸 etag**，任何引号形式（双引号、
/// 单引号、W/ 弱验证器前缀）都返回 412，且 412 表现与真并发冲突**完全
/// 相同**，极易误诊。所以所有 etag 出口统一过这里，保证后续 If-Match
/// 永远是裸值。
String bareEtag(String etag) {
  var v = etag.trim();
  if (v.startsWith('W/') || v.startsWith('w/')) {
    v = v.substring(2);
  }
  if (v.length >= 2 &&
      ((v.startsWith('"') && v.endsWith('"')) ||
          (v.startsWith("'") && v.endsWith("'")))) {
    v = v.substring(1, v.length - 1);
  }
  return v;
}

/// 与单个 WebDAV 端点对话的客户端（HTTP 细节）。
class WebDavClient {
  WebDavClient({
    required this.baseUrl,
    required this.authHeader,
    required this.transport,
  });

  /// 形如 `https://dav.jianguoyun.com/dav/`（host 由调用方选定，支持
  /// dav/dav123 等分发变体，不写死）。
  final Uri baseUrl;
  final String authHeader;
  final WebDavTransport transport;

  /// PROPFIND allprop 请求体。陷阱④：显式列 `<d:getetag/>` 经常不返回，
  /// 必须用 allprop（或 propname）才稳定拿到 etag。
  static const String allpropBody =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:allprop/></d:propfind>';

  /// 相对 path → 绝对 URL。路径分段各自做百分号编码（非 ASCII、空格均
  /// 按 RFC 3986 编码，与坚果云 href 的编码风格一致），分隔符 `/` 不编码。
  /// `..` 逃逸直接拒绝（同步路径来自本地数据，防御性校验）。
  Uri resolveUrl(String path) {
    final segments = path
        .replaceAll('\\', '/')
        .split('/')
        .where((s) => s.isNotEmpty && s != '.')
        .toList();
    if (segments.any((s) => s == '..')) {
      throw ArgumentError('路径含 ..，WebDAV 后端不接受相对逃逸: $path');
    }
    final encoded = segments.map(Uri.encodeComponent).join('/');
    final basePath =
        baseUrl.path.endsWith('/') ? baseUrl.path : '${baseUrl.path}/';
    return baseUrl.replace(path: '$basePath$encoded');
  }

  /// href 与本地 path 的比对：坚果云 href 是百分号编码的绝对路径
  /// （如 `/dav/%e6%88%91/.../a.json`），与 resolveUrl 的编码产物做
  /// 字符串级后缀比对；不做解码，避免双重编码歧义。
  bool hrefMatches(String href, List<String> encodedSegments) {
    final suffix = '/${encodedSegments.join('/')}';
    final h = href.endsWith('/') && !suffix.endsWith('/')
        ? href.substring(0, href.length - 1)
        : href;
    return h == suffix ||
        Uri.decodeComponent(h) == Uri.decodeComponent(suffix);
  }

  /// PROPFIND 单个路径（depth 0），返回该对象的 etag 或 null
  /// （不存在 / 响应缺属性）。put/delete 拿新 etag 与冲突时探 actualEtag
  /// 都走这里。
  Future<String?> propfindEtag(String path) async {
    final encoded =
        path.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).map(
              Uri.encodeComponent,
            ).toList();
    final resp = await transport.send(
      WebDavHttpRequest(
        method: 'PROPFIND',
        url: resolveUrl(path),
        headers: {
          'Authorization': authHeader,
          'Depth': '0',
          'Content-Type': 'application/xml; charset=utf-8',
        },
        body: utf8.encode(allpropBody),
      ),
    );
    if (resp.statusCode != 207) {
      return null;
    }
    final entries = parseMultistatus(resp.bodyAsText);
    for (final e in entries) {
      if (hrefMatches(e.href, encoded)) {
        return e.etag == null ? null : bareEtag(e.etag!);
      }
    }
    // 某些实现只回集合条目自身；取不到精确匹配就退而求其次取第一条 etag。
    for (final e in entries) {
      if (e.etag != null) {
        return bareEtag(e.etag!);
      }
    }
    return null;
  }

  /// 确认 baseUrl 根目录本身存在（不存在则创建）。
  ///
  /// 为什么必须有这步：[ensureParentDirs] 只按 path 的相对段逐级建目录，
  /// 永远够不着 baseUrl 自身的最后一段（如 `.../dav/qingdan/` 的
  /// `qingdan/`）。而坚果云对不存在目录下的所有操作返回 409——用户配错
  /// 路径时，症状会是「第一次同步全线 409」，而不是「地址不对」。
  ///
  /// 根一旦在此确认存在，WebDavBackend.list() 的 404 就只剩「namespace
  /// 未建」一种语义（消灭 404 二义性，见 webdav_backend.dart）。
  ///
  /// 路径完全配错（复检 MKCOL 后仍 404）或凭据错误（401/403）时抛
  /// [SyncConfigException]：fail-fast，文案直接给用户看。
  Future<void> ensureRoot() async {
    // Depth:0 只探根自身。请求 URL 就是 baseUrl（resolveUrl('') 下
    // segments 为空，结果 = baseUrl 补齐尾斜杠）。
    final resp = await transport.send(
      WebDavHttpRequest(
        method: 'PROPFIND',
        url: resolveUrl(''),
        headers: {
          'Authorization': authHeader,
          'Depth': '0',
          'Content-Type': 'application/xml; charset=utf-8',
        },
        body: utf8.encode(allpropBody),
      ),
    );
    if (resp.statusCode == 207) {
      return;
    }
    if (resp.statusCode == 404) {
      // 根的最后一段不存在 → MKCOL 建它，再复检一次确认真建上了
      // （MKCOL 的 2xx 只说明服务器受理，复检才是最终事实）。
      await _mkcolRoot();
      final recheck = await transport.send(
        WebDavHttpRequest(
          method: 'PROPFIND',
          url: resolveUrl(''),
          headers: {
            'Authorization': authHeader,
            'Depth': '0',
            'Content-Type': 'application/xml; charset=utf-8',
          },
          body: utf8.encode(allpropBody),
        ),
      );
      if (recheck.statusCode == 207) {
        return;
      }
      // 仍 404：父级（如 /dav/ 下的 qingdan 一层）也不让建，典型是地址
      // 少写了最后一段或指向了只读位置。此时后续 list() 的 404 无法与
      // 「namespace 未建」区分，必须在这里把话说死。
      throw SyncConfigException(
        baseUrl: baseUrl.toString(),
        statusCode: recheck.statusCode,
        hint: '云盘上不存在也无法创建这个目录。请把同步地址指向一个可创建'
            '的子目录，例如 https://dav.jianguoyun.com/dav/qingdan/ ，'
            '并确认其上级目录存在。',
      );
    }
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      // 401/403 在建目录之前出现，几乎必然是凭据问题——同样 fail-fast，
      // 不把「凭据错」伪装成后续的 409/412。
      throw SyncConfigException(
        baseUrl: baseUrl.toString(),
        statusCode: resp.statusCode,
        hint: '认证失败：请核对账号与坚果云「应用密码」'
            '（不是登录密码），并确认账号未开启两步验证限制。',
      );
    }
    // 其他状态码（5xx、非常规 4xx 等）：如实上报原文，不猜原因。
    throw SyncConfigException(
      baseUrl: baseUrl.toString(),
      statusCode: resp.statusCode,
      hint: '根目录探测返回非预期状态，请检查同步地址与服务可用性。',
    );
  }

  /// MKCOL baseUrl 尾段目录。坚果云 MKCOL 成功无 body；405 = 已存在
  /// （与 ensureParentDirs 的约定一致，放行交给复检判定）。
  Future<void> _mkcolRoot() async {
    final resp = await transport.send(
      WebDavHttpRequest(
        method: 'MKCOL',
        url: resolveUrl(''),
        headers: {'Authorization': authHeader},
      ),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw SyncConfigException(
        baseUrl: baseUrl.toString(),
        statusCode: resp.statusCode,
        hint: '无法在云盘上创建同步根目录（MKCOL 被拒）。请把同步地址指向'
            '一个可创建的子目录，并确认账号有写权限。',
      );
    }
  }

  /// 逐级 MKCOL 预创建父目录（陷阱⑤：坚果云 PUT 进不存在目录返回 404，
  /// 且根目录不允许放文件）。
  Future<void> ensureParentDirs(String path) async {
    final segments =
        path.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty)
            .toList();
    if (segments.length <= 1) {
      return; // 没有父目录可建（根目录本就不允许放文件）
    }
    // 坚果云根 /dav/ 本身已存在；先从最深处向上找到第一个已存在的层级，
    // 避免对已存在目录发 MKCOL（405 无害但浪费请求配额）。
    var current = segments.sublist(0, segments.length - 1);
    while (current.isNotEmpty) {
      final probe = await transport.send(
        WebDavHttpRequest(
          method: 'PROPFIND',
          url: resolveUrl(current.join('/')),
          headers: {
            'Authorization': authHeader,
            'Depth': '0',
            'Content-Type': 'application/xml; charset=utf-8',
          },
          body: utf8.encode(allpropBody),
        ),
      );
      if (probe.statusCode == 207) {
        break;
      }
      if (probe.statusCode == 404) {
        current = current.sublist(0, current.length - 1);
        continue;
      }
      // 401/403 等：让后续 PUT 暴露真实错误，这里不吞。
      break;
    }
    // 从第一个不存在的层级向下逐级 MKCOL。
    for (int i = current.length; i < segments.length - 1; i++) {
      final dirPath = segments.sublist(0, i + 1).join('/');
      final resp = await transport.send(
        WebDavHttpRequest(
          method: 'MKCOL',
          url: resolveUrl(dirPath),
          headers: {'Authorization': authHeader},
        ),
      );
      // 201 创建成功；405 已存在（并发下可能出现）都放行。
      if (resp.statusCode != 201 && resp.statusCode != 405) {
        throw StateError(
          'MKCOL 失败（$dirPath）: HTTP ${resp.statusCode} '
          '${resp.bodyAsText}',
        );
      }
    }
  }
}
