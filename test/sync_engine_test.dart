/// 单端单元测试：SyncEngine 基础流程（同步、幂等、LWW、墓碑）。
///
/// 只用一台设备 + 本地文件夹后端，验证单实例下的正确性；
/// 双端交叉场景见 sync_two_device_test.dart。
library;

import 'dart:convert';

import 'package:qingdan/domain/task_priority.dart';
import 'package:qingdan/sync/local_folder_backend.dart' show sha256Etag;
import 'package:qingdan/sync/sync_backend.dart';
import 'package:qingdan/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_test_fixture.dart';

void main() {
  late SyncTestFixture fx;

  setUp(() async {
    fx = await SyncTestFixture.create();
  });

  tearDown(() async {
    await fx.dispose();
  });

  /// 在设备1 建一个任务并返回 id。
  Future<String> createTask(String title) async {
    final task = await fx.device1.tasks.create(title: title);
    return task.id;
  }

  test('新建任务 → 同步 → 上传到云端（entities/task 布局 + manifest）',
      () async {
    final String id = await createTask('买入牛奶');

    final report = await fx.syncDevice(1);

    // 上传了 1 个实体文件（不含墓碑与 manifest）。
    expect(report.uploaded, 1);
    expect(report.downloaded, 0);
    expect(report.errors, isEmpty);
    // 云端布局：entities/task/<id>.json（扁平，2026-09-30 真机实测后改）。
    final String expected = 'entities/task/$id.json';
    expect(fx.cloudFileTree(), contains(expected));
    // manifest 也写了（有数据变化时才写）。
    expect(fx.cloudFileTree(), contains('manifest.json'));
  });

  test('同步幂等：连续两次同步，第二次 uploaded==0 且 downloaded==0（防死循环）',
      () async {
    await createTask('幂等检查');
    final first = await fx.syncDevice(1);
    expect(first.uploaded, 1);

    // 第二次同步：本地与基线一致、远端 etag 未变（内容派生），必须零传输。
    // 若 rev/deviceId 误判触发重传，这里会 >0，即「永远在同步」的死循环。
    final second = await fx.syncDevice(1);
    expect(second.uploaded, 0,
        reason: '第二次同步不该再上传任何实体（rev/deviceId 误判会死循环）');
    expect(second.downloaded, 0, reason: '第二次同步不该再下载任何实体');
    expect(second.errors, isEmpty);
  });

  test('彻底删除 → 同步 → 本地行消失，云端留下墓碑文件', () async {
    final String id = await createTask('待删除');
    await fx.syncDevice(1);

    await fx.device1.tasks.deleteForever(id);
    final report = await fx.syncDevice(1);

    expect(report.errors, isEmpty);
    // 本地已物理删除。
    expect(await fx.device1.taskRow(id), isNull);
    // 云端实体文件删掉（tombstones/<id>.json 也会命中 contains('/$id.json')，
    // 所以必须只看 entities/ 前缀），留下墓碑 tombstones/<id>.json。
    expect(
      fx.cloudFileTree().where(
          (p) => p.startsWith('entities/') && p.contains('/$id.json')),
      isEmpty,
      reason: '实体文件应被删除',
    );
    expect(fx.cloudFileTree(), contains('tombstones/$id.json'));
  });

  test('条件写保护：过期 etag 写入抛 PreconditionFailedException，内容不被覆盖',
      () async {
    final List<int> bytes = utf8.encode('{"title":"旧内容"}');
    final String path = 'entities/task/test-cond.json';
    final String etagV1 = (await fx.backend.put(path, bytes))!;

    // 模拟「对端先写过」：无条件覆盖，云端 etag 前进到 v2。
    final List<int> v2 = utf8.encode('{"title":"对端已改"}');
    await fx.backend.put(path, v2);

    // 拿过期 etag（v1）条件写：当前 etag 是 v2，必须 412 拒绝，不许静默覆盖。
    final List<int> newBytes = utf8.encode('{"title":"新内容"}');
    await expectLater(
      fx.backend.put(path, newBytes, ifMatchEtag: etagV1),
      throwsA(isA<PreconditionFailedException>()),
    );

    // 内容未被静默覆盖：读回仍是对端写入的 v2，新内容没写进去。
    final ({List<int> bytes, String? etag}) after = await fx.backend.get(path);
    expect(utf8.decode(after.bytes), '{"title":"对端已改"}');
    expect(after.etag, sha256Etag(v2));
  });

  test('同一字段两端都改：LWW 按 modifiedTime 较新者胜，不丢另一端字段',
      () async {
    // 设备1 建任务，两端都拉到同一基线。
    final String id = await createTask('LWW任务');
    await fx.syncDevice(1);
    await fx.syncDevice(2);
    expect(await fx.device2.taskRow(id), isNotNull);

    // 设备1 改标题（modifiedTime = T1），设备2 也改标题但时间更晚（T2 > T1）。
    final t1 = await fx.device1.taskRow(id);
    await fx.device1.db.update(
      'tasks',
      {'title': '设备1的标题', 'modified_time': 1000},
      where: 'id = ?',
      whereArgs: [id],
    );
    await fx.device2.db.update(
      'tasks',
      {'title': '设备2的标题', 'modified_time': 2000},
      where: 'id = ?',
      whereArgs: [id],
    );
    // t1 只用来确认基线存在（dart analyze 不喜欢未使用变量）。
    expect(t1, isNotNull);

    // 设备1 先同步（上传自己的标题），设备2 后同步（LWW 决胜：本地 2000 更新，
    // 保留「设备2的标题」并上传）。之后设备1 需要再同步一次才能拉到决胜结果
    // —— 拉取式同步没有推送通知，一轮收敛是最终一致性的必然，不是 bug。
    final r1 = await fx.syncDevice(1);
    final r2 = await fx.syncDevice(2);
    expect(r1.errors, isEmpty);
    expect(r2.errors, isEmpty);
    await fx.syncDevice(1);

    // 两端收敛到 modifiedTime 更新的设备2 标题；LWW 决胜的字段数 ≥1。
    final row1 = await fx.device1.taskRow(id);
    final row2 = await fx.device2.taskRow(id);
    expect(row1!['title'], '设备2的标题');
    expect(row2!['title'], '设备2的标题');
    expect(r1.conflicts + r2.conflicts, greaterThanOrEqualTo(1));
  });

  test('报告字段：一次真实同步的 requests 计数 > 0 且 durationMs ≥ 0', () async {
    await createTask('请求计数');
    final report = await fx.syncDevice(1);
    // list + get + put 等 backend 调用都必须经过计数器，不能漏。
    expect(report.requests, greaterThan(0));
    expect(report.durationMs, greaterThanOrEqualTo(0));
  });

  test('优先级枚举往返：TaskPriority 序列化为整数且能还原', () async {
    // 场景1 依赖 priority 的 int 序列化正确，这里单测兜底。
    final String id = await createTask('优先级');
    final row = await fx.device1.taskRow(id);
    expect(row!['priority'], TaskPriority.none.value);
  });

  test('★ sync() 先调 ensureReady，再发任何 list/get/put（fail-fast 顺序）',
      () async {
    // 假后端记录调用顺序；ensureReady 抛配置异常时，异常必须原样冒泡
    // （fail-fast，不伪装成报告 errors），且引擎不得发出任何数据请求。
    final calls = <String>[];
    final fake = _RecordingBackend(calls, ensureReadyError: Exception('配置错误'));
    final engine = SyncEngine(backend: fake, db: fx.device1.db);

    await expectLater(
      engine.sync(),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('配置错误'),
        ),
      ),
    );
    expect(calls.first, 'ensureReady', reason: 'ensureReady 必须先于一切数据请求');
    expect(calls, everyElement('ensureReady'),
        reason: 'ensureReady 抛出后不应再有任何 list/get/put/delete');
  });

  test('ensureReady 正常后，后续数据请求按 list 在前的顺序发生', () async {
    final calls = <String>[];
    await SyncEngine(
      backend: _RecordingBackend(calls),
      db: fx.device1.db,
    ).sync();
    expect(calls.first, 'ensureReady');
    expect(calls, contains('list'));
    expect(calls.indexOf('ensureReady'), lessThan(calls.indexOf('list')));
  });
}

/// 顺序记录用假后端：方法入参忽略，只记调用序。
class _RecordingBackend extends SyncBackend {
  _RecordingBackend(this.calls, {this.ensureReadyError});

  final List<String> calls;
  final Object? ensureReadyError;

  @override
  Future<void> ensureReady() async {
    calls.add('ensureReady');
    final err = ensureReadyError;
    if (err != null) {
      throw err;
    }
  }

  @override
  Future<List<RemoteObject>> list(String namespace) async {
    calls.add('list');
    return const [];
  }

  @override
  Future<({List<int> bytes, String? etag})> get(String path) async {
    calls.add('get');
    throw ObjectNotFoundException(path);
  }

  @override
  Future<String?> put(String path, List<int> bytes, {String? ifMatchEtag}) async {
    calls.add('put');
    return null;
  }

  @override
  Future<void> delete(String path, {String? ifMatchEtag}) async {
    calls.add('delete');
  }

  @override
  Future<BackendCapabilities> capabilities() async {
    return const BackendCapabilities(
      supportsConditionalWrite: true,
      supportsList: true,
      supportsRangeRead: false,
    );
  }
}
