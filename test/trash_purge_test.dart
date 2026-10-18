/// 回收站自动清空（M6-A4）测试。
///
/// 核心风险：`task` 是同步实体（sync_serializer.dart 的 kEntityTypes 含 task），
/// 物理删除必须与 op-log delete 意图**同一事务**落库，否则另一台设备永远留着
/// 该行、下次 pull 还可能复活它。op-log 断言（★ 标记）抓的就是这个错：
/// 若实现只 `DELETE FROM tasks` 不 append 意图，purge 后 `opLog('task')` 里
/// 按 operation 过滤出的 delete 行数为 0，expect(1) 当场失败——
/// 「双端同步」组那条则会在 B 端仍能看到该任务时失败。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/task_use_case.dart';
import 'package:qingdan/application/trash_purge_scheduler.dart';
import 'package:qingdan/features/settings/settings_model.dart';

import 'dao_test_helper.dart';
import 'sync_fakes.dart';
import 'sync_test_fixture.dart';

/// 记录 purge 调用次数的用例子类（调度器测试断言「调没调用例层」用）。
class _CountingTaskUseCase extends TaskUseCase {
  _CountingTaskUseCase(super.services);

  int purgeCalls = 0;

  @override
  Future<int> purgeExpiredTrash({required int days}) {
    purgeCalls++;
    return super.purgeExpiredTrash(days: days);
  }
}

DateTime _utcDaysAgo(int days) =>
    DateTime.now().toUtc().subtract(Duration(days: days));

void main() {
  ensureSqfliteFfi();

  group('TaskDao.purgeTrashedBefore', () {
    test('cutoff 精确性：40/20/1 天前三条只删 40 天那条，未删除行不动', () async {
      final DaoTestDb env = await DaoTestDb.open();
      final old = await env.taskDao.insert(title: '40 天前入站');
      final mid = await env.taskDao.insert(title: '20 天前入站');
      final fresh = await env.taskDao.insert(title: '1 天前入站');
      final active = await env.taskDao.insert(title: '还没进回收站');
      await env.taskDao.moveToTrash(old.id, deletedTime: _utcDaysAgo(40));
      await env.taskDao.moveToTrash(mid.id, deletedTime: _utcDaysAgo(20));
      await env.taskDao.moveToTrash(fresh.id, deletedTime: _utcDaysAgo(1));

      final int purged =
          await env.taskDao.purgeTrashedBefore(_utcDaysAgo(30));

      expect(purged, 1);
      expect(await env.taskDao.findById(old.id), isNull);
      expect(await env.taskDao.findById(mid.id), isNotNull);
      expect(await env.taskDao.findById(fresh.id), isNotNull);
      expect(await env.taskDao.findById(active.id), isNotNull,
          reason: '未删除的行绝不被触碰');
      expect((await env.taskDao.findTrashed()).map((t) => t.id),
          containsAll(<String>[mid.id, fresh.id]));
      await env.close();
    });

    test('★ op-log：purge 在同一事务内为每行记 task/delete 意图', () async {
      final DaoTestDb env = await DaoTestDb.open();
      final old = await env.taskDao.insert(title: '到期清空');
      final keep = await env.taskDao.insert(title: '未满阈值');
      await env.taskDao.moveToTrash(old.id, deletedTime: _utcDaysAgo(40));
      await env.taskDao.moveToTrash(keep.id, deletedTime: _utcDaysAgo(1));

      final int before = await env.opLogCount();
      await env.taskDao.purgeTrashedBefore(_utcDaysAgo(30));

      // 只多一条（不是两条、更不是零条）：事务内逐行 append 的最小形状。
      expect(await env.opLogCount(), before + 1);
      final List<Map<String, Object?>> deletes = (await env.opLog('task'))
          .where((Map<String, Object?> r) => r['operation'] == 'delete')
          .toList();
      expect(deletes, hasLength(1),
          reason: '漏记 op-log 的话对端永远收不到这条删除（本断言即为其红线）');
      expect(deletes.single['entity_id'], old.id);
      expect(deletes.single['changes_json'], contains('"field":"title"'),
          reason: 'delete 意图的 changes 形状与 deleteForever 一致（old=title, new=null）');
      // 未满阈值的那条不该有 delete 意图。
      expect(deletes.map((Map<String, Object?> r) => r['entity_id']),
          isNot(contains(keep.id)));
      await env.close();
    });

    test('子行不留孤儿：subtasks / task_tags 随 ON DELETE CASCADE 清除',
        () async {
      final DaoTestDb env = await DaoTestDb.open();
      final old = await env.taskDao.insert(title: '带子行的到期任务');
      final sub = await env.subtaskDao.insert(taskId: old.id, title: '步骤');
      final tag = await env.tagDao.insert(name: '标签');
      await env.tagDao.attachToTask(taskId: old.id, tagId: tag.id);
      await env.taskDao.moveToTrash(old.id, deletedTime: _utcDaysAgo(40));

      // seed 阶段给任务打标签本身就会记一条 task_tag 意图（`TagDao` 走共享 opLog，
      // 而 `task_tag` 不在 kEntityTypes 里，同步时被忽略）。所以这里要问的是
      // 「purge 有没有**新增** task_tag 意图」，而不是「一条都没有」。
      final int tagOpsBefore = (await env.opLog('task_tag')).length;

      final int purged = await env.taskDao.purgeTrashedBefore(_utcDaysAgo(30));
      expect(purged, 1);
      expect(await env.subtaskDao.findByTask(old.id), isEmpty);
      expect(await env.tagDao.findByTask(old.id), isEmpty);
      // 孤儿行走原始表确认（不依赖任何 DAO 的过滤逻辑）。
      expect(
          await env.db.query('subtasks',
              where: 'task_id = ?', whereArgs: <Object?>[old.id]),
          isEmpty);
      expect(
          await env.db.query('task_tags',
              where: 'task_id = ?', whereArgs: <Object?>[old.id]),
          isEmpty);
      expect((await env.opLog('task_tag')).length, tagOpsBefore,
          reason: 'purge 只该新增 task 的 delete 意图，不该碰 task_tag');
      expect(sub.taskId, old.id);
      await env.close();
    });

    test('无命中：返回 0 且不产生任何 op-log', () async {
      final DaoTestDb env = await DaoTestDb.open();
      final t = await env.taskDao.insert(title: '还早');
      await env.taskDao.moveToTrash(t.id, deletedTime: _utcDaysAgo(1));
      final int before = await env.opLogCount();

      expect(await env.taskDao.purgeTrashedBefore(_utcDaysAgo(30)), 0);
      expect(await env.opLogCount(), before);
      await env.close();
    });

    // 窄竞态兜底（M6-A4）：恢复过的行**留着过期的 `deleted_time`**——`TaskUseCase.restore`
    // 传 `deletedTime: null`，而 `Task.copyWith` 是 `??` 语义，清不掉旧值。所以只要
    // DELETE 少写一个 `deleted = 1`（旧实现就是只按 id 删），刚复活的活数据就会被
    // purge 吃掉，op-log 还跟着广播一条删除。
    // ★ 让这条断言先红一次的改法：把 DELETE 的 where 写成 `id = ? AND deleted_time < ?`。
    // （纯「SELECT 挪进事务」那半边的窗口期需要单连接里造不出的交错，测不到，
    //  这里钉的是「按 id 直删」这个真实可达的形状 + 恢复行不被动。）
    test('★ 竞态兜底：满足 cutoff 但已被恢复的行 → 返回 0、一行不动、不留 delete 意图',
        () async {
      final DaoTestDb env = await DaoTestDb.open();
      final tasks = TaskUseCase(AppServices(db: env.db));
      final revived = await env.taskDao.insert(title: '刚被恢复的任务');
      await env.taskDao.moveToTrash(revived.id, deletedTime: _utcDaysAgo(40));

      // 用户点「恢复」（同步 pull 回来的 restore 更新走同一条 update）。
      await tasks.restore(revived.id);
      expect((await env.taskDao.findById(revived.id))?.deleted, isFalse,
          reason: 'seed 侧确认恢复真的落库（deleted=0）');

      final int opsBefore = await env.opLogCount();
      final int purged = await env.taskDao.purgeTrashedBefore(_utcDaysAgo(30));

      expect(purged, 0, reason: '一条都不该删（它已经不在回收站里了）');
      expect(await env.taskDao.findById(revived.id), isNotNull,
          reason: '刚恢复的活数据绝不能被 purge 吃掉');
      expect(
          (await env.opLog('task'))
              .where((Map<String, Object?> r) => r['operation'] == 'delete'),
          isEmpty,
          reason: '没有真删掉的行就不该有 delete 意图');
      expect(await env.opLogCount(), opsBefore,
          reason: '这次 purge 一个字节都不该写');

      // 对照：同一条再次入站并过了 cutoff，就该真的被清掉（兜底条件没把功能关掉）。
      await env.taskDao.moveToTrash(revived.id, deletedTime: _utcDaysAgo(40));
      expect(await env.taskDao.purgeTrashedBefore(_utcDaysAgo(30)), 1);
      expect(await env.taskDao.findById(revived.id), isNull);
      await env.close();
    });
  });

  group('TaskUseCase.purgeExpiredTrash', () {
    test('days == 0（永不）：返回 0、不调 DAO、行原样保留', () async {
      final DaoTestDb env = await DaoTestDb.open();
      final tasks = TaskUseCase(AppServices(db: env.db));
      final old = await env.taskDao.insert(title: '到期但设为永不');
      await env.taskDao.moveToTrash(old.id, deletedTime: _utcDaysAgo(400));
      final int before = await env.opLogCount();

      expect(await tasks.purgeExpiredTrash(days: 0), 0);
      expect(await env.taskDao.findById(old.id), isNotNull);
      expect(await env.opLogCount(), before);

      // 对照：同一条在 days=30 下确实会被清掉（证明 cutoff 真的接通 DAO）。
      expect(await tasks.purgeExpiredTrash(days: 30), 1);
      expect(await env.taskDao.findById(old.id), isNull);
      await env.close();
    });
  });

  group('TrashPurgeScheduler（假时钟）', () {
    test('start 立即清一次；推进 30 分钟再清一次；stop 后不再清', () async {
      final DaoTestDb env = await DaoTestDb.open();
      final _CountingTaskUseCase tasks =
          _CountingTaskUseCase(AppServices(db: env.db));
      final SettingsModel settings = SettingsModel(); // 默认 30 天，不碰 prefs
      final FakeTimers fake = FakeTimers();
      final TrashPurgeScheduler scheduler = TrashPurgeScheduler(
          useCase: tasks, settings: settings, timers: fake);

      Future<String> seedExpired(String title) async {
        final t = await env.taskDao.insert(title: title);
        await env.taskDao.moveToTrash(t.id, deletedTime: _utcDaysAgo(40));
        return t.id;
      }

      final String first = await seedExpired('启动首轮');
      await scheduler.start();
      expect(tasks.purgeCalls, 1);
      expect(await env.taskDao.findById(first), isNull,
          reason: 'start() 必须立即检查一次，不等第一个 30 分钟');

      final String second = await seedExpired('周期第二轮');
      await fake.advance(kTrashPurgeCheckInterval);
      await scheduler.lastTick;
      expect(tasks.purgeCalls, 2);
      expect(await env.taskDao.findById(second), isNull);

      scheduler.stop();
      final String third = await seedExpired('stop 之后');
      await fake.advance(kTrashPurgeCheckInterval * 2);
      await scheduler.lastTick;
      expect(tasks.purgeCalls, 2, reason: 'stop() 必须取消周期定时器');
      expect(await env.taskDao.findById(third), isNotNull);
      await env.close();
    });

    test('trashPurgeDays == 0：调度器一次都不调用用例层', () async {
      final DaoTestDb env = await DaoTestDb.open();
      final _CountingTaskUseCase tasks =
          _CountingTaskUseCase(AppServices(db: env.db));
      final SettingsModel settings = SettingsModel()..trashPurgeDays = 0;
      final FakeTimers fake = FakeTimers();
      final TrashPurgeScheduler scheduler = TrashPurgeScheduler(
          useCase: tasks, settings: settings, timers: fake);

      final t = await env.taskDao.insert(title: '永不清空');
      await env.taskDao.moveToTrash(t.id, deletedTime: _utcDaysAgo(400));

      await scheduler.start();
      await fake.advance(kTrashPurgeCheckInterval * 3);
      await scheduler.lastTick;
      expect(tasks.purgeCalls, 0);
      expect(await env.taskDao.findById(t.id), isNotNull);
      await env.close();
    });
  });

  group('双端同步', () {
    test('A 端自动清空 + 同步后 B 端该任务物理消失', () async {
      final SyncTestFixture fx = await SyncTestFixture.create();
      addTearDown(fx.dispose);

      final task = await fx.device1.tasks.create(title: '将被自动清空');
      final String id = task.id;
      await fx.syncDevice(1);
      await fx.syncDevice(2);
      expect(await fx.device2.taskRow(id), isNotNull);

      // A 端入站并把 deleted_time 人为推到 40 天前（用例层的 cutoff 取真表）。
      await fx.device1.tasks.moveToTrash(id);
      await fx.device1.db.update(
        'tasks',
        <String, Object?>{'deleted_time': _utcDaysAgo(40).millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      expect(await fx.device1.tasks.purgeExpiredTrash(days: 30), 1);
      expect(await fx.device1.taskRow(id), isNull);

      final r1 = await fx.syncDevice(1);
      expect(r1.errors, isEmpty);
      expect(fx.cloudFileTree(), contains('tombstones/$id.json'),
          reason: 'purge 的 delete 意图必须上云成墓碑（同 deleteForever 通路）');

      final r2 = await fx.syncDevice(2);
      expect(r2.errors, isEmpty);
      expect(await fx.device2.taskRow(id), isNull,
          reason: '若 purge 不记 op-log，B 端这条会永远留着——本断言就是那条红线');
    });
  });
}
