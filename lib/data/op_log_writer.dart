import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import '../domain/field_change.dart';
import '../domain/ids.dart';
import '../domain/op_log_entry.dart';

/// 「写实体 + 记 op-log」的统一执行器（F38）。
///
/// 所有 DAO 的写方法都经由本类，保证：
/// - 写实体与写 op-log 在**同一事务**里（AGENTS.md 铁律：用例层内
///   「写库 + 记待同步意图」必须在同一事务中；M1 以 op-log 承担该职责）；
/// - 事务由调用方（DAO）持有并提交/回滚，本类只负责在一个已存在的
///   事务上下文里追加 op-log 行（[append] 接收事务/连接执行器）。
class OpLogWriter {
  /// [onLocalWrite] 是 M3 同步触发源（设计稿 §2.1）：append 末尾回调，
  /// 回调里**只置内存脏标记，不做任何 IO**。挂在 op-log 这一层而非用例层，
  /// 是因为 op-log 是全项目本地写的唯一汇聚点，新增写路径自动覆盖。
  const OpLogWriter({this.onLocalWrite});

  /// 本地写发生后的通知（可为 null = 无订阅者）。
  final void Function()? onLocalWrite;

  /// 在调用方的活动事务/连接上追加一条 op-log 记录。
  ///
  /// 不自己开事务——事务边界归 DAO 的写方法管理，本方法只 INSERT。
  Future<void> append(
    DatabaseExecutor txn, {
    required OpLogEntityType entityType,
    required String entityId,
    required OpLogOperation operation,
    required List<FieldChange> changes,
    DateTime? operatedTime,
  }) async {
    final OpLogEntry entry = OpLogEntry(
      id: IdGenerator.next(),
      entityType: entityType.value,
      entityId: entityId,
      operation: operation.value,
      changesJson: encodeChanges(changes),
      operatedTime: operatedTime ?? DateTime.now().toUtc(),
    );
    await txn.insert('op_log', entry.toMap());
    // 事务提交前触发：回调只置内存计时，防抖窗口（2s）远大于事务毫秒级
    // 耗时，故实际无竞态；事务若回滚只多一次近乎空转的同步，有意接受。
    onLocalWrite?.call();
  }
}
