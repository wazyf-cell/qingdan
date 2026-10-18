// WebDavBackend 单元测试（核心 CAS / 条件写路径），假 HTTP 层不连真实网络。
// 拆分说明：全项目规矩单文件 ≤300 行，测试按职责拆为——
//   本文件：If-Match 条件写、412/404 异常、PUT 无 ETag 退化、capabilities；
//   webdav_xml_test.dart：PROPFIND XML 解析与 list 前缀过滤；
//   webdav_headers_test.dart：Basic Auth 认证头与路径百分号编码；
//   webdav_test_fixture.dart：共享夹具（假传输层、假响应构造器）。
// 用例总数不变（21 个），一个未删未放宽。
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

  group('★ If-Match 条件写（陷阱①）', () {
    test('If-Match 发出的是不带引号的裸 etag', () async {
      transport.handler = (req, i) => i == 0
          ? const WebDavHttpResponse(statusCode: 204)
          : multistatus([
              propEntry(
                href: '/dav/manifest.json',
                etag: '7rUhJVNLEbF4X7j_cO-4yw',
                size: 3,
              ),
            ]);
      await backend.put(
        'manifest.json',
        [1, 2, 3],
        ifMatchEtag: '7rUhJVNLEbF4X7j_cO-4yw',
      );
      final putReq = transport.requests.firstWhere((r) => r.method == 'PUT');
      expect(putReq.headers['If-Match'], '7rUhJVNLEbF4X7j_cO-4yw');
      expect(putReq.headers['If-Match'], isNot(contains('"')));
      expect(putReq.headers['If-Match'], isNot(startsWith('W/')));
    });

    test('服务端返回带引号的 etag → 剥掉后再用于 If-Match', () async {
      transport.handler = (req, i) => i == 0
          ? const WebDavHttpResponse(statusCode: 204)
          : multistatus([
              propEntry(href: '/dav/a.json', etag: '"yvhYroOdEZlSW8ZkJgo7TQ"'),
            ]);
      await backend.put(
        'a.json',
        [1],
        ifMatchEtag: '"yvhYroOdEZlSW8ZkJgo7TQ"',
      );
      final putReq = transport.requests.firstWhere((r) => r.method == 'PUT');
      expect(putReq.headers['If-Match'], 'yvhYroOdEZlSW8ZkJgo7TQ');
    });

    test('弱验证器 W/"..." 也被剥成裸值', () async {
      transport.handler = (req, i) => i == 0
          ? const WebDavHttpResponse(statusCode: 204)
          : multistatus([propEntry(href: '/dav/a.json', etag: 'abc')]);
      await backend.put('a.json', [1], ifMatchEtag: 'W/"abc"');
      final putReq = transport.requests.firstWhere((r) => r.method == 'PUT');
      expect(putReq.headers['If-Match'], 'abc');
    });

    test('★ 412 → 抛 PreconditionFailedException（含 path/expected/actual）',
        () async {
      transport.handler = (req, i) => i == 0
          ? const WebDavHttpResponse(statusCode: 412)
          : multistatus([propEntry(href: '/dav/a.json', etag: 'serverNow')]);
      await expectLater(
        backend.put('a.json', [1], ifMatchEtag: 'stale'),
        throwsA(
          isA<PreconditionFailedException>()
              .having((e) => e.path, 'path', 'a.json')
              .having((e) => e.expectedEtag, 'expectedEtag', 'stale')
              .having((e) => e.actualEtag, 'actualEtag', 'serverNow'),
        ),
      );
    });

    test('delete 条件删 412 同样抛 PreconditionFailedException', () async {
      transport.handler = (req, i) => i == 0
          ? const WebDavHttpResponse(statusCode: 412)
          : multistatus([propEntry(href: '/dav/a.json', etag: 'live')]);
      await expectLater(
        backend.delete('a.json', ifMatchEtag: 'old'),
        throwsA(
          isA<PreconditionFailedException>()
              .having((e) => e.actualEtag, 'actualEtag', 'live'),
        ),
      );
    });
  });

  group('404 → ObjectNotFoundException', () {
    test('get 404 抛异常', () async {
      transport.handler =
          (req, i) => const WebDavHttpResponse(statusCode: 404);
      await expectLater(
        backend.get('missing.json'),
        throwsA(isA<ObjectNotFoundException>()),
      );
    });

    test('delete 404 抛异常', () async {
      transport.handler =
          (req, i) => const WebDavHttpResponse(statusCode: 404);
      await expectLater(
        backend.delete('missing.json'),
        throwsA(isA<ObjectNotFoundException>()),
      );
    });
  });

  group('★ PUT 无 ETag 头的退化（陷阱③）', () {
    test('PUT 204 + PROPFIND 拿到 etag → 返回服务端 etag', () async {
      transport.handler = (req, i) => i == 0
          ? const WebDavHttpResponse(statusCode: 204)
          : multistatus([
              propEntry(href: '/dav/manifest.json', etag: 'serverEtag123'),
            ]);
      final etag = await backend.put('manifest.json', [1, 2, 3]);
      expect(etag, 'serverEtag123');
    });

    test('PUT 后 PROPFIND 无 etag 属性 → 退化为内容 sha256 etag', () async {
      transport.handler = (req, i) => i == 0
          // 204 但 PROPFIND 响应缺 getetag（坚果云偶发行为）
          ? const WebDavHttpResponse(statusCode: 204)
          : multistatus([propEntry(href: '/dav/manifest.json', size: 3)]);
      final etag = await backend.put('manifest.json', [1, 2, 3]);
      // sha256([1,2,3]) 前 16 位十六进制（与 local_folder_backend 同算法）。
      expect(etag, matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('PUT 返回带 ETag 头时优先用响应头（省一次 PROPFIND）', () async {
      transport.handler =
          (req, i) => i == 0
              ? const WebDavHttpResponse(
                  statusCode: 201,
                  headers: {'etag': '"respEtag"'},
                )
              : throw StateError('不应再发 PROPFIND');
      final etag = await backend.put('a.json', [1]);
      expect(etag, 'respEtag'); // 已剥引号
      expect(transport.requests, hasLength(1));
    });

    test('PUT 进不存在目录 404 → MKCOL 逐级补建后重试（陷阱⑤）', () async {
      transport.handler = (req, i) {
        final method = req.method;
        if (method == 'PUT') {
          return i < 2
              ? const WebDavHttpResponse(statusCode: 404)
              : const WebDavHttpResponse(statusCode: 201);
        }
        if (method == 'PROPFIND' && req.url.path.endsWith('manifest.json')) {
          return multistatus([
            propEntry(href: '/dav/entities/manifest.json', etag: 'afterMkcol'),
          ]);
        }
        // 目录存在性探测与 MKCOL
        if (method == 'PROPFIND') {
          return const WebDavHttpResponse(statusCode: 404);
        }
        if (method == 'MKCOL') {
          return const WebDavHttpResponse(statusCode: 201);
        }
        return const WebDavHttpResponse(statusCode: 500);
      };
      final etag = await backend.put('entities/manifest.json', [1]);
      expect(etag, 'afterMkcol');
      final methods = transport.requests.map((r) => r.method).toList();
      expect(methods, ['PUT', 'PROPFIND', 'MKCOL', 'PUT', 'PROPFIND']);
    });
  });

  group('★ ensureRoot：根目录就绪（消灭 list() 404 二义性）', () {
    // baseUrl = https://dav.example.invalid/dav/，根探测 URL 即它本身。
    test('PROPFIND 207 → 直接通过，不发 MKCOL', () async {
      transport.handler =
          (req, i) => multistatus([propEntry(href: '/dav/', isDir: true)]);
      await backend.ensureReady();
      final methods = transport.requests.map((r) => r.method).toList();
      expect(methods, ['PROPFIND']);
      expect(transport.requests.first.url.toString(),
          'https://dav.example.invalid/dav/');
      expect(transport.requests.first.headers['Depth'], '0');
    });

    test('404 → MKCOL 根目录 → 复检 207 → 通过（调用序列含 MKCOL）', () async {
      transport.handler = (req, i) {
        if (req.method == 'PROPFIND') {
          // 首次 404；MKCOL 之后的复检通过。
          return i == 0
              ? const WebDavHttpResponse(statusCode: 404)
              : multistatus([propEntry(href: '/dav/', isDir: true)]);
        }
        if (req.method == 'MKCOL') {
          return const WebDavHttpResponse(statusCode: 201);
        }
        return const WebDavHttpResponse(statusCode: 500);
      };
      await backend.ensureReady();
      final methods = transport.requests.map((r) => r.method).toList();
      expect(methods, ['PROPFIND', 'MKCOL', 'PROPFIND'],
          reason: '必须先探测、再建根、最后复检');
      // MKCOL 打的也是根 URL（baseUrl 尾段目录）。
      expect(transport.requests[1].url.toString(),
          'https://dav.example.invalid/dav/');
    });

    test('401 → 抛 SyncConfigException（凭据文案）', () async {
      transport.handler =
          (req, i) => const WebDavHttpResponse(statusCode: 401);
      await expectLater(
        backend.ensureReady(),
        throwsA(
          isA<SyncConfigException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.hint, 'hint', contains('应用密码')),
        ),
      );
    });

    test('403 → 抛 SyncConfigException（凭据文案）', () async {
      transport.handler =
          (req, i) => const WebDavHttpResponse(statusCode: 403);
      await expectLater(
        backend.ensureReady(),
        throwsA(isA<SyncConfigException>()),
      );
    });

    test('404 → MKCOL 建上但复检仍 404 → 抛 SyncConfigException（含 baseUrl）',
        () async {
      // MKCOL 受理（201），但根目录就是建不出来（如父级只读）——
      // 复检揭穿，必须以配置异常收场，不能让引擎误以为云端为空。
      transport.handler = (req, i) => req.method == 'MKCOL'
          ? const WebDavHttpResponse(statusCode: 201)
          : const WebDavHttpResponse(statusCode: 404);
      await expectLater(
        backend.ensureReady(),
        throwsA(
          isA<SyncConfigException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having(
                (e) => e.toString(),
                'toString 含 baseUrl 原文',
                contains('https://dav.example.invalid/dav/'),
              ),
        ),
      );
      // 探测、建根、复检，共 3 个请求后放弃。
      expect(transport.requests, hasLength(3));
    });

    test('MKCOL 本身被拒（如 403）→ 直接抛 SyncConfigException', () async {
      transport.handler = (req, i) => req.method == 'MKCOL'
          ? const WebDavHttpResponse(statusCode: 403)
          : const WebDavHttpResponse(statusCode: 404);
      await expectLater(
        backend.ensureReady(),
        throwsA(
          isA<SyncConfigException>()
              .having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
      // MKCOL 被拒就没有复检的必要了。
      expect(transport.requests, hasLength(2));
    });

    test('其他状态码（如 502）→ 抛 SyncConfigException 携带原码', () async {
      transport.handler = (req, i) => const WebDavHttpResponse(statusCode: 502);
      await expectLater(
        backend.ensureReady(),
        throwsA(
          isA<SyncConfigException>()
              .having((e) => e.statusCode, 'statusCode', 502),
        ),
      );
    });
  });

  group('capabilities', () {
    test('CAS 可用、可列目录、不支持范围读', () async {
      final caps = await backend.capabilities();
      expect(caps.supportsConditionalWrite, isTrue);
      expect(caps.supportsList, isTrue);
      expect(caps.supportsRangeRead, isFalse);
    });
  });
}
