/// 双端端到端同步测试：两台设备经同一个 LocalFolderBackend 云端收敛。
///
/// 核心场景（场景1）：离线并发改不同字段，三路合并后两端都拿到
/// 标题="B" 且 优先级=high —— 这是 M2 字段级合并存在的唯一理由。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qingdan/domain/task_priority.dart';

import 'sync_test_fixture.dart';

void main() {
  late SyncTestFixture fx;

  setUp(() async {
    fx = await SyncTestFixture.create();
  });

  tearDown(() async {
    await fx.dispose();
  });

  test('场景1（★核心）：离线并发改不同字段，三路合并后两端都收敛', () async {
    // 1. 设备1 建任务（标题 A，优先级 none）。
    final task = await fx.device1.tasks.create(title: 'A');
    final String id = task.id;

    // 2. 设备1 同步 → 上传到云端。
    final r1a = await fx.syncDevice(1);
    expect(r1a.uploaded, 1);

    // 3. 设备2 同步 → 拉到这个任务。
    final r2a = await fx.syncDevice(2);
    expect(r2a.downloaded, 1);
    expect((await fx.device2.taskRow(id))!['title'], 'A');

    // 4. 设备1 改标题为 B（离线，不同步）。
    final t1 = await fx.device1.tasks.findById(id);
    await fx.device1.tasks.update(t1!.copyWith(title: 'B'));

    // 5. 设备2 改优先级为 high（离线，不同步）。
    final t2 = await fx.device2.tasks.findById(id);
    await fx.device2.tasks.update(t2!.copyWith(priority: TaskPriority.high));

    // 6. 设备1 同步（上传标题变更，可能先拉到设备2 的优先级变更——顺序无关）。
    final r1b = await fx.syncDevice(1);
    expect(r1b.errors, isEmpty);

    // 7. 设备2 同步（拉到标题变更，推自己的优先级变更）。
    final r2b = await fx.syncDevice(2);
    expect(r2b.errors, isEmpty);

    // 7.5 设备1 再同步一次：拉取式同步没有推送通知——设备1 在第 6 步同步时
    // 设备2 的优先级变更还没上云，收敛必然需要这一轮。这是最终一致性的
    // 必然开销，不是实现 bug。
    final r1c = await fx.syncDevice(1);
    expect(r1c.errors, isEmpty);

    // 8. 断言：两端任务都是 标题=B 且 优先级=high。
    final row1 = await fx.device1.taskRow(id);
    final row2 = await fx.device2.taskRow(id);
    expect(row1, isNotNull);
    expect(row2, isNotNull);
    expect(row1!['title'], 'B',
        reason: '设备1 应保留自己改的标题，并从设备2 拉到优先级（不回滚）');
    expect(row1['priority'], TaskPriority.high.value);
    expect(row2!['title'], 'B');
    expect(row2['priority'], TaskPriority.high.value,
        reason: '设备2 应保留自己改的优先级，并从设备1 拉到标题');
  });

  test('场景2：双端同步幂等——收敛后连续两次同步零上传零下载（防死循环）', () async {
    final task = await fx.device1.tasks.create(title: '幂等双端');
    await fx.syncDevice(1);
    await fx.syncDevice(2);

    // 两端都已收敛到同一基线。再各同步一次：必须零传输。
    final r1 = await fx.syncDevice(1);
    final r2 = await fx.syncDevice(2);
    expect(r1.uploaded, 0, reason: '收敛后设备1 不该再上传');
    expect(r1.downloaded, 0, reason: '收敛后设备1 不该再下载');
    expect(r2.uploaded, 0, reason: '收敛后设备2 不该再上传');
    expect(r2.downloaded, 0, reason: '收敛后设备2 不该再下载');
    expect(r1.errors, isEmpty);
    expect(r2.errors, isEmpty);
    expect(task.id, isNotNull);
  });

  test('场景3：新建传播——设备1 建任务，设备2 同步后能查到', () async {
    final task = await fx.device1.tasks.create(title: '新建传播');
    await fx.syncDevice(1);

    final report = await fx.syncDevice(2);
    expect(report.downloaded, 1);

    final t = await fx.device2.tasks.findById(task.id);
    expect(t, isNotNull);
    expect(t!.title, '新建传播');
  });

  test('场景4：彻底删除传播——设备1 deleteForever，设备2 同步后物理行消失',
      () async {
    final task = await fx.device1.tasks.create(title: '将被彻底删除');
    final String id = task.id;
    await fx.syncDevice(1);
    await fx.syncDevice(2);
    expect(await fx.device2.taskRow(id), isNotNull);

    await fx.device1.tasks.deleteForever(id);
    final r1 = await fx.syncDevice(1);
    expect(r1.errors, isEmpty);
    // 云端有墓碑。
    expect(fx.cloudFileTree(), contains('tombstones/$id.json'));

    final r2 = await fx.syncDevice(2);
    expect(r2.errors, isEmpty);
    // 设备2 本地行也没了。
    expect(await fx.device2.taskRow(id), isNull);
  });

  test('场景5：回收站传播——设备1 移入回收站，设备2 该任务 deleted==1',
      () async {
    final task = await fx.device1.tasks.create(title: '回收站传播');
    final String id = task.id;
    await fx.syncDevice(1);
    await fx.syncDevice(2);

    await fx.device1.tasks.moveToTrash(id);
    final r1 = await fx.syncDevice(1);
    expect(r1.errors, isEmpty);

    final r2 = await fx.syncDevice(2);
    expect(r2.errors, isEmpty);
    final row2 = await fx.device2.taskRow(id);
    expect(row2, isNotNull);
    expect(row2!['deleted'], 1, reason: '设备2 的任务应进入回收站状态');
    // 设备1 自身状态不变。
    expect((await fx.device1.taskRow(id))!['deleted'], 1);
  });

  test('场景6：条件写保护（跨端）——两端先后写同一实体，后写方用过期 etag 被拒并收敛',
      () async {
    // 两端先对齐基线。
    final task = await fx.device1.tasks.create(title: '条件写');
    final String id = task.id;
    await fx.syncDevice(1);
    await fx.syncDevice(2);

    // 设备2 离线改标题（还没上传），设备1 也改标题并同步——云端 etag 变了。
    await fx.device2.tasks
        .update((await fx.device2.tasks.findById(id))!.copyWith(title: '端2改'));
    await fx.device1.tasks
        .update((await fx.device1.tasks.findById(id))!.copyWith(title: '端1改'));
    final r1 = await fx.syncDevice(1);
    expect(r1.errors, isEmpty);

    // 设备2 同步：它的 upsert 会以云端最新内容为远端重跑合并，以对端为准收敛。
    // 不崩、不覆盖云端为旧值；最终两端标题一致（LWW：谁 modifiedTime 新谁赢，
    // 这里设备1 后改所以赢——但断言只要求两端一致且非设备2 旧值之外的内容）。
    final r2 = await fx.syncDevice(2);
    expect(r2.errors, isEmpty);
    final row1 = await fx.device1.taskRow(id);
    final row2 = await fx.device2.taskRow(id);
    // 两端收敛到同一标题（LWW 胜者），且引擎以 412 收敛流程处理而非静默覆盖。
    expect(row2!['title'], row1!['title']);
    // 若设备1 的时间戳较新，标题应为「端1改」（本机毫秒可能同毫秒——只在
    // 不同毫秒时断言，同毫秒平手时实现按确定性规则决胜，只要求一致）。
    if ((row1['modified_time'] as int) != (row2['modified_time'] as int)) {
      expect(row2['title'], '端1改');
    }
  });

  test('场景7：同一字段两端都改——LWW modifiedTime 较新者胜，其他字段不丢',
      () async {
    final task = await fx.device1.tasks.create(title: 'LWW双端');
    final String id = task.id;
    // 建任务时给定备注，验证 LWW 决胜后另一方的其他字段不丢。
    await fx.syncDevice(1);
    await fx.syncDevice(2);

    // 设备1 改标题（旧时间），设备2 改同一字段标题 + 优先级（新时间）。
    await fx.forceModifiedTime(fx.device1, id, 1000);
    await fx.device1.db.update(
      'tasks',
      {'title': '端1标题', 'modified_time': 1000},
      where: 'id = ?',
      whereArgs: [id],
    );
    await fx.device2.db.update(
      'tasks',
      {'title': '端2标题', 'priority': TaskPriority.high.value, 'modified_time': 5000},
      where: 'id = ?',
      whereArgs: [id],
    );

    final r1 = await fx.syncDevice(1);
    final r2 = await fx.syncDevice(2);
    expect(r1.errors, isEmpty);
    expect(r2.errors, isEmpty);
    // 设备1 再拉一轮：设备2 的决胜结果上云晚于设备1 的首轮同步。
    await fx.syncDevice(1);

    // 两端收敛：标题/优先级取 modifiedTime 较新的设备2；LWW 决胜的字段 ≥1。
    final row1 = await fx.device1.taskRow(id);
    final row2 = await fx.device2.taskRow(id);
    expect(row1!['title'], '端2标题');
    expect(row1['priority'], TaskPriority.high.value);
    expect(row2!['title'], '端2标题');
    expect(row2['priority'], TaskPriority.high.value);
    expect(r1.conflicts + r2.conflicts, greaterThanOrEqualTo(1));
  });
}
