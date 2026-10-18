import 'timestamps.dart';

/// 标签（F11，P1）。
///
/// 表结构在 M1 迁移 v2 就位（避免 M2/M3 改写入路径），但 M1 不提供用例与 UI。
class Tag {
  const Tag({
    required this.id,
    required this.name,
    this.color,
    this.modifiedTime,
    this.lastSyncedJson,
  });

  final String id;
  final String name;

  /// 展示色（可空；格式由 UI 层约定，如 '#RRGGBB'）。
  final String? color;
  final DateTime? modifiedTime;
  final String? lastSyncedJson;

  Tag copyWith({
    String? name,
    String? color,
    DateTime? modifiedTime,
    String? lastSyncedJson,
  }) =>
      Tag(
        id: id,
        name: name ?? this.name,
        color: color ?? this.color,
        modifiedTime: modifiedTime ?? this.modifiedTime,
        lastSyncedJson: lastSyncedJson ?? this.lastSyncedJson,
      );

  factory Tag.fromMap(Map<String, Object?> map) => Tag(
        id: map['id']! as String,
        name: map['name']! as String,
        color: map['color'] as String?,
        modifiedTime: msToDateTime(map['modified_time'] as int?),
        lastSyncedJson: map['last_synced_json'] as String?,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'name': name,
        'color': color,
        'modified_time': dateTimeToMs(modifiedTime),
        'last_synced_json': lastSyncedJson,
      };

  factory Tag.fromJson(Map<String, Object?> json) => Tag(
        id: json['id']! as String,
        name: json['name']! as String,
        color: json['color'] as String?,
        modifiedTime: msToDateTime(json['modifiedTime'] as int?),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'color': color,
        'modifiedTime': dateTimeToMs(modifiedTime),
      };
}

/// 任务 ↔ 标签关联（多对多）。复合主键 (task_id, tag_id)，无独立 id。
class TaskTag {
  const TaskTag({required this.taskId, required this.tagId});

  final String taskId;
  final String tagId;

  factory TaskTag.fromMap(Map<String, Object?> map) => TaskTag(
        taskId: map['task_id']! as String,
        tagId: map['tag_id']! as String,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'task_id': taskId,
        'tag_id': tagId,
      };
}
