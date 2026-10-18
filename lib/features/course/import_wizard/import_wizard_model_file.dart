// 导入向导模型 · 步 1（文件）与步 2（列映射）的状态（§十二.2 从
// `import_wizard_model.dart` 按职责搬出：332 行触 300 红线，搬家不改行为，
// 方法体与文案与原文件逐字一致）。

import 'package:flutter/foundation.dart';

import 'package:qingdan/import/course/column_mapping.dart';
import 'package:qingdan/import/course/schedule_file.dart';
import 'package:qingdan/import/course/wakeup_schedule_file.dart';

/// 步 1 / 步 2：字节 → 表 → 列映射。IO 边界在外壳（文件由步 1 的壳读好递进来）。
mixin WizardFileSteps on ChangeNotifier {
  String? fileError;

  // ---- 步 1 ----
  String? fileName;
  Uint8List? _bytes;
  ScheduleTable? _table;

  /// WakeUp 导出顺带带的学期与作息（其它来源为 null）。步 3 用它**预填 +
  /// 用户点「采纳」才写**，不静默覆盖已有学期。
  WakeupMeta? wakeupMeta;

  // ---- 步 2 ----
  ColumnMapping? mapping;

  bool get hasFile => _table != null;
  ScheduleTable? get table => _table;

  // ================= 步 1：文件 =================

  /// [fileName] 只作展示与真实类型提示，**判类型看字节**（用户常改扩展名）。
  void loadFile({required String fileName, required Uint8List bytes}) {
    this.fileName = fileName;
    _bytes = bytes;
    fileError = null;
    wakeupMeta = isWakeupSchedule(bytes) ? readWakeupMeta(bytes) : null;
    try {
      final ScheduleTable t = readScheduleTable(bytes, fileName: fileName);
      if (t.isEmpty) {
        fileError = '文件里没有任何数据行';
        _table = null;
      } else {
        _table = t;
      }
    } on ScheduleFileException catch (e) {
      fileError = e.message;
      _table = null;
    }
    notifyListeners();
  }

  /// 已经解析好的表（教务系统抓取那条链）：跳过「字节 → 表」这一步，
  /// 从列映射开始走同一条向导，校正与三模式落库完全复用。
  void loadTable({required String fileName, required ScheduleTable table}) {
    this.fileName = fileName;
    _bytes = null;
    fileError = null;
    if (table.isEmpty) {
      fileError = '抓取结果里没有数据行';
      _table = null;
    } else {
      _table = table;
    }
    notifyListeners();
  }

  /// 界面上手动切换编码重读（§3.1:162「允许手动切换重读」）。
  void reloadWith(FileEncoding encoding) {
    final Uint8List? bytes = _bytes;
    if (bytes == null) return;
    try {
      _table =
          readScheduleTable(bytes, fileName: fileName, forceEncoding: encoding);
      fileError = null;
    } on ScheduleFileException catch (e) {
      fileError = e.message;
      _table = null;
    }
    notifyListeners();
  }

  // ================= 步 2：列映射 =================

  void guessMapping() {
    final ScheduleTable? t = _table;
    if (t == null || mapping != null) return;
    mapping = guessColumnMapping(t);
    notifyListeners();
  }

  String? assignColumn(int index, CourseField field) {
    final String? notice = mapping?.assign(index, field);
    notifyListeners();
    return notice;
  }

  bool get mappingReady => mapping?.canImport ?? false;
}
