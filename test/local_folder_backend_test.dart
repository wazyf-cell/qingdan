// LocalFolderBackend 单元测试：用真实临时目录（systemTemp），不用 mock。
// 重点覆盖：CAS 三条红线（错误 etag 拒绝且内容不变、文件不存在拒绝、
// 相同内容相同 etag）、路径穿越防护、list/get/delete/capabilities。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingdan/sync/local_folder_backend.dart';
import 'package:qingdan/sync/sync_backend.dart';

void main() {
  late Directory tempDir;
  late LocalFolderBackend backend;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('qingdan_backend_test_');
    backend = LocalFolderBackend(tempDir);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('get', () {
    test('读不存在的文件 → 抛 ObjectNotFoundException', () {
      expect(
        () => backend.get('missing/a.json'),
        throwsA(isA<ObjectNotFoundException>()),
      );
    });
  });

  group('put / get', () {
    test('新建 → 返回 etag；get 读回内容逐字节相同', () async {
      final bytes = [1, 2, 3, 255, 0, 42];
      final etag = await backend.put('obj/a.bin', bytes);
      expect(etag, isNotNull);

      final got = await backend.get('obj/a.bin');
      expect(got.bytes, bytes); // List<int> 逐元素相等即逐字节相同
      expect(got.etag, etag);
    });

    test('覆盖（不传 etag）→ 成功，etag 变化', () async {
      final e1 = await backend.put('obj/a.bin', [1, 1, 1]);
      final e2 = await backend.put('obj/a.bin', [2, 2, 2]);
      expect(e1, isNot(e2));
      final got = await backend.get('obj/a.bin');
      expect(got.bytes, [2, 2, 2]);
    });

    test('传正确的 ifMatchEtag → CAS 正常路径成功', () async {
      final e1 = await backend.put('obj/a.bin', [9, 9]);
      final e2 = await backend.put('obj/a.bin', [8, 8], ifMatchEtag: e1);
      expect(e2, isNotNull);
      expect(e2, isNot(e1));
      expect((await backend.get('obj/a.bin')).bytes, [8, 8]);
    });

    test('★ 传错误的 ifMatchEtag → 抛 PreconditionFailedException，内容未变', () async {
      final original = [7, 7, 7];
      await backend.put('obj/a.bin', original);

      expect(
        () => backend.put('obj/a.bin', [1, 2, 3], ifMatchEtag: 'deadbeefdeadbeef'),
        throwsA(
          isA<PreconditionFailedException>()
              .having((e) => e.path, 'path', 'obj/a.bin')
              .having((e) => e.expectedEtag, 'expectedEtag', 'deadbeefdeadbeef'),
        ),
      );
      // 关键验收：拒绝写入后文件内容必须保持不变（不许静默覆盖）。
      expect((await backend.get('obj/a.bin')).bytes, original);
    });

    test('★ 传 ifMatchEtag 但文件不存在 → 抛 PreconditionFailedException', () {
      expect(
        () => backend.put('obj/ghost.bin', [1], ifMatchEtag: 'aaaaaaaaaaaaaaaa'),
        throwsA(isA<PreconditionFailedException>()),
      );
      // 且确实没有创建文件。
      expect(
        File('${tempDir.path}${Platform.pathSeparator}obj${Platform.pathSeparator}ghost.bin')
            .existsSync(),
        isFalse,
      );
    });

    test('相同内容两次写入（不同路径）→ etag 相同（内容派生）', () async {
      final e1 = await backend.put('obj/x.json', [10, 20, 30]);
      final e2 = await backend.put('obj/y.json', [10, 20, 30]);
      expect(e1, e2);
    });

    test('put 自动创建父目录（多级）', () async {
      await backend.put('a/b/c/deep.txt', [104, 105]);
      expect(
        File('${tempDir.path}${Platform.pathSeparator}a${Platform.pathSeparator}b'
                '${Platform.pathSeparator}c${Platform.pathSeparator}deep.txt')
            .readAsBytesSync(),
        [104, 105],
      );
    });
  });

  group('list', () {
    test('返回全部对象（含嵌套目录），路径与 etag 正确', () async {
      final eA = await backend.put('ns1/a.json', [1]);
      final eB = await backend.put('ns1/sub/b.json', [2, 2]);

      final objs = await backend.list('ns1');
      final paths = objs.map((o) => o.path).toSet();
      expect(paths, {'ns1/a.json', 'ns1/sub/b.json'});

      final a = objs.firstWhere((o) => o.path == 'ns1/a.json');
      expect(a.etag, eA);
      expect(a.size, 1);
      expect(a.modifiedAt, isNotNull);

      final b = objs.firstWhere((o) => o.path == 'ns1/sub/b.json');
      expect(b.etag, eB);
      expect(b.size, 2);
    });

    test('空 namespace → 空列表', () async {
      expect(await backend.list('nothing/here'), isEmpty);
    });
  });

  group('delete', () {
    test('删除存在的对象 → 之后 get 抛异常', () async {
      await backend.put('obj/a.bin', [1]);
      await backend.delete('obj/a.bin');
      expect(() => backend.get('obj/a.bin'), throwsA(isA<ObjectNotFoundException>()));
    });

    test('删除不存在的对象 → 抛 ObjectNotFoundException', () {
      expect(
        () => backend.delete('obj/ghost.bin'),
        throwsA(isA<ObjectNotFoundException>()),
      );
    });

    test('条件删：etag 匹配 → 成功；不匹配 → 412 且文件还在', () async {
      final e = await backend.put('obj/a.bin', [5, 6]);
      expect(
        () => backend.delete('obj/a.bin', ifMatchEtag: 'ffffffffffffffff'),
        throwsA(isA<PreconditionFailedException>()),
      );
      expect((await backend.get('obj/a.bin')).bytes, [5, 6]);
      await backend.delete('obj/a.bin', ifMatchEtag: e);
      expect(() => backend.get('obj/a.bin'), throwsA(isA<ObjectNotFoundException>()));
    });
  });

  group('路径穿越防护', () {
    test('★ ../ 逃逸 → 抛 ArgumentError，且 root 之外无文件生成', () async {
      // 与 root 同级放一个哨兵目录，用于确认没有任何越界写入。
      final outside = Directory.systemTemp.createTempSync('qingdan_backend_out_');
      try {
        expect(
          () => backend.put('../escaped.json', [1]),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => backend.get('../escaped.json'),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => backend.delete('../escaped.json'),
          throwsA(isA<ArgumentError>()),
        );
        // root 之外确实没生成文件：root 上级与哨兵目录里都没有 escaped.json。
        final escapedOutside =
            File('${tempDir.parent.path}${Platform.pathSeparator}escaped.json');
        expect(escapedOutside.existsSync(), isFalse);
        expect(
          File('${outside.path}${Platform.pathSeparator}escaped.json')
              .existsSync(),
          isFalse,
        );
      } finally {
        outside.deleteSync(recursive: true);
      }
    });
  });

  group('capabilities', () {
    test('三个字段值正确', () async {
      final caps = await backend.capabilities();
      expect(caps.supportsConditionalWrite, isTrue);
      expect(caps.supportsList, isTrue);
      expect(caps.supportsRangeRead, isFalse);
    });
  });

  group('ensureReady', () {
    // 本地后端的根就是构造参数目录，无就绪概念；默认空实现必须安静通过，
    // 保证 SyncEngine.sync() 对所有后端统一调用 ensureReady() 不会误伤。
    test('默认空实现：直接完成，无异常', () async {
      await expectLater(backend.ensureReady(), completes);
    });
  });
}
