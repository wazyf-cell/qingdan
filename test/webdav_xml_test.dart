// PROPFIND XML 解析与 list 前缀过滤测试（陷阱④，真实形状样本）。
// 拆分说明见 webdav_backend_test.dart 头注释；用例从原单文件原样迁出。
// 百分号编码的中文目录 href + 裸 etag + 秒级 HTTP-date，均按坚果云实测形状。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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

  group('★ PROPFIND XML 解析（陷阱④，真实形状样本）', () {
    test('allprop 响应：取 href / getetag / getcontentlength / getlastmodified',
        () async {
      transport.handler = (req, i) => multistatus([
            propEntry(href: '/dav/%e6%88%91%e7%9a%84/', isDir: true),
            propEntry(
              href: '/dav/%e6%88%91%e7%9a%84/%e4%bb%bb%e5%8a%a1.json',
              etag: 'yvhYroOdEZlSW8ZkJgo7TQ',
              size: 128,
              lastModified: 'Mon, 28 Sep 2026 05:12:23 GMT',
            ),
          ]);
      final objs = await backend.list('我的');
      expect(objs, hasLength(1));
      expect(objs.single.path, '我的/任务.json');
      expect(objs.single.etag, 'yvhYroOdEZlSW8ZkJgo7TQ');
      expect(objs.single.size, 128);
      expect(
        objs.single.modifiedAt!.toUtc().toIso8601String(),
        '2026-09-28T05:12:23.000Z',
      );
    });

    test('list 只返回前缀下的文件对象，目录与自身被过滤', () async {
      transport.handler = (req, i) => multistatus([
            propEntry(href: '/dav/entities/', isDir: true), // namespace 自身
            propEntry(href: '/dav/entities/tasks/', isDir: true), // 子目录
            propEntry(href: '/dav/entities/tasks/a.json', etag: 'e1', size: 1),
            propEntry(
              href: '/dav/entities/tasks/sub/b.json',
              etag: 'e2',
              size: 2,
            ),
            propEntry(href: '/dav/other.json', etag: 'e3', size: 3), // 前缀外
          ]);
      final objs = await backend.list('entities');
      expect(objs.map((o) => o.path).toSet(), {
        'entities/tasks/a.json',
        'entities/tasks/sub/b.json',
      });
    });

    test('list 404 → 空列表（与 LocalFolderBackend 语义一致）', () async {
      transport.handler =
          (req, i) => const WebDavHttpResponse(statusCode: 404);
      expect(await backend.list('nothing'), isEmpty);
    });

    test('自闭合 collection 标签与无前缀标签也能解析', () async {
      // 另一种真实变体：无命名空间前缀 + <collection/> 自闭合。
      transport.handler = (req, i) => WebDavHttpResponse(
            statusCode: 207,
            body: utf8.encode(
              '<?xml version="1.0"?>'
              '<multistatus xmlns="DAV:">'
              '<response><href>/dav/ns/</href><propstat><prop>'
              '<collection/>'
              '</prop><status>HTTP/1.1 200 OK</status></propstat></response>'
              '<response><href>/dav/ns/x.bin</href><propstat><prop>'
              '<resourcetype/>'
              '<getetag>short</getetag>'
              '<getcontentlength>7</getcontentlength>'
              '</prop><status>HTTP/1.1 200 OK</status></propstat></response>'
              '</multistatus>',
            ),
          );
      final objs = await backend.list('ns');
      expect(objs.single.path, 'ns/x.bin');
      expect(objs.single.etag, 'short');
    });
  });
}
