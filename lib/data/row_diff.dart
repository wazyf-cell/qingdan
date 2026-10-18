/// SQLite 行 Map ↔ op-log 字段级变更（F38）的换算工具。
///
/// 变更记录里的字段名用领域字段名（camelCase，如 `dueDate`），
/// 行列名是 snake_case，这里统一换算，避免 op-log 里两套命名并存。
library;

import '../domain/field_change.dart';

/// snake_case 列名 → camelCase 字段名（`due_date` → `dueDate`）。
String camelFieldName(String column) {
  final List<String> parts = column.split('_');
  if (parts.length == 1) return column;
  return parts.first +
      parts.skip(1).map((String p) {
        if (p.isEmpty) return p;
        return p[0].toUpperCase() + p.substring(1);
      }).join();
}

/// create 操作的全量字段变更：old 为 null，new 为行值。
/// 跳过主键与同步基线列（它们不是业务变更）。
List<FieldChange> createChanges(Map<String, Object?> row) => <FieldChange>[
      for (final MapEntry<String, Object?> e in row.entries)
        if (e.key != 'id' && e.key != 'last_synced_json')
          FieldChange(
              field: camelFieldName(e.key), oldValue: null, newValue: e.value),
    ];

/// update 操作的字段级差异：逐列比较前后两份行 Map。
/// 跳过主键与同步基线列；值相等的列不产生变更项。
List<FieldChange> diffRowMaps(
  Map<String, Object?> before,
  Map<String, Object?> after,
) =>
    <FieldChange>[
      for (final MapEntry<String, Object?> e in after.entries)
        if (e.key != 'id' &&
            e.key != 'last_synced_json' &&
            before[e.key] != e.value)
          FieldChange(
            field: camelFieldName(e.key),
            oldValue: before[e.key],
            newValue: e.value,
          ),
    ];
