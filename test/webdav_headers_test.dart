// Basic Auth 认证头与路径百分号编码测试。
// 拆分说明见 webdav_backend_test.dart 头注释；用例从原单文件原样迁出。
import 'package:flutter_test/flutter_test.dart';
import 'package:qingdan/sync/sync_backend.dart';
import 'package:qingdan/sync/webdav_backend.dart';
import 'package:qingdan/sync/webdav_transport.dart';

import 'webdav_test_fixture.dart';

void main() {
  late FakeWebDavTransport transport;
  late WebDavBackend backend;

  setUp(() {
    transport = FakeWebDavTransport();
    backend = makeBackend(transport);
  });

  group('Basic Auth（铁律：凭据不落任何持久层）', () {
    test('Authorization 头 = Basic base64(u:p)', () async {
      transport.handler =
          (req, i) => const WebDavHttpResponse(statusCode: 404);
      try {
        await backend.get('x');
      } on ObjectNotFoundException {
        // 预期
      }
      // base64('u:p') = dTpw
      expect(transport.last.headers['Authorization'], 'Basic dTpw');
    });

    test('所有请求都带 Authorization', () async {
      transport.handler = (req, i) => i == 0
          ? const WebDavHttpResponse(statusCode: 204)
          : multistatus([propEntry(href: '/dav/a.json', etag: 'e')]);
      await backend.put('a.json', [1], ifMatchEtag: 'e');
      expect(
        transport.requests.every((r) => r.headers['Authorization'] != null),
        isTrue,
      );
    });
  });

  group('路径拼接与百分号编码', () {
    test('非 ASCII 与空格文件名：分段编码、分隔符不编码', () async {
      transport.handler =
          (req, i) => const WebDavHttpResponse(statusCode: 404);
      try {
        await backend.get('我的 任务/abc def.json');
      } on ObjectNotFoundException {
        // 预期
      }
      final url = transport.last.url.toString();
      expect(url, contains('%E6%88%91%E7%9A%84%20%E4%BB%BB%E5%8A%A1'));
      expect(url, contains('abc%20def.json'));
      // '//' 只允许出现在 scheme 后（https://），路径部分不得出现。
      expect(url.substring('https://'.length), isNot(contains('//')));
    });

    test('`..` 逃逸被拒绝', () {
      expect(
        () => backend.put('../escaped.json', [1]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('URL 指向所选 host（不写死坚果云分发变体）', () async {
      transport.handler =
          (req, i) => const WebDavHttpResponse(statusCode: 404);
      try {
        await backend.get('a.json');
      } on ObjectNotFoundException {
        // 预期
      }
      expect(transport.last.url.host, 'dav.example.invalid');
      expect(transport.last.url.path, '/dav/a.json');
    });
  });
}
