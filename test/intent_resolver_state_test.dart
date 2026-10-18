/// 意图推导器测试 · 来源 B（base vs current 终态 diff）。
///
/// 对应方案设计 §三 六态规格与评审点名的必测项 1–8、11、12。
/// 纯函数测试，无数据库；测试数据构造见 `intent_test_data.dart`。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qingdan/sync/intent_resolver.dart';

import 'intent_test_data.dart';

void main() {
  group('来源 B：resolveFromState（base vs current 终态 diff）', () {
    test('1. base 为 null + 实体存在 → CREATE', () {
      final intents = resolveFromState(
        entityType: 'task',
        currentRows: {'t1': taskRow(id: 't1')},
        baseJsonByEntityId: const {'t1': null},
      );
      expect(intents, hasLength(1));
      expect(intents.single.resolvedFromKind, 'CREATE');
      expect(intents.single.kind, SyncIntentKind.upsert);
      expect(intents.single.payload!['id'], 't1');
    });

    test('2. 字段变化（改名）→ CONTENT，payload 为完整终态 JSON', () {
      final intents = resolveFromState(
        entityType: 'task',
        currentRows:
            {'t1': taskRow(id: 't1', title: '新名', modifiedTime: 2000)},
        baseJsonByEntityId: {'t1': baseJson()},
      );
      expect(intents.single.resolvedFromKind, 'CONTENT');
      expect(intents.single.payload!['title'], '新名');
    });

    test('3. 进回收站 → 恢复：TRASH 与 RESTORE 免费抵消，不产生意图', () {
      // base 即「未删」终态；经历 deleted 1 再回到 0、deletedTime 回 null
      // —— current 与 base 逐字段相等，diff 为空（终态快照对的免费抵消）。
      final intents = resolveFromState(
        entityType: 'task',
        currentRows: {'t1': taskRow(id: 't1')},
        baseJsonByEntityId: {'t1': baseJson()},
      );
      expect(intents, isEmpty);
    });

    test('4. 反复改优先级 A→B→A：diff 只剩终值，不产生意图', () {
      final intents = resolveFromState(
        entityType: 'task',
        currentRows: {'t1': taskRow(id: 't1', priority: 0)},
        baseJsonByEntityId: {'t1': baseJson({'priority': 0})},
      );
      expect(intents, isEmpty);
    });

    test('5. 创建 → 改名 → 删进回收站：一次 diff 得 TRASH 终态', () {
      final intents = resolveFromState(
        entityType: 'task',
        currentRows: {
          't1': taskRow(
            id: 't1',
            title: '改名后的任务',
            deleted: 1,
            deletedTime: 3000,
            modifiedTime: 3000,
          ),
        },
        baseJsonByEntityId: {'t1': baseJson()},
      );
      expect(intents, hasLength(1));
      expect(intents.single.resolvedFromKind, 'TRASH');
      expect(intents.single.payload!['deleted'], 1);
      expect(intents.single.payload!['title'], '改名后的任务');
    });

    test('6. TRASH 与 RESTORE 分别判定正确', () {
      final trash = resolveFromState(
        entityType: 'task',
        currentRows:
            {'t1': taskRow(id: 't1', deleted: 1, deletedTime: 2000)},
        baseJsonByEntityId: {'t1': baseJson()},
      );
      expect(trash.single.resolvedFromKind, 'TRASH');

      final restore = resolveFromState(
        entityType: 'task',
        currentRows: {'t1': taskRow(id: 't1', modifiedTime: 2000)},
        baseJsonByEntityId: {
          't1': baseJson({'deleted': 1, 'deletedTime': 1500}),
        },
      );
      expect(restore.single.resolvedFromKind, 'RESTORE');
    });

    test('7. listId 变化 → MOVE', () {
      final intents = resolveFromState(
        entityType: 'task',
        currentRows: {'t1': taskRow(id: 't1', listId: 'list-2')},
        baseJsonByEntityId: {'t1': baseJson()},
      );
      expect(intents.single.resolvedFromKind, 'MOVE');
    });

    test('8. 多字段同时变化（title+priority+completed）→ 只产出一条意图', () {
      final intents = resolveFromState(
        entityType: 'task',
        currentRows: {
          't1': taskRow(
            id: 't1',
            title: '改了',
            priority: 2,
            completed: 1,
            completedTime: 2500,
            modifiedTime: 2500,
          ),
        },
        baseJsonByEntityId: {'t1': baseJson()},
      );
      expect(intents, hasLength(1));
      expect(intents.single.resolvedFromKind, 'CONTENT');
      expect(intents.single.payload!['title'], '改了');
      expect(intents.single.payload!['priority'], 2);
      expect(intents.single.payload!['completed'], 1);
    });

    test('11. rev/deviceId/sortOrder 变化不触发任何意图（死循环防护）', () {
      final intents = resolveFromState(
        entityType: 'task',
        currentRows: {
          't1': taskRow(
            id: 't1',
            sortOrder: 99, // §5.3：sort_order 从同步 JSON 排除
          ),
        },
        baseJsonByEntityId: {'t1': baseJson()},
      );
      expect(intents, isEmpty);
    });

    test('11b. payload 不含 rev/deviceId/sortOrder/lastSyncedJson', () {
      final intents = resolveFromState(
        entityType: 'task',
        currentRows:
            {'t1': taskRow(id: 't1', title: '新', modifiedTime: 2000)},
        baseJsonByEntityId: {'t1': baseJson()},
      );
      final payload = intents.single.payload!;
      for (final String forbidden in const <String>[
        'rev',
        'deviceId',
        'device_id',
        'sortOrder',
        'sort_order',
        'lastSyncedJson',
        'last_synced_json',
      ]) {
        expect(payload.keys, isNot(contains(forbidden)),
            reason: 'payload 不应含 $forbidden');
      }
    });

    test('12. 空输入 → 空输出', () {
      expect(
        resolveFromState(
          entityType: 'task',
          currentRows: const {},
          baseJsonByEntityId: const {},
        ),
        isEmpty,
      );
    });

    test('附：current 不存在 + base 存在 → B 不产出 delete（物理删归 A）', () {
      // currentRows 里没有 t1（物理删后 DAO 查不到），B 不得凭空产意图。
      final intents = resolveFromState(
        entityType: 'task',
        currentRows: const {},
        baseJsonByEntityId: {'t1': baseJson()},
      );
      expect(intents, isEmpty);
    });
  });
}
