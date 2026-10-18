/// WebDAV 传输层抽象 + dart:io 生产实现。
///
/// 为什么单独抽一层：WebDAV 后端的测试要求「不连真实网络」。若在
/// WebDavBackend 里直接 new HttpClient()，测试无法拦截；把「发一个 HTTP
/// 请求」收敛成单方法接口 [WebDavTransport]，测试注入假实现即可精确断言
/// method / url / headers（如 If-Match 裸值、Basic Auth 格式），同时生产
/// 路径仍然走真实的 dart:io HttpClient（项目铁律不引入 http/dio 依赖）。
library;

import 'dart:convert';
import 'dart:io';

/// 一次 WebDAV HTTP 请求的完整描述。
class WebDavHttpRequest {
  const WebDavHttpRequest({
    required this.method,
    required this.url,
    this.headers = const <String, String>{},
    this.body,
  });

  /// PROPFIND / GET / PUT / DELETE / MKCOL 等大写方法名。
  final String method;

  final Uri url;
  final Map<String, String> headers;
  final List<int>? body;
}

/// 一次 WebDAV HTTP 响应。
class WebDavHttpResponse {
  const WebDavHttpResponse({
    required this.statusCode,
    this.headers = const <String, String>{},
    this.body = const <int>[],
  });

  final int statusCode;
  final Map<String, String> headers;
  final List<int> body;

  /// 大小写不敏感取头。坚果云返回的 ETag/X-File-Version 等大小写不定。
  String? header(String name) {
    final direct = headers[name.toLowerCase()];
    if (direct != null) {
      return direct;
    }
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == name.toLowerCase()) {
        return e.value;
      }
    }
    return null;
  }

  String get bodyAsText => utf8.decode(body, allowMalformed: true);
}

/// 传输层：唯一入口 [send]。实现方不得自行缓存或重试——重试语义（如
/// PUT 404 后补建目录）归 WebDavBackend，保证测试假实现与生产实现行为
/// 边界一致。
abstract class WebDavTransport {
  Future<WebDavHttpResponse> send(WebDavHttpRequest request);
}

/// 生产实现：dart:io HttpClient 手写 HTTP（无第三方依赖）。
class HttpClientWebDavTransport implements WebDavTransport {
  HttpClientWebDavTransport({
    HttpClient? client,
    Duration connectionTimeout = const Duration(seconds: 30),
  }) : _ownsClient = client == null,
       _client = client ?? HttpClient() {
    _client.connectionTimeout = connectionTimeout;
  }

  final HttpClient _client;
  final bool _ownsClient;

  /// 结束时释放连接池。只在我们自己创建 client 时才真正关闭。
  void close() => _client.close(force: _ownsClient);

  @override
  Future<WebDavHttpResponse> send(WebDavHttpRequest request) async {
    final HttpClientRequest req =
        await _client.openUrl(request.method, request.url);
    request.headers.forEach(req.headers.set);
    if (request.body != null) {
      req.add(request.body!);
    }
    final HttpClientResponse resp = await req.close();
    final List<int> body =
        await resp.fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
    // 键统一小写；多值头用逗号合并（配合 header() 的大小写不敏感查找）。
    final Map<String, String> headers = <String, String>{};
    resp.headers.forEach((name, values) {
      headers[name.toLowerCase()] = values.join(', ');
    });
    return WebDavHttpResponse(
      statusCode: resp.statusCode,
      headers: headers,
      body: body,
    );
  }
}

/// Basic Auth 头（RFC 7617）。
///
/// 坚果云用的是「应用密码」而非登录密码。凭据由调用方从系统凭据库取出后
/// 经构造参数传入（AGENTS.md 铁律：不写代码、不落配置、不进日志），这里
/// 只做一次性编码，不做任何持久化。
String basicAuthHeader(String username, String password) =>
    'Basic ${base64Encode(utf8.encode('$username:$password'))}';
