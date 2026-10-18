/// 坚果云 WebDAV 实现的 [SyncBackend]。
///
/// 全部行为依据真实实测结论（见各陷阱注释），不是 RFC 推测：
///
/// 陷阱① If-Match 必须是**不带引号的裸 ETag**，违反 RFC 7232——带双引号、
///   单引号、W/ 前缀一律 412，且 412 表现与真并发冲突**完全相同**，极易
///   误诊。因此本后端所有 etag 出口统一经 `bareEtag`（webdav_client.dart）
///   剥引号，并在注释标注。
///
/// 陷阱② `If-None-Match: *` 被坚果云忽略（对已存在文件 PUT 仍返回 204），
///   所以**无法做「不存在才创建」的原子操作**。ifMatchEtag == null 的 put
///   就是无条件写，可能覆盖已存在文件——这是已知缺口，无法在服务端侧防护。
///
/// 陷阱③ PUT 响应**不返回 ETag 头**（只有 X-File-Version 整数）。取新 etag
///   需再发一次 PROPFIND（一次 put 实际 ≈ 3 个 HTTP 请求）。若 PROPFIND
///   拿不到 etag，退化为对写入内容算 sha256 etag（见 content_etag.dart），
///   以保持「put 返回内容派生 etag」与 LocalFolderBackend 一致的语义——
///   同步引擎靠 etag 判断「本地内容没变 → 远端没变 → 免重传」，服务端
///   etag 与内容派生 etag 混用只影响少一次上传判断，不影响正确性。
///
/// 陷阱④ PROPFIND 取 etag 必须发 `<d:allprop/>`；显式列 `<d:getetag/>`
///   经常不返回。本后端全部用 allprop（见 webdav_client.allpropBody）。
///
/// 陷阱⑤ 根目录不能直接 PUT 文件；PUT 进不存在的目录返回 404，须逐级
///   MKCOL 预创建；删除非空/空目录都返回 403（坚果云特性，未确证）。
///   本实现的 put/delete 都只针对文件对象（同步模型里目录由路径隐含）。
///
/// 端点 host 不写死（dav.jianguoyun.com / dav123.jianguoyun.com 等分发
/// 变体），由构造参数传入完整 baseUrl。凭据（坚果云「应用密码」）只作为
/// 构造参数，不持久化、不打日志（AGENTS.md 铁律）。
///
/// 文件拆分（单文件 ≤300 行规矩）：HTTP 协议细节（URL 拼接、PROPFIND 取
/// etag、逐级 MKCOL、etag 剥引号）在 webdav_client.dart；XML 解析在
/// webdav_xml.dart；传输注入点在 webdav_transport.dart；内容 etag 在
/// content_etag.dart。本文件只做「后端接口语义 ↔ WebDAV 动词」的映射。
library;

import 'dart:convert';

import 'content_etag.dart';
import 'sync_backend.dart';
import 'webdav_client.dart';
import 'webdav_transport.dart';
import 'webdav_xml.dart';

/// WebDAV 后端。所有对象路径是相对 [baseUrl] 路径部分的 `/` 分隔相对路径。
class WebDavBackend implements SyncBackend {
  /// [baseUrl] 形如 `https://dav.jianguoyun.com/dav/`（host 由调用方选定，
  /// 支持分发变体）；[username]/[password] 为坚果云账号与应用密码。
  WebDavBackend({
    required Uri baseUrl,
    required String username,
    required String password,
    WebDavTransport? transport,
  })  : _transport = transport ?? HttpClientWebDavTransport(),
        _ownsTransport = transport == null {
    _client = WebDavClient(
      baseUrl: _requireTrailingSlash(baseUrl),
      authHeader: basicAuthHeader(username, password),
      transport: _transport,
    );
  }

  late final WebDavClient _client;
  final WebDavTransport _transport;
  final bool _ownsTransport;

  static Uri _requireTrailingSlash(Uri uri) =>
      uri.toString().endsWith('/') ? uri : Uri.parse('${uri.toString()}/');

  @override
  Future<void> ensureReady() => _client.ensureRoot();

  @override
  Future<List<RemoteObject>> list(String namespace) async {
    final resp = await _transport.send(
      WebDavHttpRequest(
        method: 'PROPFIND',
        url: _client.resolveUrl(namespace),
        headers: {
          'Authorization': _client.authHeader,
          'Depth': 'infinity',
          'Content-Type': 'application/xml; charset=utf-8',
        },
        body: utf8.encode(WebDavClient.allpropBody),
      ),
    );
    if (resp.statusCode == 404) {
      // 根目录已由 ensureReady()（→ ensureRoot）在同步开始时保证存在，
      // 此处 404 语义唯一：namespace 目录（entities/、tombstones/ 等）
      // 尚未创建 = 云端为空，返回空列表（与 LocalFolderBackend 一致）。
      // baseUrl 本身不存在导致的 404 已被 ensureRoot 前置消灭——那才是
      // 「配置错误」，在引擎发出任何数据请求前就会以明确文案失败。
      return const [];
    }
    if (resp.statusCode != 207) {
      throw StateError('PROPFIND 失败（$namespace）: HTTP ${resp.statusCode}');
    }
    // href → 相对路径的解析已下沉到 webdav_xml.resolveObjects（纯文本处理，
    // 与协议交互分离）；这里只负责组装 RemoteObject。
    final baseDecoded = _client.baseUrl.path;
    final objects = <RemoteObject>[];
    for (final r in resolveObjects(
      entries: parseMultistatus(resp.bodyAsText),
      basePath: baseDecoded,
      namespace: namespace,
    )) {
      objects.add(
        RemoteObject(
          path: r.path,
          etag: r.entry.etag == null ? null : bareEtag(r.entry.etag!),
          size: r.entry.contentLength ?? 0,
          modifiedAt: r.entry.lastModified,
        ),
      );
    }
    return objects;
  }

  @override
  Future<({List<int> bytes, String? etag})> get(String path) async {
    final resp = await _transport.send(
      WebDavHttpRequest(
        method: 'GET',
        url: _client.resolveUrl(path),
        headers: {'Authorization': _client.authHeader},
      ),
    );
    if (resp.statusCode == 404) {
      throw ObjectNotFoundException(path);
    }
    if (resp.statusCode != 200) {
      throw StateError('GET 失败（$path）: HTTP ${resp.statusCode}');
    }
    final etagHeader = resp.header('ETag');
    return (
      bytes: resp.body,
      etag: etagHeader == null ? null : bareEtag(etagHeader),
    );
  }

  @override
  Future<String?> put(String path, List<int> bytes, {String? ifMatchEtag}) async {
    // CAS 前置检查：陷阱① 要求 If-Match 是裸 etag，这里统一剥。
    // 陷阱②：ifMatchEtag == null 时是无条件写（If-None-Match: * 被坚果云
    // 忽略，无法做「不存在才创建」，见类注释——已知缺口）。
    final headers = <String, String>{
      'Authorization': _client.authHeader,
      'Content-Type': 'application/octet-stream',
    };
    if (ifMatchEtag != null) {
      headers['If-Match'] = bareEtag(ifMatchEtag);
    }

    var resp = await _transport.send(
      WebDavHttpRequest(
        method: 'PUT',
        url: _client.resolveUrl(path),
        headers: headers,
        body: bytes,
      ),
    );
    if (resp.statusCode == 404 || resp.statusCode == 409) {
      // 陷阱⑤：父目录不存在时 PUT 被拒，**状态码因服务端而异**——
      // 坚果云实测 409（2026-09-30 真机穷举），标准实现（mod_dav、Nextcloud）404。
      // 两者都触发逐级 MKCOL 后重试一次（409 的其他来源见变更日志）。
      await _client.ensureParentDirs(path);
      resp = await _transport.send(
        WebDavHttpRequest(
          method: 'PUT',
          url: _client.resolveUrl(path),
          headers: headers,
          body: bytes,
        ),
      );
    }

    // 412 = 条件写失败。已统一发裸值（陷阱①），到这里仍 412 就是真冲突
    // （或目标不存在）。actualEtag 需额外 PROPFIND——冲突时值得多花一个
    // 请求，actualEtag 是同步引擎排障的关键信息。
    if (resp.statusCode == 412) {
      String? actual;
      try {
        actual = await _client.propfindEtag(path);
      } on Exception {
        actual = null; // 冲突是主信号，探测失败不掩盖它
      }
      throw PreconditionFailedException(
        path: path,
        expectedEtag: ifMatchEtag,
        actualEtag: actual,
      );
    }
    if (resp.statusCode != 201 && resp.statusCode != 204) {
      throw StateError('PUT 失败（$path）: HTTP ${resp.statusCode}');
    }

    // 陷阱③：PUT 响应没有 ETag 头（坚果云实测），必须 PROPFIND 取新 etag。
    // 但若某服务端/代理实现了标准行为带回了 ETag 头，直接用它可省一次请求
    // （配额宝贵：免费版 600 请求/30 分钟）。响应头同样经 bareEtag 剥引号。
    final respEtag = resp.header('ETag');
    if (respEtag != null && respEtag.trim().isNotEmpty) {
      return bareEtag(respEtag);
    }
    final etag = await _client.propfindEtag(path);
    if (etag != null && etag.isNotEmpty) {
      return etag;
    }
    // 退化路径：PROPFIND 拿不到 etag 时对写入内容算 sha256 etag
    // （与 LocalFolderBackend 的语义一致，理由见类注释陷阱③）。
    return sha256Etag(bytes);
  }

  @override
  Future<void> delete(String path, {String? ifMatchEtag}) async {
    final headers = <String, String>{'Authorization': _client.authHeader};
    if (ifMatchEtag != null) {
      headers['If-Match'] = bareEtag(ifMatchEtag);
    }
    final resp = await _transport.send(
      WebDavHttpRequest(
        method: 'DELETE',
        url: _client.resolveUrl(path),
        headers: headers,
      ),
    );
    if (resp.statusCode == 404) {
      throw ObjectNotFoundException(path);
    }
    if (resp.statusCode == 412) {
      // 同 put：冲突时补一次 PROPFIND 填 actualEtag。
      String? actual;
      try {
        actual = await _client.propfindEtag(path);
      } on Exception {
        actual = null;
      }
      throw PreconditionFailedException(
        path: path,
        expectedEtag: ifMatchEtag,
        actualEtag: actual,
      );
    }
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      // 403 = 坚果云删目录（无论空否）的特性，同步模型只删文件对象，
      // 文件被拒则如实抛错。
      throw StateError('DELETE 失败（$path）: HTTP ${resp.statusCode}');
    }
  }

  @override
  Future<BackendCapabilities> capabilities() async {
    // supportsConditionalWrite：坚果云支持 If-Match CAS（裸 etag，实测）。
    // supportsRangeRead：同步对象都是小 JSON，接口层也没用到 Range，如实 false。
    return const BackendCapabilities(
      supportsConditionalWrite: true,
      supportsList: true,
      supportsRangeRead: false,
    );
  }

  /// 释放底层连接池（仅当传输层由本类创建时）。
  void close() {
    if (_ownsTransport && _transport is HttpClientWebDavTransport) {
      _transport.close();
    }
  }
}
