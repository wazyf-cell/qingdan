// 步 3：学期与作息（§4.2 步骤 3，M6-D §7.5 改版）。文件里不含这两项（硬事实），
// 必须在预览前补齐，否则预览画不出日历。
//
// 多学期后目标学期必须让用户**选**：`adopt-semester` 从「沿用现有学期」变成
// 学期下拉，选定后步 4 解析、步 5 落库、扩周数全部落在**那个学期**上。
// `adopt-timetable` 两选：沿用现有作息 / 换成某个模板（模板走
// `TimetableUseCase.templates()`，选中即把快照复制进目标学期）。
//
// 卡片本体与设置弹层共用（`semester_timetable_cards.dart`），这里只负责
// 「保存 → 回读 → 交给向导模型」。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/application/timetable_use_case.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/import/course/wakeup_schedule_file.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

import 'import_wizard_model.dart';
import 'wizard_setup_pickers.dart';
import '../semester_timetable_cards.dart';

class WizardStepSetup extends StatefulWidget {
  const WizardStepSetup({super.key, required this.isMobile});

  final bool isMobile;

  @override
  State<WizardStepSetup> createState() => _WizardStepSetupState();
}

class _WizardStepSetupState extends State<WizardStepSetup> {
  Semester? _selected;
  List<TimeDetail> _details = const <TimeDetail>[];
  List<Semester> _semesters = const <Semester>[];
  List<TimeTable> _templates = const <TimeTable>[];
  String _timetableChoice = kWizardKeepTimetable;
  String? _notice;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  /// 回读库内真值。[keepSelectedId] 指回刚保存/新建的学期：
  /// 「导入到」下拉不能因为保存就跳回 active 学期，否则用户改了目标却没改目标。
  Future<void> _reload({String? keepSelectedId}) async {
    final SemesterUseCase semesters = context.read<SemesterUseCase>();
    final TimetableUseCase tt = context.read<TimetableUseCase>();
    final List<Semester> all = await semesters.allSemesters();
    final Semester? active = await semesters.activeSemester();
    final List<TimeDetail> d = await semesters.loadDefaultDetails();
    final List<TimeTable> templates = await tt.templates();
    if (!mounted) return;
    final String? wanted = keepSelectedId ?? _selected?.id;
    final Semester? selected =
        all.where((Semester s) => s.id == wanted).firstOrNull ?? active;
    // 模板可能在上一次保存后被删掉：下拉值失效就退回「沿用」，
    // DropdownButton 的 value 不在 items 里会直接断言失败。
    final String choice = templates.any((TimeTable t) => t.id == _timetableChoice)
        ? _timetableChoice
        : kWizardKeepTimetable;
    setState(() {
      _semesters = all;
      _templates = templates;
      _selected = selected;
      _timetableChoice = choice;
      _details = d;
      _loaded = true;
    });
    context.read<ImportWizardModel>().adoptSemester(selected, d);
  }

  /// 「导入到学期」下拉换了目标：立刻把模型指过去，作息沿用当前展示值
  /// （学期专属作息的只读 API 属 §六/§七 的并行改造，落地后这里换数据源即可）。
  void _pickSemester(Semester? s) {
    if (s == null) return;
    setState(() => _selected = s);
    context.read<ImportWizardModel>().adoptSemester(s, _details);
  }

  /// 「作息」两选：沿用 / 换成模板。选模板 = 把模板节次**复制成该学期作息的
  /// 快照**（`applyTemplateToSemester`），此后与模板再无关系；界面展示的
  /// 就是刚复制的那份内容。
  Future<void> _pickTimetable(String? choice) async {
    if (choice == null) return;
    setState(() => _timetableChoice = choice);
    if (choice == kWizardKeepTimetable) return;
    final Semester? s = _selected;
    if (s == null) {
      setState(() => _notice = '先选要导入到的学期');
      return;
    }
    final TimetableUseCase tt = context.read<TimetableUseCase>();
    try {
      await tt.applyTemplateToSemester(semesterId: s.id, templateId: choice);
      final List<TimeDetail> copied = await tt.templateDetails(choice);
      if (!mounted) return;
      setState(() {
        _details = copied;
        _notice = '已把模板复制为「${s.name}」的作息（${copied.length} 节）';
      });
      context.read<ImportWizardModel>().adoptSemester(s, copied);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _notice = '套用模板失败：$e');
    }
  }

  Future<void> _saveSemester({
    required String name,
    required DateTime firstWeekDate,
    required int totalWeeks,
  }) async {
    final SemesterUseCase semesters = context.read<SemesterUseCase>();
    final Semester? existing = _selected;
    // 一次写完：三个 setter 依次调会互相盖回旧值（见 SemesterUseCase.saveSemester）。
    final String savedId = existing == null
        ? (await semesters.createSemester(
                name: name,
                firstWeekDate: firstWeekDate,
                totalWeeks: totalWeeks))
            .id
        : (await semesters.saveSemester(existing,
                name: name,
                firstWeekDate: firstWeekDate,
                totalWeeks: totalWeeks))
            .id;
    // 回读后卡片按库里真值重画，这就是保存成功的可见反馈（_notice 只放错误）。
    await _reload(keepSelectedId: savedId);
  }

  Future<void> _saveTimetable(List<TimeDetail> draft) async {
    final String? error =
        await context.read<SemesterUseCase>().saveDefaultTimetable(draft);
    if (!mounted) return;
    setState(() => _notice = error);
    if (error == null) await _reload();
  }

  String _ymd(DateTime d) => '${d.year}-${d.month}-${d.day}';

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final AppColors colors = AppColors.of(context);
    final WakeupMeta? meta = context.watch<ImportWizardModel>().wakeupMeta;
    final Widget pickerRow = WizardSetupPickers(
      semesters: _semesters,
      selected: _selected,
      templates: _templates,
      timetableChoice: _timetableChoice,
      onPickSemester: _pickSemester,
      onPickTimetable: _pickTimetable,
    );
    final Widget semesterCard = SemesterCard(
      semester: _selected,
      onSave: (
              {required String name,
              required DateTime firstWeekDate,
              required int totalWeeks}) =>
          _saveSemester(
              name: name,
              firstWeekDate: firstWeekDate,
              totalWeeks: totalWeeks),
    );
    final Widget timetableCard = TimetableCard(
      details: _details,
      isMobile: widget.isMobile,
      onSave: _saveTimetable,
    );
    return Padding(
      padding: const EdgeInsets.all(AppDimens.panelPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          pickerRow,
          // WakeUp 导出文件自带学期与作息：这里只做**预填提示 + 一键采纳**，
          // 走的是卡片同一个保存入口（用户点一下才写库，不静默覆盖），
          // 且写进的是下拉选中的那个学期。
          if (meta != null)
            Container(
              key: const ValueKey<String>('setup-from-export'),
              margin: const EdgeInsets.only(bottom: AppDimens.s12),
              padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.s12, vertical: AppDimens.s4),
              decoration: BoxDecoration(
                  color: colors.surfaceHigh,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                        '导出文件里带着：${_ymd(meta.firstWeekDate)} 起 · '
                        '${meta.totalWeeks} 周 · ${meta.sections.length} 节作息',
                        style: TextStyle(
                            fontSize: 13, color: colors.textSecondary)),
                  ),
                  TextButton(
                    key: const ValueKey<String>('adopt-semester-from-export'),
                    onPressed: () => _saveSemester(
                        name: _selected?.name ??
                            '${meta.firstWeekDate.year}-'
                                '${meta.firstWeekDate.year + 1}-1',
                        firstWeekDate: meta.firstWeekDate,
                        totalWeeks: meta.totalWeeks),
                    child: Text(_selected == null ? '新建并采纳学期' : '采纳到所选学期'),
                  ),
                  TextButton(
                    key: const ValueKey<String>('adopt-timetable-from-export'),
                    onPressed: () => _saveTimetable(meta.toDraft()),
                    child: const Text('采纳作息'),
                  ),
                ],
              ),
            ),
          if (_selected == null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppDimens.s12),
              child: Text('还没有学期：先建一个学期（开学日期 + 总周数），否则预览画不出日历。',
                  key: const ValueKey<String>('setup-need-semester'),
                  style: TextStyle(color: colors.overdue, fontSize: 13)),
            ),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppDimens.s8),
              child: Text(_notice!, style: TextStyle(color: colors.overdue)),
            ),
          Expanded(
            child: widget.isMobile
                ? ListView(children: <Widget>[
                    semesterCard,
                    const SizedBox(height: AppDimens.s16),
                    timetableCard,
                  ])
                : SingleChildScrollView(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(child: semesterCard),
                        const SizedBox(width: AppDimens.s16),
                        Expanded(child: timetableCard),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

