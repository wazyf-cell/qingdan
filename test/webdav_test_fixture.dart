// WebDAV 测试共享夹具：假传输层 + 假响应构造器。
// 拆分原因：全项目规矩单文件 ≤300 行，测试文件按职责拆分后共用这些夹具。
//
// 凭据纪律：只用假凭据 'u'/'p'，不出现任何真实账号。
import 'dart:convert';

import 'package:qingdan/sync/webdav_backend.dart';
import 'package:qingdan/sync/webdav_transport.dart';

/// 假传输层：记录全部请求，按注册的处理函数生成响应。
/// 注入点设计见 webdav_transport.dart 头注释：传输收敛为单方法接口后，
/// 假实现可精确断言 method / url / headers，无需网络。
class FakeWebDavTransport implements WebDavTransport {
  final List<WebDavHttpRequest> requests = <WebDavHttpRequest>[];

  /// 默认处理：返回注册器；未注册则 404。
  WebDavHttpResponse Function(WebDavHttpRequest req, int index) handler =
      (req, i) => const WebDavHttpResponse(statusCode: 404);

  @override
  Future<WebDavHttpResponse> send(WebDavHttpRequest request) async {
    requests.add(request);
    return handler(request, requests.length - 1);
  }

  WebDavHttpRequest get last => requests.last;
}

/// 常用假后端工厂：host 故意用非真实分发变体（测试不用真地址）。
WebDavBackend makeBackend(FakeWebDavTransport t) => WebDavBackend(
      baseUrl: Uri.parse('https://dav.example.invalid/dav/'),
      username: 'u',
      password: 'p',
      transport: t,
    );

/// 构造坚果云形状的 207 multistatus 响应（allprop、d: 前缀、
/// 百分号编码 href、无引号裸 etag——真实形状）。
WebDavHttpResponse multistatus(List<String> responseChunks) =>
    WebDavHttpResponse(
      statusCode: 207,
      headers: {'content-type': 'application/xml; charset=utf-8'},
      body: utf8.encode(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<d:multistatus xmlns:d="DAV:">${responseChunks.join()}</d:multistatus>',
      ),
    );

String propEntry({
  required String href,
  String? etag,
  int? size,
  String? lastModified,
  bool isDir = false,
}) {
  final props = StringBuffer();
  if (isDir) {
    props.write('<d:resourcetype><d:collection/></d:resourcetype>');
  } else {
    props.write('<d:resourcetype/>');
  }
  if (etag != null) {
    props.write('<d:getetag>$etag</d:getetag>');
  }
  if (size != null) {
    props.write('<d:getcontentlength>$size</d:getcontentlength>');
  }
  if (lastModified != null) {
    props.write('<d:getlastmodified>$lastModified</d:getlastmodified>');
  }
  return '<d:response><d:href>$href</d:href>'
      '<d:propstat><d:prop>$props</d:prop>'
      '<d:status>HTTP/1.1 200 OK</d:status></d:propstat>'
      '</d:response>';
}
