/// 三路合并引擎表驱动测试（方案设计 §5.4；边界思想移植自 TickTick
/// `TaskMergeUtils` 的三类分支覆盖：一致 / 单侧改 / 双侧改）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qingdan/sync/merge_engine.dart';

/// 构造一份任务实体 JSON（字段取自 `Task.toJson`，UTC 毫秒时间戳）。
Map<String, Object?> task({
  String id = 't1',
  String title = '标题',
  String note = '备注',
  int priority = 0,
  bool deleted = false,
  int modifiedTime = 1000,
  int rev = 1,
  String deviceId = 'deviceA',
  List<Object?>? tags,
}) =>
    <String, Object?>{
      'id': id,
      'title': title,
      'note': note,
      'priority': priority,
      'deleted': deleted,
      'modifiedTime': modifiedTime,
      'rev': rev,
      'deviceId': deviceId,
      'tags': ?tags,
    };

/// 一条表驱动用例：输入三方 + 期望的结果类型 / 关键合并值 / 冲突字段。
class _Case {
  const _Case(
    this.name, {
    required this.current,
    required this.remote,
    this.base,
    this.setFields,
    this.additiveFields,
    this.ignoredFields,
    required this.expectType,
    this.expectMerged = const <String, Object?>{},
    this.expectConflicts = const <String>[],
  });

  final String name;
  final Map<String, Object?> current;
  final Map<String, Object?> remote;
  final Map<String, Object?>? base;
  final Set<String>? setFields;
  final Set<String>? additiveFields;
  final Set<String>? ignoredFields;
  final MergeOutcomeType expectType;
  final Map<String, Object?> expectMerged;
  final List<String> expectConflicts;
}

final List<_Case> _kCases = <_Case>[
  // ---- 四个基本分支 ----
  _Case('基本1 remote==current：双方一致，无需上传',
      current: task(title: '相同'),
      remote: task(title: '相同', rev: 9, deviceId: 'deviceB'),
      base: task(title: '基线'),
      expectType: MergeOutcomeType.unchanged),
  _Case('基本2 base==current：本地未改，取远端',
      current: task(title: '基线'),
      remote: task(title: '远端改过', deviceId: 'deviceB'),
      base: task(title: '基线'),
      expectType: MergeOutcomeType.takeRemote,
      expectMerged: <String, Object?>{'title': '远端改过'}),
  _Case('基本3 base==remote：远端未改，取本地',
      current: task(title: '本地改过'),
      remote: task(title: '基线', deviceId: 'deviceB'),
      base: task(title: '基线'),
      expectType: MergeOutcomeType.takeLocal,
      expectMerged: <String, Object?>{'title': '本地改过'}),
  _Case('基本4 三者互不相等且本地新：LWW 本地胜',
      current: task(title: '本地新', modifiedTime: 2000),
      remote: task(title: '远端旧', modifiedTime: 1000, deviceId: 'deviceB'),
      base: task(title: '基线'),
      expectType: MergeOutcomeType.takeLocal,
      expectConflicts: <String>['title'],
      expectMerged: <String, Object?>{'title': '本地新'}),
  _Case('基本5 三者互不相等且远端新：LWW 远端胜',
      current: task(title: '本地旧', modifiedTime: 1000),
      remote: task(title: '远端新', modifiedTime: 2000, deviceId: 'deviceB'),
      base: task(title: '基线'),
      expectType: MergeOutcomeType.takeRemote,
      expectConflicts: <String>['title'],
      expectMerged: <String, Object?>{'title': '远端新'}),

  // ---- ★ base == null 退化路径（M2 上线唯一真实路径）----
  _Case('退化1 base==null 且双方不一致：本地权威',
      current: task(title: '本地内容'),
      remote: task(title: '远端内容', deviceId: 'deviceB'),
      expectType: MergeOutcomeType.takeLocal,
      expectMerged: <String, Object?>{'title': '本地内容'}),
  _Case('退化2 base==null 且双方一致：unchanged',
      current: task(title: '相同'),
      remote: task(title: '相同', deviceId: 'deviceB'),
      expectType: MergeOutcomeType.unchanged),

  // ---- 多字段部分冲突：A3 存在的理由 ----
  _Case('部分冲突：本地改 title、远端改 priority，两个改动都保留',
      current: task(title: '本地改的标题', modifiedTime: 2000),
      remote: task(title: '基线标题', priority: 2, deviceId: 'deviceB',
          modifiedTime: 1500),
      base: task(title: '基线标题'),
      expectType: MergeOutcomeType.merged,
      expectConflicts: <String>[],
      expectMerged: <String, Object?>{'title': '本地改的标题', 'priority': 2}),

  // ---- 死循环防护：rev / deviceId / sortOrder 变化不影响结论 ----
  _Case('死循环防护：仅 rev/deviceId/sortOrder 不同 → unchanged',
      current: task(title: '相同', rev: 1, deviceId: 'deviceA'),
      remote: task(title: '相同', rev: 99, deviceId: 'deviceB'),
      expectType: MergeOutcomeType.unchanged),
  _Case('死循环防护：业务字段合并时元字段差异不产生冲突项',
      current: task(title: '本地新', modifiedTime: 2000),
      remote: task(title: '远端旧', modifiedTime: 1000, rev: 42,
          deviceId: 'deviceB'),
      base: task(title: '基线'),
      expectConflicts: <String>['title'],
      expectType: MergeOutcomeType.takeLocal),

  // ---- 集合型（标签）：并集 ----
  _Case('集合：双方各自新增 → 并集',
      current: task(tags: <Object?>['工作']),
      remote: task(tags: <Object?>['紧急'], deviceId: 'deviceB'),
      base: task(tags: <Object?>[]),
      setFields: <String>{'tags'},
      expectType: MergeOutcomeType.merged,
      expectMerged: <String, Object?>{
        'tags': <Object?>['工作', '紧急']
      }),
  _Case('集合：双方都删 → 真删',
      current: task(tags: <Object?>['剩下的']),
      remote: task(tags: <Object?>['剩下的'], deviceId: 'deviceB'),
      base: task(tags: <Object?>['剩下的', '都被删的']),
      setFields: <String>{'tags'},
      expectType: MergeOutcomeType.unchanged,
      expectMerged: <String, Object?>{
        'tags': <Object?>['剩下的']
      }),
  _Case('集合：一方删一方留 → 保留',
      current: task(tags: <Object?>['留下的', '被远端删的']),
      remote: task(tags: <Object?>['留下的'], deviceId: 'deviceB'),
      base: task(tags: <Object?>['留下的', '被远端删的']),
      setFields: <String>{'tags'},
      expectType: MergeOutcomeType.takeLocal,
      expectMerged: <String, Object?>{
        'tags': <Object?>['留下的', '被远端删的']
      }),

  // ---- 累加型（当前无调用方，为 M5 番茄钟/习惯预留）----
  // 注：期望值直接写在构造参数里——expectMerged 的默认值是 const map，
  // 不能在级联里 addAll（运行期 unmodifiable）。
  _Case('累加：两端各 +1 → +2 而不是 +1',
      current: task()..['pomoCount'] = 6,
      remote: task()..['pomoCount'] = 6,
      base: task()..['pomoCount'] = 5,
      additiveFields: <String>{'pomoCount'},
      expectType: MergeOutcomeType.merged,
      expectMerged: <String, Object?>{'pomoCount': 7}),
  _Case('累加：两端各 +1（值不同）→ remote+current-base',
      current: task()..['pomoCount'] = 11,
      remote: task()..['pomoCount'] = 12,
      base: task()..['pomoCount'] = 10,
      additiveFields: <String>{'pomoCount'},
      expectType: MergeOutcomeType.merged,
      expectMerged: <String, Object?>{'pomoCount': 13}),

  // ---- 新增 / 缺失字段 ----
  _Case('键处理：远端新增键、本地没有 → 取远端',
      current: task(),
      remote: task()..['dueDate'] = 1700000000000,
      base: task(),
      expectType: MergeOutcomeType.takeRemote,
      expectMerged: <String, Object?>{'dueDate': 1700000000000}),
  _Case('键处理：远端删除键（base 有、remote 无）→ 跟随删除',
      current: task(),
      remote: task()..remove('note'),
      base: task(),
      expectType: MergeOutcomeType.takeRemote,
      expectMerged: <String, Object?>{'note': null}),
  _Case('键处理：本地新增键、远端没有 → 保留本地',
      current: task()..['dueDate'] = 1700000000000,
      remote: task(deviceId: 'deviceB'),
      base: task(),
      expectType: MergeOutcomeType.takeLocal),

  // ---- 空输入 / 全等 ----
  _Case('空输入：三方全空 → unchanged',
      current: task(),
      remote: task(deviceId: 'deviceB'),
      base: task(),
      expectType: MergeOutcomeType.unchanged),
  _Case('全等输入 → unchanged',
      current: task(),
      remote: task(),
      base: task(),
      expectType: MergeOutcomeType.unchanged),

  // ---- ignoredFields 追加参数 ----
  _Case('ignoredFields：追加忽略的字段不参与判定，取本地值',
      current: task()..['extra'] = '本地值',
      remote: task(deviceId: 'deviceB')..['extra'] = '远端值',
      base: task(),
      ignoredFields: <String>{'extra'},
      expectType: MergeOutcomeType.unchanged,
      expectMerged: <String, Object?>{'extra': '本地值'}),
];

void main() {
  for (final _Case c in _kCases) {
    test(c.name, () {
      final MergeResult r = mergeEntity(
        current: c.current,
        remote: c.remote,
        base: c.base,
        setFields: c.setFields,
        additiveFields: c.additiveFields,
        ignoredFields: c.ignoredFields,
      );
      expect(r.type, c.expectType, reason: '结果类型不符');
      for (final MapEntry<String, Object?> e in c.expectMerged.entries) {
        expect(r.merged[e.key], e.value, reason: '字段 ${e.key} 合并值不符');
      }
      expect(r.conflictedFields, c.expectConflicts, reason: '冲突字段列表不符');
    });
  }
}
