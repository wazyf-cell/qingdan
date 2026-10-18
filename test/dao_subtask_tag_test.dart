import 'package:flutter_test/flutter_test.dart';

import 'dao_test_helper.dart';

void main() {
  ensureSqfliteFfi();

  group('SubtaskDao', () {
    test('CRUD + findByTask 排序 + op-log', () async {
      final DaoTestDb env = await DaoTestDb.open();
      final t = await env.taskDao.insert(title: '父任务');
      final int before = await env.opLogCount();

      final s2 =
          await env.subtaskDao.insert(taskId: t.id, title: '乙', sortOrder: 2);
      final s1 =
          await env.subtaskDao.insert(taskId: t.id, title: '甲', sortOrder: 1);
      expect((await env.subtaskDao.findByTask(t.id)).map((s) => s.title),
          <String>['甲', '乙']);
      expect((await env.subtaskDao.findById(s1.id))!.completed, isFalse);

      await env.subtaskDao.update(s1.copyWith(completed: true));
      expect((await env.subtaskDao.findById(s1.id))!.completed, isTrue);
      final rows = await env.opLogRows();
      expect(rows.length, before + 3); // create×2 + update
      final String changes = rows.last['changes_json']! as String;
      expect(changes, contains('"field":"completed"'));

      await env.subtaskDao.delete(s2.id);
      expect(await env.subtaskDao.findById(s2.id), isNull);
      expect((await env.opLogRows()).last['operation'], 'delete');
      await env.close();
    });
  });

  group('TagDao（F11，P1 表就位）', () {
    test('标签 CRUD + attach/detach 幂等 + 按任务查标签', () async {
      final DaoTestDb env = await DaoTestDb.open();
      final t = await env.taskDao.insert(title: '任务');
      final g = await env.tagDao.insert(name: '重要', color: '#ff0000');
      final int before = await env.opLogCount();

      await env.tagDao.attachToTask(taskId: t.id, tagId: g.id);
      await env.tagDao.attachToTask(taskId: t.id, tagId: g.id); // 幂等
      expect((await env.tagDao.findByTask(t.id)).map((x) => x.name),
          <String>['重要']);
      expect((await env.opLogRows()).length, before + 1,
          reason: '重复挂载不应重复记流水');

      await env.tagDao.detachFromTask(taskId: t.id, tagId: g.id);
      await env.tagDao.detachFromTask(taskId: t.id, tagId: g.id); // 幂等
      expect(await env.tagDao.findByTask(t.id), isEmpty);

      await env.tagDao.update(g.copyWith(name: '重要事'));
      expect((await env.tagDao.findById(g.id))!.name, '重要事');
      await env.tagDao.delete(g.id);
      expect(await env.tagDao.findById(g.id), isNull);
      await env.close();
    });

    test('删任务后关联清理（外键 CASCADE）', () async {
      final DaoTestDb env = await DaoTestDb.open();
      final t = await env.taskDao.insert(title: '任务');
      final g = await env.tagDao.insert(name: '标签');
      await env.tagDao.attachToTask(taskId: t.id, tagId: g.id);
      await env.taskDao.deleteForever(t.id);
      expect(await env.tagDao.findByTask(t.id), isEmpty);
      expect(await env.tagDao.findById(g.id), isNotNull,
          reason: '标签本体不随任务删除');
      await env.close();
    });
  });

  group('op-log 完整性（F38）', () {
    test('每条流水 uploaded 恒为 0、operated_time 非空', () async {
      final DaoTestDb env = await DaoTestDb.open();
      final l = await env.listDao.insert(name: '清单');
      final t = await env.taskDao.insert(title: '任务', listId: l.id);
      await env.taskDao.moveToTrash(t.id);
      final rows = await env.opLogRows();
      expect(rows, isNotEmpty);
      for (final Map<String, Object?> r in rows) {
        expect(r['uploaded'], 0, reason: 'M1 恒为未上传');
        expect(r['operated_time'], isNotNull);
        expect(r['changes_json'], isNotEmpty);
      }
      await env.close();
    });
  });

  group('事务原子性（写库 + op-log 同事务）', () {
    test('实体写失败时 op-log 不残留（无半写）', () async {
      // 通过注册非法触发器让 tasks 表的 INSERT 必然失败，
      // 验证同一事务内的 op_log 写入被一并回滚。
      final DaoTestDb env = await DaoTestDb.open();
      await env.db.execute(
          "CREATE TRIGGER fail_tasks_insert BEFORE INSERT ON tasks "
          "BEGIN SELECT RAISE(ABORT, 'forced failure'); END");
      final int before = await env.opLogCount();

      await expectLater(
        env.taskDao.insert(title: '必败'),
        throwsA(anything),
      );
      expect(await env.opLogCount(), before, reason: '事务回滚后 op-log 不应有新记录');
      expect(await env.db.query('tasks'), isEmpty);

      await env.db.execute('DROP TRIGGER fail_tasks_insert');
      // 同一路径在触发器移除后恢复正常（说明失败来自注入，而非 DAO 逻辑）。
      await env.taskDao.insert(title: '恢复');
      expect(await env.opLogCount(), before + 1);
      await env.close();
    });
  });
}
