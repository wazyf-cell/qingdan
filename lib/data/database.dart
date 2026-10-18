import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'migrations.dart';

/// 应用数据库的连接、路径解析与版本化迁移入口。
///
/// 路径策略（关键约束）：sqflite_common_ffi 的默认 inMemory/临时路径会落在
/// `.dart_tool\` 下，清构建产物即丢用户数据。因此这里**显式**用
/// path_provider 解析应用数据目录（Windows 上为
/// `%APPDATA%\<org>\<app>\`，即 getApplicationSupportDirectory），
/// 并在打开前确保目录存在。
Future<String> resolveDatabasePath() async {
  final Directory base = await getApplicationSupportDirectory();
  await base.create(recursive: true);
  return '${base.path}${Platform.pathSeparator}qingdan.db';
}

/// 打开（或升级）应用数据库。
///
/// - `onConfigure` 阶段开启 `PRAGMA foreign_keys = ON`
///   （SQLite 默认关闭外键约束，必须在任何事务前设置）；
/// - 版本化迁移由 [kMigrations] 驱动：新建库从 0 连续执行到最新版本，
///   旧库只执行 `(from, to]` 区间内的迁移，每条迁移包在独立事务里。
Future<Database> openAppDatabase() async {
  sqfliteFfiInit();
  final String path = await resolveDatabasePath();

  return databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: kLatestSchemaVersion,
      onConfigure: (Database db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (Database db, int version) async {
        await runMigrations(db, fromVersion: 0, toVersion: version);
      },
      onUpgrade: (Database db, int from, int to) async {
        await runMigrations(db, fromVersion: from, toVersion: to);
      },
    ),
  );
}
