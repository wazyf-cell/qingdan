/// op-log 与未来意图表共用的字段级变更序列化工具。
///
/// 变更项格式（F38 验收要求）：`{"field":"title","old":"a","new":"b"}`，
/// create 时 `old` 为 null，delete 时 `new` 为 null。时间字段一律毫秒整数。
library;

import 'dart:convert';

/// 一条字段级变更。`oldValue`/`newValue` 必须是 JSON 可序列化标量
/// （String / int / bool / null；时间字段由调用方先转毫秒）。
class FieldChange {
  const FieldChange({required this.field, this.oldValue, this.newValue});

  final String field;
  final Object? oldValue;
  final Object? newValue;

  Map<String, Object?> toJson() => <String, Object?>{
        'field': field,
        'old': oldValue,
        'new': newValue,
      };
}

/// 把 [changes] 序列化为 op-log 的 `changes_json` 文本。
String encodeChanges(List<FieldChange> changes) =>
    jsonEncode(changes.map((FieldChange c) => c.toJson()).toList());

/// 把 op-log 的 `changes_json` 文本还原为字段级变更列表。
List<FieldChange> decodeChanges(String changesJson) => (jsonDecode(changesJson)
        as List<Object?>)
    .map((Object? item) {
      final Map<String, Object?> json = item! as Map<String, Object?>;
      return FieldChange(
        field: json['field']! as String,
        oldValue: json['old'],
        newValue: json['new'],
      );
    })
    .toList(growable: false);
