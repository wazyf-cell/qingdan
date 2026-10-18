/// 双端同步测试共享夹具：真文件 IO（不用 mock / 不用内存库）。
///
/// 目录布局（每个测试一个独立临时目录，互不污染）：
/// ```
/// 临时目录/
///   cloud/       ← 云端（LocalFolderBackend 的 root）
///   device1.db   ← 设备1 本地库（磁盘文件，可反复关开、可外部读回）
///   device2.db   ← 设备2 本地库
/// ```
///
/// 为什么不能用 inMemoryDatabasePath：内存库一关即销毁，而双端测试需要
/// 从外部读回验证、并模拟「设备离线」（两次同步之间不做任何通信）。
library;

import 'dart:io';

import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/application/task_use_case.dart';
import 'package:qingdan/data/migrations.dart';
import 'package:qingdan/sync/local_folder_backend.dart';
import 'package:qingdan/sync/sync_engine.dart';
import 'package:qingdan/sync/sync_report.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'dao_test_helper.dart' show ensureSqfliteFfi;

export 'dao_test_helper.dart' show ensureSqfliteFfi;

/// 一台「设备」：独立磁盘库 + 用例层入口。
class DeviceHarness {
  DeviceHarness._(this.db)
      : services = AppServices(db: db),
        dbPath = db.path;

  final Database db;
  final AppServices services;
  final String dbPath;

  late final TaskUseCase tasks = TaskUseCase(services);

  /// 直接读某表的原始行（验证最终状态用，不经任何业务映射）。
  Future<Map<String, Object?>?> row(String table, String id) async {
    final List<Map<String, Object?>> rows = await db.query(
      table,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// 直接读 tasks 原始行。
  Future<Map<String, Object?>?> taskRow(String id) => row('tasks', id);
}

/// 整个测试环境的夹具。
class SyncTestFixture {
  SyncTestFixture._(
    this.tempDir,
    this.cloudDir,
    this.backend,
    this.device1,
    this.device2,
  );

  final Directory tempDir;
  final Directory cloudDir;
  final LocalFolderBackend backend;
  final DeviceHarness device1;
  final DeviceHarness device2;

  /// 建一个全新环境：临时目录 + cloud/ + 两台设备的磁盘库（跑全量迁移）。
  static Future<SyncTestFixture> create() async {
    ensureSqfliteFfi();
    final Directory tempDir =
        await Directory.systemTemp.createTemp('qingdan_sync_test_');
    final Directory cloudDir =
        Directory('${tempDir.path}${Platform.pathSeparator}cloud');
    cloudDir.createSync(recursive: true);
    final DeviceHarness d1 = await _openDevice(
      '${tempDir.path}${Platform.pathSeparator}device1.db',
    );
    final DeviceHarness d2 = await _openDevice(
      '${tempDir.path}${Platform.pathSeparator}device2.db',
    );
    return SyncTestFixture._(
      tempDir,
      cloudDir,
      LocalFolderBackend(cloudDir),
      d1,
      d2,
    );
  }

  /// 按既有 DAO 测试模式建库：磁盘文件 + 全量迁移 + 外键开启。
  /// 不走 openAppDatabase()，因为它内部用 path_provider（纯 Dart 测试无平台通道）。
  static Future<DeviceHarness> _openDevice(String path) async {
    final Database db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: kLatestSchemaVersion,
        onConfigure: (Database db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (Database db, int version) async {
          await runMigrations(db, fromVersion: 0, toVersion: version);
        },
      ),
    );
    return DeviceHarness._(db);
  }

  /// 设备 [n]（1 或 2）执行一次同步。
  ///
  /// ⚠️ 每次都 new 一个 SyncEngine：引擎的 SyncReport 在构造期创建、跨 sync()
  /// 累加不复位，复用实例会让「第二次同步 uploaded==0」这类断言失真。
  /// 这是有意的测试侧选择，不是实现缺陷（单次报告在单实例内是准确的）。
  Future<SyncReport> syncDevice(int n) async {
    final DeviceHarness device = n == 1 ? device1 : device2;
    final SyncEngine engine = SyncEngine(
      backend: backend,
      db: device.db,
    );
    return engine.sync();
  }

  /// 直接改某行的 modified_time（毫秒）：制造确定性的 LWW 时间差。
  /// 用例层 update() 会自动盖 now()，本机时钟毫秒可能相同，LWW 平手不可控，
  /// 所以测试里显式控制时间戳（任务书允许）。
  Future<void> forceModifiedTime(
    DeviceHarness device,
    String taskId,
    int ms,
  ) => forceRowModifiedTime(device, 'tasks', taskId, ms);

  Future<void> forceRowModifiedTime(
    DeviceHarness device,
    String table,
    String id,
    int ms,
  ) {
    return device.db.update(
      table,
      <String, Object?>{'modified_time': ms},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// dump 云端真实目录树（相对 cloud/ 的路径列表），验证 §5.2 布局。
  List<String> cloudFileTree() {
    final List<String> out = <String>[];
    if (!cloudDir.existsSync()) return out;
    for (final FileSystemEntity e
        in cloudDir.listSync(recursive: true, followLinks: false)) {
      if (e is File) {
        out.add(e.path
            .substring(cloudDir.path.length + 1)
            .replaceAll('\\', '/'));
      }
    }
    out.sort();
    return out;
  }

  /// 清理：关库 + 删临时目录。
  Future<void> dispose() async {
    await device1.db.close();
    await device2.db.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  }
}
