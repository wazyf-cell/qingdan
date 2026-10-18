import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import '../domain/ids.dart';

/// 本设备标识：一次生成、持久化进 `_meta`、跨重启稳定。
///
/// ⚠️ 不能用 `IdGenerator.next()` 现算：它每次调用都返回新值
/// （时间戳 + 计数器 + 随机数），拿它当 device_id 会导致同一设备的
/// 每条基线看起来来自不同设备，并发检测（rev + device_id）彻底失效。
///
/// 用法：同步引擎启动时调用一次 [ensureDeviceId]，之后每次写基线
/// 都读同一值。只在 `_meta` 无 `device_id` 键时才生成新 id；
/// 生成与写入包在同一事务里，避免并发双开时写出两个不同值。
class DeviceId {
  DeviceId._();

  static const String _metaKey = 'device_id';

  /// 读取已持久化的 device_id；不存在则生成并落库。
  /// [db] 通常是已打开的应用数据库连接。
  static Future<String> ensureDeviceId(Database db) async {
    final List<Map<String, Object?>> rows = await db.query(
      '_meta',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[_metaKey],
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.first['value']! as String;

    final String generated = IdGenerator.next();
    // 事务 + 二次检查：两个进程/连接同时冷启动时只保留一个值。
    await db.transaction((Transaction txn) async {
      final List<Map<String, Object?>> again = await txn.query(
        '_meta',
        columns: <String>['value'],
        where: 'key = ?',
        whereArgs: <Object?>[_metaKey],
        limit: 1,
      );
      if (again.isNotEmpty) return;
      await txn.insert('_meta', <String, Object?>{'key': _metaKey, 'value': generated});
    });
    // 若事务里发现已有人写入，返回持久化值而非本次生成值。
    final List<Map<String, Object?>> finalRows = await db.query(
      '_meta',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[_metaKey],
      limit: 1,
    );
    return finalRows.first['value']! as String;
  }
}
