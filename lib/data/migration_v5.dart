import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

// 迁移 v5：time_details 补 created_time / modified_time。
//
// 搬家说明（M6-D §2.1）：原定义在 `course_tables.dart` 尾部，现拆到独立
// 文件；**DDL 一字未改**。

/// 迁移 v5：给 `time_details` 补两列时间戳。
///
/// 为什么必须有：字段级 LWW 比较的是**行上的** `modified_time`。缺列时
/// `_remoteNewer` 恒为 false → 恒判本地胜 → 同一节被两端各改一次时，**胜者
/// 由谁后推送决定，而不是谁编辑得晚**（两端照样收敛，只是可能收敛到那条更早
/// 的编辑，新值被静默覆盖）。判别用例见
/// `test/sync_two_device_course_test.dart` 的「编辑时间新的那份赢」。
/// 迁移只增不改，所以 v4 的建表 DDL 原样保留，新库靠这条 ALTER 补齐。
Future<void> addTimeDetailTimestamps(DatabaseExecutor db) async {
  await db.execute(
      'ALTER TABLE time_details ADD COLUMN created_time INTEGER');
  await db.execute(
      'ALTER TABLE time_details ADD COLUMN modified_time INTEGER');
}
