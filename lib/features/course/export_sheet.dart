import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/course.dart';
import '../../domain/semester.dart';
import '../../domain/time_table.dart';
import '../../export/csv_writer.dart';
import '../../export/ics_writer.dart';
import '../../platform/file_intents.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_typography.dart';

/// 落盘结局。**取消与失败必须分开**：取消什么都不写也不报错；失败（SAF 不可用且
/// 兜底也写不进）给红色回执——两者静默都是「点了没反应」的形状。
class ExportOutcome {
  const ExportOutcome._(this.path, this.canceled);
  const ExportOutcome.saved(String path) : this._(path, false);
  const ExportOutcome.canceled() : this._(null, true);
  const ExportOutcome.failed() : this._(null, false);
  final String? path;
  final bool canceled;
}

/// (mime, 文件名, 字节) → 落盘结果。测试注入假保存；生产用 [saveViaSystemOrFallback]。
typedef ExportSaver = Future<ExportOutcome> Function(String mime, String fileName, Uint8List bytes);

/// 先走系统「另存为」；用户取消到此为止；原生不可用或写入失败才落应用目录兜底。
Future<ExportOutcome> saveViaSystemOrFallback(String mime, String fileName, Uint8List bytes) async {
  String? dest; bool unavailable = false;
  try { dest = await FileIntents.createDocument(mime: mime, fileName: fileName); }
  on PlatformException { unavailable = true; }
  on MissingPluginException { unavailable = true; }
  if (dest == null && !unavailable) return const ExportOutcome.canceled();
  if (dest != null && await FileIntents.writeToUri(dest, bytes)) return ExportOutcome.saved(dest);
  final fb = await FileIntents.writeAppDocument(fileName: fileName, bytes: bytes);
  return fb == null ? const ExportOutcome.failed() : ExportOutcome.saved(fb);
}

/// 课表导出弹层（§9.2）。形态与 `showCourseSetup` 同款：桌面居中弹窗、移动底部抽屉。
/// [currentWeek] 由调用方算好传入（「仅本周」的范围）；[saver] 仅为测试注入。
Future<void> showExportSheet(BuildContext context,
    {required Semester semester, required List<Course> courses, required List<TimeDetail> details,
    required int currentWeek, required bool isMobile, ExportSaver? saver}) {
  final body = _ExportSheet(semester: semester, courses: courses, details: details,
      currentWeek: currentWeek, save: saver ?? saveViaSystemOrFallback);
  return isMobile
      ? showModalBottomSheet<void>(context: context, isScrollControlled: true,
          showDragHandle: true, // 长路径回执 + 小屏时不顶出溢出红线
          builder: (_) => SafeArea(child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: body)))
      : showDialog<void>(context: context,
          builder: (_) => AlertDialog(insetPadding: const EdgeInsets.all(AppDimens.s32),
              content: SizedBox(width: 420, child: body)));
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.semester, required this.courses, required this.details,
    required this.currentWeek, required this.save});
  final Semester semester;
  final List<Course> courses;
  final List<TimeDetail> details;
  final int currentWeek;
  final ExportSaver save;
  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  bool _ics = true, _allWeeks = true, _busy = false, _failed = false;
  String? _said, _savedPath; // 回执文本；可复制的完整路径（兜底事故防线）

  /// 范围裁剪：「仅本周」把每门课周次压成当周并改写周数文本——否则导出的 CSV
  /// 再导回来会把全学期周次带回去（raw_weeks_text 优先于 weeks）。
  List<Course> _scoped() {
    final live = widget.courses.where((Course c) => !c.deleted).toList();
    if (_allWeeks) return live;
    return <Course>[
      for (final Course c in live)
        if (c.isOn(widget.currentWeek))
          c.copyWith(weeks: <int>[widget.currentWeek], rawWeeksText: '${widget.currentWeek}周')
    ];
  }

  /// 文件名消毒：学期名常带空格与 `/`（如 `2026/2027 秋季`）。Windows 明令禁止
  /// `\/:*?"<>|`，SAF 与部分 ROM 连空格都出问题，URI/命令行拼接也怕空格；头尾的
  /// 点 Windows 会静默吞掉。非法与空白统一换 `_`，全非法则退回「课表」。
  String _fileName() {
    var base = widget.semester.name
        .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
        .replaceAll(RegExp(r'^[.]+|[.]+$'), '');
    return '${base.isEmpty ? '课表' : base}.${_ics ? 'ics' : 'csv'}';
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    final scoped = _scoped();
    final text = _ics
        ? writeIcs(semester: widget.semester, courses: scoped, details: widget.details).text
        : writeCsv(courses: scoped);
    final out = await widget.save(_ics ? 'text/calendar' : 'text/csv',
        _fileName(), Uint8List.fromList(utf8.encode(text)));
    if (!mounted) return;
    setState(() {
      _busy = false; _savedPath = out.path; _failed = !out.canceled && out.path == null;
      _said = out.canceled ? '已取消，未写任何文件'
          : _failed ? '导出失败：未能写入文件，请重试' : '已导出到：${out.path}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final scoped = _scoped();
    // 预览也走纯函数：ics「事件数」= 逐周展开后的 VEVENT 数；csv 一行 == 一个事件。
    final preview = writeIcs(semester: widget.semester, courses: scoped, details: widget.details);
    final events = _ics ? preview.eventCount : scoped.length;
    final skipped = _ics ? preview.skippedCount : 0;
    final colors = AppColors.of(context);
    return Column(
        key: const ValueKey<String>('export-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 导出朝上、导入朝下（A7 对称定案）；入口按钮由接线方同样用这个图标。
          Row(children: <Widget>[
            const Icon(Icons.file_upload_outlined, size: 20),
            const SizedBox(width: AppDimens.s8),
            Text('导出课表文件', style: Theme.of(context).textTheme.titleMedium),
          ]),
          const SizedBox(height: AppDimens.s8),
          _radios(_ics ? 'ics' : 'csv', (v) => setState(() => _ics = v == 'ics'),
              const <(String, String, String)>[
                ('export-format-ics', 'ics 日历文件（逐周展开）', 'ics'),
                ('export-format-csv', 'csv 表格（可再导回本应用）', 'csv'),
              ]),
          _radios(_allWeeks ? 'all' : 'week', (v) => setState(() => _allWeeks = v == 'all'),
              <(String, String, String)>[
                const ('export-scope-all', '当前学期全部周次', 'all'),
                ('export-scope-week', '仅本周（第 ${widget.currentWeek} 周）', 'week'),
              ]),
          Text('将导出 ${scoped.length} 门课程、$events 个事件',
              key: const ValueKey<String>('export-count'), style: AppTypography.meta),
          if (skipped > 0)
            Text('$skipped 门课因节次不在作息表中被跳过',
                key: const ValueKey<String>('export-skipped'),
                style: AppTypography.meta.copyWith(color: colors.textFaint)),
          if (_said != null)
            SelectableText(_said!, key: const ValueKey<String>('export-said'),
                style: AppTypography.meta.copyWith(
                    color: _failed ? colors.overdue : colors.textSecondary)),
          if (_savedPath != null)
            Align(alignment: Alignment.centerLeft, child: TextButton.icon(
                key: const ValueKey<String>('export-copy'),
                onPressed: () => Clipboard.setData(ClipboardData(text: _savedPath!)),
                icon: const Icon(Icons.copy_all_outlined, size: 16),
                label: const Text('复制路径'))),
          const SizedBox(height: AppDimens.s8),
          Row(children: <Widget>[
            Expanded(child: FilledButton.icon(
                key: const ValueKey<String>('export-run'),
                onPressed: _busy ? null : _export,
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: Text(_busy ? '导出中…' : '导出'))),
            const SizedBox(width: AppDimens.s8),
            TextButton(key: const ValueKey<String>('export-close'),
                onPressed: () => Navigator.of(context).pop(), child: const Text('关闭')),
          ]),
        ]);
  }

  /// Flutter 3.32+：分组值归 RadioGroup 管，单个 tile 只带 value。
  Widget _radios(String group, ValueChanged<String?> on, List<(String, String, String)> opts) =>
      RadioGroup<String>(groupValue: group, onChanged: on,
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            for (final (String key, String label, String value) in opts)
              RadioListTile<String>(key: ValueKey<String>(key), value: value, dense: true,
                  title: Text(label, style: AppTypography.meta))
          ]));
}
