/// 意图推导器测试 · 来源 A（op-log 物理删）与两来源合并（A 优先）。
///
/// 对应评审点名必测项 9、10。纯函数测试，无数据库；
/// 测试数据构造见 `intent_test_data.dart`。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qingdan/domain/op_log_entry.dart';
import 'package:qingdan/sync/intent_resolver.dart';

import 'intent_test_data.dart';

void main() {
  group('来源 A：resolvePhysicalDeletes（op-log 物理删）', () {
    test('9. 未上传 delete 流水 → 产出删除集合，收集全部 op-log id', () {
      final deletes = resolvePhysicalDeletes(
        entityType: 'list',
        unconsumedOpLog: [
          opLog('op1', 'delete'),
          opLog('op2', 'delete'),
        ],
      );
      expect(deletes.keys, {'e1'});
      expect(deletes['e1'], unorderedEquals(<String>['op1', 'op2']));
    });

    test('9b. 只认 delete：create/update 流水不产出；已上传流水跳过', () {
      final deletes = resolvePhysicalDeletes(
        entityType: 'list',
        unconsumedOpLog: [
          opLog('op1', 'create'),
          opLog('op2', 'update'),
          OpLogEntry(
            id: 'op3',
            entityType: 'list',
            entityId: 'e1',
            operation: 'delete',
            changesJson: '[]',
            operatedTime:
                DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
            uploaded: true,
          ),
        ],
      );
      expect(deletes, isEmpty);
    });

    test('9c. 按实体类型过滤：task 流水不影响 list 通道', () {
      final deletes = resolvePhysicalDeletes(
        entityType: 'list',
        unconsumedOpLog: [opLog('op1', 'delete', entityType: 'task')],
      );
      expect(deletes, isEmpty);
    });
  });

  group('合并：convergeIntents（A 的 delete 优先）', () {
    test('10. B 有 upsert、A 有 delete → 只留 delete（A 优先）', () {
      // 场景：任务软删（B 推出 TRASH upsert），随后又彻底删除
      // （A 有 delete 流水）——最终对远端只能做删文件，不能先 PUT 再删。
      final merged = convergeIntents(
        entityType: 'task',
        stateIntents: [
          SyncIntent(
            entityType: 'task',
            entityId: 't1',
            kind: SyncIntentKind.upsert,
            payload: const {'id': 't1', 'title': '软删但流水说彻底删'},
            resolvedFromKind: 'TRASH',
          ),
        ],
        physicalDeletes: const {
          't1': <String>['op1'],
        },
      );
      expect(merged, hasLength(1));
      expect(merged.single.kind, SyncIntentKind.delete);
      expect(merged.single.resolvedFromKind, 'DELETE');
      expect(merged.single.sourceOpLogIds, <String>['op1']);
    });

    test('10b. 两个实体互不干扰：B 产 upsert、A 产 delete 并存', () {
      final merged = convergeIntents(
        entityType: 'task',
        stateIntents: [
          SyncIntent(
            entityType: 'task',
            entityId: 't1',
            kind: SyncIntentKind.upsert,
            resolvedFromKind: 'CREATE',
          ),
        ],
        physicalDeletes: const {
          't2': <String>['op2'],
        },
      );
      expect(merged, hasLength(2));
      expect(
        {for (final i in merged) i.entityId: i.kind},
        {'t1': SyncIntentKind.upsert, 't2': SyncIntentKind.delete},
      );
    });
  });
}
