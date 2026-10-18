// 步 3：学期与作息（§4.2 步骤 3）。文件里不含这两项（硬事实），必须在预览前补齐，
// 否则预览画不出日历；用户也可跳过作息先进预览，超界警告会在步 4 集中出现。
//
// 卡片本体与设置弹层共用（`semester_timetable_cards.dart`），这里只负责
// 「保存 → 回读 → 交给向导模型」。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/import/course/wakeup_schedule_file.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

import 'import_wizard_model.dart';
import '../semester_timetable_cards.dart';

class WizardStepSetup extends StatefulWidget {
  const WizardStepSetup({super.key, required this.isMobile});

  final bool isMobile;

  @override
  State<WizardStepSetup> createState() => _WizardStepSetupState();
}

class _WizardStepSetupState extends State<WizardStepSetup> {
  Semester? _semester;
  List<TimeDetail> _details = const <TimeDetail>[];
  String? _notice;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final SemesterUseCase semesters = context.read<SemesterUseCase>();
    final Semester? s = await semesters.activeSemester();
    final List<TimeDetail> d = await semesters.loadDefaultDetails();
    if (!mounted) return;
    setState(() {
      _semester = s;
      _details = d;
      _loaded = true;
    });
    context
        .read<ImportWizardModel>()
        .adoptSemester(s, d);
  }

  Future<void> _saveSemester({
    required String name,
    required DateTime firstWeekDate,
    required int totalWeeks,
  }) async {
    final SemesterUseCase semesters = context.read<SemesterUseCase>();
    final Semester? existing = _semester;
    // 一次写完：三个 setter 依次调会互相盖回旧值（见 SemesterUseCase.saveSemester）。
    if (existing == null) {
      await semesters.createSemester(
          name: name, firstWeekDate: firstWeekDate, totalWeeks: totalWeeks);
    } else {
      await semesters.saveSemester(existing,
          name: name,
          firstWeekDate: firstWeekDate,
          totalWeeks: totalWeeks);
    }
    // 回读后卡片按库里真值重画，这就是保存成功的可见反馈（_notice 只放错误）。
    await _reload();
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
    final Widget semesterCard = SemesterCard(
      semester: _semester,
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
          // WakeUp 导出文件自带学期与作息：这里只做**预填提示 + 一键采纳**，
          // 走的是卡片同一个保存入口（用户点一下才写库，不静默覆盖）。
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
                    key: const ValueKey<String>('adopt-semester'),
                    onPressed: () => _saveSemester(
                        name: _semester?.name ??
                            '${meta.firstWeekDate.year}-'
                                '${meta.firstWeekDate.year + 1}-1',
                        firstWeekDate: meta.firstWeekDate,
                        totalWeeks: meta.totalWeeks),
                    child: const Text('采纳学期'),
                  ),
                  TextButton(
                    key: const ValueKey<String>('adopt-timetable'),
                    onPressed: () => _saveTimetable(meta.toDraft()),
                    child: const Text('采纳作息'),
                  ),
                ],
              ),
            ),
          if (_semester == null)
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
