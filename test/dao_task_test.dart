import 'package:flutter_test/flutter_test.dart';

import 'package:qingdan/domain/task_priority.dart';

import 'dao_test_helper.dart';

void main() {
  ensureSqfliteFfi();

  group('TaskDao', () {
    test('insert 与默认值、create op-log', () async {
      final DaoTestDb env = await DaoTestDb.open();
      final int before = await env.opLogCount();
      final t = await env.taskDao.insert(title: '买牛奶', note: '# 标签');
      expect(t.priority, TaskPriority.none);
      expect(t.completed, isFalse);
      expect(t.deleted, isFalse);
      expect(t.createdTime, isNotNull);
      expect(t.modifiedTime, t.createdTime);

      final rows = await env.opLogRows();
      expect(rows.length, before + 1);
      expect(rows.first['entity_type'], 'task');
      expect(rows.first['operation'], 'create');
      expect(rows.first['changes_json'], contains('"field":"title"'));
      await env.close();
    });

    test('findActiveByList 按 sort_order 排序，收集箱任务 listId 为 null', () async {
      final DaoTestDb env = await DaoTestDb.open();
      final l = await env.listDao.insert(name: '工作');
      await env.taskDao.insert(title: 'b', listId: l.id, sortOrder: 2);
      await env.taskDao.insert(title: 'a', listId: l.id, sortOrder: 1);
      await env.taskDao.insert(title: 'inbox'); // 收集箱

      final inboxTasks = await env.taskDao.findActiveByList(null);
      expect(inboxTasks.map((t) => t.title), <String>['inbox']);
      final listTasks = await env.taskDao.findActiveByList(l.id);
      expect(listTasks.map((t) => t.title), <String>['a', 'b']);
      await env.close();
    });

    test('update 记字段级变更（标题+优先级同时改）', () async {
      final DaoTestDb env = await DaoTestDb.open();
      final t = await env.taskDao.insert(title: '旧标题');
      final int before = await env.opLogCount();
      await env.taskDao.update(t.copyWith(
        title: '新标题',
        priority: TaskPriority.high,
        modifiedTime: DateTime.now().toUtc(),
      ));
      final rows = await env.opLogRows();
      expect(rows.length, before + 1);
      final String changes = rows.last['changes_json']! as String;
      expect(changes, contains('"field":"title"'));
      expect(changes, contains('"field":"priority"'));
      expect(changes, contains('"old":1'));
      expect(changes, contains('"new":3'));
      await env.close();
    });

    test('回收站语义（F4）：moveToTrash 后普通查询不可见、findTrashed 可见，可恢复',
        () async {
      final DaoTestDb env = await DaoTestDb.open();
      final t = await env.taskDao.insert(title: '要删的任务');
      await env.taskDao.moveToTrash(t.id);

      expect(await env.taskDao.findById(t.id), isNotNull,
          reason: '移入回收站不是物理删除');
      expect((await env.taskDao.findAllActive()).map((x) => x.id),
          isNot(contains(t.id)));
      final trashed = await env.taskDao.findTrashed();
      expect(trashed.map((x) => x.id), contains(t.id));
      expect(trashed.first.deletedTime, isNotNull);

      // 恢复。
      final restored = trashed.first.copyWith(deleted: false, deletedTime: null);
      await env.taskDao.update(restored);
      expect((await env.taskDao.findTrashed()), isEmpty);
      expect((await env.taskDao.findAllActive()).map((x) => x.id),
          contains(t.id));
      await env.close();
    });

    test('deleteForever 物理删除 + delete op-log；子任务级联清除', () async {
      final DaoTestDb env = await DaoTestDb.open();
      final t = await env.taskDao.insert(title: '彻底删');
      await env.subtaskDao.insert(taskId: t.id, title: '步骤');
      final int before = await env.opLogCount();

      await env.taskDao.deleteForever(t.id);
      expect(await env.taskDao.findById(t.id), isNull);
      expect(await env.subtaskDao.findByTask(t.id), isEmpty);

      final rows = await env.opLogRows();
      expect(rows.length, before + 1);
      expect(rows.last['operation'], 'delete');
      expect(rows.last['changes_json'], contains('"field":"title"'));
      await env.close();
    });

    test('search（F10）：标题与备注命中、LIKE 通配符转义', () async {
      final DaoTestDb env = await DaoTestDb.open();
      await env.taskDao.insert(title: '买牛奶', note: '便利店');
      await env.taskDao.insert(title: '写报告', note: '见 100% 进度');
      await env.taskDao.insert(title: 'axb');
      await env.taskDao.insert(title: 'a_b');
      final trashed = await env.taskDao.insert(title: '草稿买牛奶');
      await env.taskDao.moveToTrash(trashed.id);

      expect((await env.taskDao.search('牛奶')).map((t) => t.title),
          <String>['买牛奶']);
      expect((await env.taskDao.search('便利店')), hasLength(1),
          reason: '备注也参与搜索');
      expect((await env.taskDao.search('100%')), hasLength(1),
          reason: '% 不应作通配符');
      expect((await env.taskDao.search('%')).map((t) => t.title),
          <String>['写报告'],
          reason: '裸 % 按字面量匹配，只命中含 % 字符的备注');
      expect((await env.taskDao.search('a_b')).map((t) => t.title),
          <String>['a_b'],
          reason: '_ 不应作通配符，不匹配 axb');
      expect(await env.taskDao.search(''), isEmpty);
      expect((await env.taskDao.search('草稿')), isEmpty, reason: '回收站任务不参与搜索');
      await env.close();
    });

    test('findCompleted 按 completed_time 倒序（F3）', () async {
      final DaoTestDb env = await DaoTestDb.open();
      final t1 = await env.taskDao.insert(title: '一');
      final t2 = await env.taskDao.insert(title: '二');
      await env.taskDao.update(t1.copyWith(
        completed: true,
        completedTime: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      ));
      await env.taskDao.update(t2.copyWith(
        completed: true,
        completedTime: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
      ));
      final completed = await env.taskDao.findCompleted();
      expect(completed.map((t) => t.title), <String>['二', '一']);
      await env.close();
    });

    test('update 不存在的任务抛 StateError', () async {
      final DaoTestDb env = await DaoTestDb.open();
      final t = await env.taskDao.insert(title: 'x');
      await env.taskDao.deleteForever(t.id);
      await expectLater(env.taskDao.update(t), throwsStateError);
      await env.close();
    });
  });
}
