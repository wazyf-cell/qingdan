import 'timestamps.dart';

/// 清单（F6）。
///
/// 纯数据类。`id` 为 TEXT 主键、应用生成（跨端同步要求 id 稳定）。
/// F7 的清单文件夹（folderId）属 P1，M1 不建列、不建模，后续版本迁移追加。
class TaskList {
  const TaskList({
    required this.id,
    required this.name,
    this.sortOrder = 0,
    this.createdTime,
    this.modifiedTime,
    this.lastSyncedJson,
  });

  final String id;

  /// 清单名；「收集箱」为内置清单（seed 行，应用不可删除）。
  final String name;
  final int sortOrder;
  final DateTime? createdTime;
  final DateTime? modifiedTime;

  /// 上次同步成功时的快照 JSON（三路合并 base）。
  final String? lastSyncedJson;

  TaskList copyWith({
    String? name,
    int? sortOrder,
    DateTime? modifiedTime,
    String? lastSyncedJson,
  }) =>
      TaskList(
        id: id,
        name: name ?? this.name,
        sortOrder: sortOrder ?? this.sortOrder,
        createdTime: createdTime,
        modifiedTime: modifiedTime ?? this.modifiedTime,
        lastSyncedJson: lastSyncedJson ?? this.lastSyncedJson,
      );

  factory TaskList.fromMap(Map<String, Object?> map) => TaskList(
        id: map['id']! as String,
        name: map['name']! as String,
        sortOrder: (map['sort_order'] ?? 0) as int,
        createdTime: msToDateTime(map['created_time'] as int?),
        modifiedTime: msToDateTime(map['modified_time'] as int?),
        lastSyncedJson: map['last_synced_json'] as String?,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'name': name,
        'sort_order': sortOrder,
        'created_time': dateTimeToMs(createdTime),
        'modified_time': dateTimeToMs(modifiedTime),
        'last_synced_json': lastSyncedJson,
      };

  factory TaskList.fromJson(Map<String, Object?> json) => TaskList(
        id: json['id']! as String,
        name: json['name']! as String,
        sortOrder: (json['sortOrder'] ?? 0) as int,
        createdTime: msToDateTime(json['createdTime'] as int?),
        modifiedTime: msToDateTime(json['modifiedTime'] as int?),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'sortOrder': sortOrder,
        'createdTime': dateTimeToMs(createdTime),
        'modifiedTime': dateTimeToMs(modifiedTime),
      };
}
