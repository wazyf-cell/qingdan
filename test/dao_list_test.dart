import 'package:flutter_test/flutter_test.dart';

import 'dao_test_helper.dart';

void main() {
  ensureSqfliteFfi();

  group('TaskListDao', () {
    test('insert → findAll → findById → update → delete 全链路', () async {
      final DaoTestDb env = await DaoTestDb.open();
      final int before = await env.opLogCount();
      final l1 = await env.listDao.insert(name: '工作', sortOrder: 2);
      final l2 = await env.listDao.insert(name: '生活', sortOrder: 1);

      expect(l1.id, isNotEmpty);
      expect(l1.createdTime, isNotNull);

      // 排序：sort_order 升序，同序按名称。
      final List lists = await env.listDao.findAll();
      expect(lists.map((l) => l.name), <String>['生活', '工作']);

      expect((await env.listDao.findById(l1.id))!.name, '工作');
      expect(await env.listDao.findById('nope'), isNull);

      // 重命名 → 字段级 update op-log。
      await env.listDao.update(l1.copyWith(name: '工作事项'));
      expect((await env.listDao.findById(l1.id))!.name, '工作事项');

      final List<Map<String, Object?>> rows = await env.opLogRows();
      expect(rows.length, before + 3); // create×2 + update（delete 在下一句）
      final Map<String, Object?> updateRow = rows[2];
      expect(updateRow['entity_type'], 'list');
      expect(updateRow['operation'], 'update');
      expect(updateRow['changes_json'], contains('"field":"name"'));
      expect(updateRow['changes_json'], contains('"old":"工作"'));
      expect(updateRow['changes_json'], contains('"new":"工作事项"'));

      await env.listDao.delete(l2.id);
      expect(await env.listDao.findById(l2.id), isNull);
      final Map<String, Object?> deleteRow = (await env.opLogRows()).last;
      expect(deleteRow['operation'], 'delete');
      expect((deleteRow['uploaded'] as int), 0);
      await env.close();
    });

    test('update 不存在的清单抛 StateError', () async {
      final DaoTestDb env = await DaoTestDb.open();
      final l = await env.listDao.insert(name: 'x');
      await env.listDao.delete(l.id);
      await expectLater(env.listDao.update(l), throwsStateError);
      await env.close();
    });
  });
}
