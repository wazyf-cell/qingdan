// ignore_for_file: prefer_initializing_formals — 命名参数不能以 _ 开头
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/application/timetable_use_case.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';

/// 模板库页的一行：模板行 + 它的节次（摘要与「使用」回执的 N 都从这里取）。
/// 节次随 `load()` 一起拉，行渲染不再触发异步。
class TemplateRow {
  TemplateRow({required this.table, required this.details});

  final TimeTable table;
  final List<TimeDetail> details;

  /// `08:00–22:30 · 12 节`（§7.3 的首末节时间摘要）。
  String get summary => details.isEmpty
      ? '暂无节次'
      : '${formatMinutes(details.first.startMinutes)}'
        '–${formatMinutes(details.last.endMinutes)} · ${details.length} 节';
}

/// 时间表管理页的状态（M6-D §7.3）。
///
/// UI 不碰 DAO（AGENTS.md 铁律）：读写只经 `TimetableUseCase` /
/// `SemesterUseCase`。「设为默认模板」写 prefs `course.defaultTemplateId`，
/// **设备本地、不同步**（两台设备可以有各自的默认偏好，§7.3 末条）。
/// 所有写路径的结果（成功回执或错误串）都落在 [message]，界面**不许静默**。
class TimetableLibraryModel extends ChangeNotifier {
  TimetableLibraryModel({
    required TimetableUseCase templates,
    required SemesterUseCase semesters,
    SharedPreferences? prefs,
  })  : _templates = templates,
        _semesters = semesters,
        _prefs = prefs;

  static const String kDefaultTemplatePrefKey = 'course.defaultTemplateId';

  final TimetableUseCase _templates;
  final SemesterUseCase _semesters;
  final SharedPreferences? _prefs;

  List<TemplateRow> rows = <TemplateRow>[];
  List<Semester> semesters = <Semester>[];
  String? defaultTemplateId;
  String? message;
  bool messageIsError = false;

  String? get activeSemesterId {
    for (final Semester s in semesters) {
      if (s.isActive) return s.id;
    }
    return semesters.isEmpty ? null : semesters.first.id;
  }

  Future<void> load() async {
    final List<TimeTable> tables = await _templates.templates();
    rows = <TemplateRow>[
      for (final TimeTable t in tables)
        TemplateRow(table: t, details: await _templates.templateDetails(t.id)),
    ];
    semesters = await _semesters.allSemesters();
    defaultTemplateId = (await _instance()).getString(kDefaultTemplatePrefKey);
    notifyListeners();
  }

  /// 编辑器保存：[row] 为 null = 新建；否则「改名（若变了）+ 整表保存节次」。
  /// 内置模板的节次保存在用例层被拒（StateError），错误串进 [message]，
  /// 返回 false——界面把它显示在面板内，不许静默 return（§7.3）。
  Future<bool> save(TemplateRow? row, String name, List<TimeDetail> details) async {
    final String trimmed = name.trim();
    String? error;
    try {
      if (row == null) {
        await _templates.createTemplate(name: trimmed, generated: details);
      } else {
        if (trimmed.isNotEmpty && trimmed != row.table.name) {
          await _templates.renameTemplate(row.table.id, trimmed);
        }
        error = await _templates.saveTemplateDetails(row.table.id, details);
      }
    } catch (e) {
      error = _msg(e);
    }
    if (trimmed.isEmpty && error == null) error = '模板名称不能为空';
    if (error != null) {
      _say(error, true);
      return false;
    }
    await load();
    _say(row == null ? '已创建「$trimmed」' : '已保存「${row.table.name}」', false);
    return true;
  }

  /// 「使用」= 把模板节次**复制快照**进该学期作息（§6.2：复用原行 id，
  /// 同步侧不把改时间看成一删一增）。回执文案按 §7.3 逐字。
  Future<void> use(String templateId, String semesterId) async {
    final TemplateRow row = rows.firstWhere((TemplateRow r) => r.table.id == templateId);
    final String semesterName =
        semesters.firstWhere((Semester s) => s.id == semesterId).name;
    try {
      await _templates.applyTemplateToSemester(
          semesterId: semesterId, templateId: templateId);
      _say('已把「${row.table.name}」的 ${row.details.length} 节时间'
          '应用到「$semesterName」', false);
    } catch (e) {
      _say(_msg(e), true);
    }
    await load();
  }

  Future<void> remove(String id) async {
    try {
      await _templates.deleteTemplate(id);
    } catch (e) {
      _say(_msg(e), true);
      return;
    }
    await load();
    _say('已删除模板', false);
  }

  Future<void> setDefault(String id) async {
    await (await _instance()).setString(kDefaultTemplatePrefKey, id);
    defaultTemplateId = id;
    _say('已设为本机默认模板', false);
    notifyListeners();
  }

  Future<SharedPreferences> _instance() async =>
      _prefs ?? await SharedPreferences.getInstance();

  /// 用例层守卫（StateError/ArgumentError）的文案原样展示；其它异常兜底成
  /// runtimeType + message，不吞、也不裸 `toString()` 带出「Bad state:」前缀。
  static String _msg(Object e) {
    if (e is StateError) return e.message;
    if (e is ArgumentError) return '${e.message}';
    return '$e';
  }

  void _say(String text, bool error) {
    message = text;
    messageIsError = error;
    notifyListeners();
  }
}
