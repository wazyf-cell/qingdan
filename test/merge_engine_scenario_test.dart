/// 端到端合并场景测试（纯函数，无数据库）：直接映射成功标准第 2 条——
/// 「不同字段都保留、同字段取新」。场景语义见各 test 的注释。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qingdan/sync/merge_engine.dart';

const Set<String> _kTags = <String>{'tags'};

/// 场景 A：设备1 离线改标题，设备2 离线改优先级，随后同步。
/// 期望：两个改动都保留（这是 A3 方案存在的理由）。
void main() {
  test('场景A：离线改动不同字段 → 两个改动都保留', () {
    final Map<String, Object?> base = <String, Object?>{
      'id': 't1',
      'title': '写周报',
      'priority': 0,
      'modifiedTime': 1000,
      'rev': 1,
      'deviceId': 'device1',
    };
    // 设备1 本地：改标题（modifiedTime 刷新为实体级时间戳）。
    final Map<String, Object?> current = <String, Object?>{
      ...base,
      'title': '写本月周报',
      'modifiedTime': 2000,
    };
    // 设备2 远端：改优先级。
    final Map<String, Object?> remote = <String, Object?>{
      ...base,
      'priority': 3,
      'modifiedTime': 1500,
      'rev': 1,
      'deviceId': 'device2',
    };

    final MergeResult r = mergeEntity(
        current: current, remote: remote, base: base);

    expect(r.type, MergeOutcomeType.merged);
    expect(r.merged['title'], '写本月周报', reason: '本地改动必须保留');
    expect(r.merged['priority'], 3, reason: '远端改动必须保留');
    expect(r.conflictedFields, isEmpty, reason: '字段不重叠，无真冲突');
  });

  test('场景B：两端同时改同一字段 → modifiedTime 较新者胜，'
      '败方值以「实体快照留在 tombstones」归档（归档由调用方执行，见下注释）', () {
    final Map<String, Object?> base = <String, Object?>{
      'id': 't1',
      'title': '买菜',
      'modifiedTime': 1000,
      'rev': 1,
      'deviceId': 'device1',
    };
    // 设备1 在 10:05 把标题改成「买菜+水果」。
    final Map<String, Object?> current = <String, Object?>{
      ...base,
      'title': '买菜+水果',
      'modifiedTime': 3000,
    };
    // 设备2 在 10:03 把标题改成「买菜+牛奶」（更早）。
    final Map<String, Object?> remote = <String, Object?>{
      ...base,
      'title': '买菜+牛奶',
      'modifiedTime': 2000,
      'rev': 1,
      'deviceId': 'device2',
    };

    final MergeResult r = mergeEntity(
        current: current, remote: remote, base: base);

    // LWW：本地（3000）比远端（2000）新 → 本地胜。
    expect(r.type, MergeOutcomeType.takeLocal);
    expect(r.merged['title'], '买菜+水果');
    expect(r.conflictedFields, <String>['title']);
    // 败方（「买菜+牛奶」）不靠合并引擎保存：按方案设计 §5.4 不变式，任何覆盖
    // 发生前调用方先把败方实体快照归档到 tombstones/<id>.<时间戳>.json——
    // 本引擎只输出「谁胜、merged 是什么」，归档是同步流程的职责，故此处不断言。
  });

  test('场景C：一端把任务移入回收站，另一端改标题 → 删除与内容改动都保留，'
      '任务以「已删除但带新标题」的状态收敛', () {
    final Map<String, Object?> base = <String, Object?>{
      'id': 't1',
      'title': '旧标题',
      'deleted': false,
      'deletedTime': null,
      'modifiedTime': 1000,
      'rev': 1,
      'deviceId': 'device1',
    };
    // 设备1：把任务移入回收站（deleted 是普通布尔字段，走 LWW）。
    final Map<String, Object?> current = <String, Object?>{
      ...base,
      'deleted': true,
      'deletedTime': 2500,
      'modifiedTime': 2500,
    };
    // 设备2：改了标题（远端未见过删除操作）。
    final Map<String, Object?> remote = <String, Object?>{
      ...base,
      'title': '新标题',
      'modifiedTime': 2000,
      'rev': 1,
      'deviceId': 'device2',
    };

    final MergeResult r = mergeEntity(
        current: current, remote: remote, base: base);

    expect(r.type, MergeOutcomeType.merged);
    expect(r.merged['deleted'], true, reason: '本地的删除意图必须生效');
    expect(r.merged['title'], '新标题', reason: '远端的内容改动也保留，不丢字');
    expect(r.conflictedFields, isEmpty);
    // 取舍理由：本项目「删除」是回收站语义（§5.4：删除走普通实体同步），
    // 不是需要仲裁的终端状态；删除方与编辑方改的字段不重叠，按字段级合并
    // 自然得出「删着但标题是新的」。用户在回收站还原后看到新标题，两端一致。
    // 若将来要「删除优先于编辑」的产品语义，应作为独立规则加在调用方，而非
    // 让合并引擎对 deleted 字段特殊裁决——引擎保持通用。
  });

  test('场景D（补充）：两端同时在两份离线数据上各加一个标签 → 并集', () {
    final Map<String, Object?> base = <String, Object?>{
      'id': 't1',
      'tags': <Object?>['工作'],
      'modifiedTime': 1000,
      'rev': 1,
      'deviceId': 'device1',
    };
    final Map<String, Object?> current = <String, Object?>{
      ...base,
      'tags': <Object?>['工作', '今天'],
      'modifiedTime': 2000,
    };
    final Map<String, Object?> remote = <String, Object?>{
      ...base,
      'tags': <Object?>['工作', '紧急'],
      'modifiedTime': 1500,
      'rev': 1,
      'deviceId': 'device2',
    };

    final MergeResult r = mergeEntity(
        current: current, remote: remote, base: base, setFields: _kTags);

    expect(r.type, MergeOutcomeType.merged);
    expect(r.merged['tags'], <Object?>['工作', '今天', '紧急'],
        reason: '双方各自新增的标签都要保留');
  });
}
