import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/import/course/schedule_file.dart';
import 'package:qingdan/import/jiaowu/jiaowu_capture.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'course_pane_model.dart';
import 'export_sheet.dart';
import 'import_wizard/import_wizard.dart';
import 'semester_timetable_cards.dart';

// 课程编辑弹层已按职责拆到 `course_editor_sheet.dart`（本文件触 300 行红线）。
// 这里再导出一次：课表面板与向导步 4 的 `import 'course_setup.dart'` 不用改。
export 'course_editor_sheet.dart';

/// 课表设置弹层（§4.2 步骤 3 的「学期卡 + 作息卡」，平时也从头部 ⚙ 进来）。
///
/// 形态按 §2.6/§五 的双端约定：桌面 = 居中弹窗两卡并排；移动 = 底部抽屉上下堆叠。
///
/// 三条高频近路都在这一层：导入课表文件、从教务系统抓取（头部那一行的两个按钮），
/// 以及导出课表文件（紧接其下的整行 [_ExportNearPath]，§9.2「近路」那条）。
Future<void> showCourseSetup(BuildContext context, {required bool isMobile}) {
  return isMobile
      ? showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (BuildContext ctx) => Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom, top: AppDimens.s8),
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.85,
              builder: (BuildContext ctx, ScrollController controller) =>
                  SingleChildScrollView(
                controller: controller,
                child: const _CourseSetupBody(),
              ),
            ),
          ),
        )
      : showDialog<void>(
          context: context,
          builder: (BuildContext ctx) => const AlertDialog(
            insetPadding: EdgeInsets.all(AppDimens.s32),
            content: SizedBox(
              width: 720,
              child: _CourseSetupBody(),
            ),
          ),
        );
}

class _CourseSetupBody extends StatefulWidget {
  const _CourseSetupBody();

  @override
  State<_CourseSetupBody> createState() => _CourseSetupBodyState();
}

class _CourseSetupBodyState extends State<_CourseSetupBody> {
  /// 保存回执。**必须是弹层内的一行字，不能是 SnackBar**：本弹层是 modal route，
  /// SnackBar 画在它下面那层 Scaffold 上，用户看不到（2026-10-18 模拟器实测）。
  String? _saidSemester;
  String? _saidTimetable;

  @override
  Widget build(BuildContext context) {
    final CoursePaneModel model = context.watch<CoursePaneModel>();
    final SemesterUseCase semesters = context.read<SemesterUseCase>();
    final bool isMobile =
        MediaQuery.sizeOf(context).width < AppDimens.breakpointNarrow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text('学期与作息',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            TextButton.icon(
              key: const ValueKey<String>('setup-import'),
              onPressed: () {
                // 先关掉本弹层再开向导：向导结束后回到的是课表主页，而不是
                // 一个数据已经过期的设置弹层。用 Navigator 自己的 context
                // 开下一层——本 widget 马上要被 pop 掉，它的 context 不能用。
                final NavigatorState nav = Navigator.of(context);
                nav.pop();
                showImportWizard(nav.context);
              },
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('导入课表文件'),
            ),
            TextButton.icon(
              key: const ValueKey<String>('setup-capture'),
              onPressed: () async {
                // 抓取页自己 push/pop；拿到表后再关本弹层开向导，
                // 与「导入课表文件」同一套理由：向导结束回到的是课表主页。
                final NavigatorState nav = Navigator.of(context);
                final ScheduleTable? scraped = await showJiaowuCapture(context);
                if (scraped == null || !nav.mounted) return;
                nav.pop();
                showImportWizard(nav.context, scraped: scraped);
              },
              icon: const Icon(Icons.public_outlined, size: 18),
              label: const Text('从教务系统抓取'),
            ),
          ],
        ),
        // 导出做成独立一整行，不塞进上面那个 Row：411dp 上「标题 + 两个按钮」
        // 已经排满，第三个只会把 Row 撑爆（本项目吃过两次窄屏 Row 溢出的亏）。
        const SizedBox(height: AppDimens.s4),
        _ExportNearPath(model: model, isMobile: isMobile),
        const SizedBox(height: AppDimens.s12),
        SemesterCard(
          semester: model.semester,
          onSave: (
                  {required String name,
                  required DateTime firstWeekDate,
                  required int totalWeeks}) async {
            // 一次写完三个字段。**不要**拆成 rename/setTotalWeeks/setFirstWeek
            // 依次调：它们各自拿同一份旧快照整行写回，后一次会盖掉前一次，
            // 表现就是用户报的「改了周数点保存没反应」（2026-10-18）。
            final Semester? existing = model.semester;
            final Semester saved = existing == null
                ? await semesters.createSemester(
                    name: name,
                    firstWeekDate: firstWeekDate,
                    totalWeeks: totalWeeks)
                : await semesters.saveSemester(existing,
                    name: name,
                    firstWeekDate: firstWeekDate,
                    totalWeeks: totalWeeks);
            await model.load();
            _saySemester('学期已保存 · ${saved.name} 共 ${saved.totalWeeks} 周');
            // 不关弹层：建完学期接着设作息，一步到位。
          },
        ),
        // 回执紧跟在产生它的那张卡下面：弹层是 85% 高的滚动区，放在最底部
        // （完成按钮旁）等于在屏幕外面（2026-10-18 模拟器实测第一版就这么藏起来了）。
        _Said(text: _saidSemester, keyName: 'setup-said-semester'),
        if (model.semester != null)
          // A5 的出口说明。计划文档要求贴在「开学日期」那一行下面，但
          // `semester_editor.dart` 不在本批可改范围，就挂在同一张学期卡正下方。
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppDimens.s12, AppDimens.s4, AppDimens.s12, 0),
            child: Text(
              '周数显示不对？在周视图点顶部「第 N 周」→ 长按正确的那一周即可一键校准',
              key: const ValueKey<String>('setup-week-calibrate-hint'),
              style: AppTypography.meta
                  .copyWith(color: AppColors.of(context).textFaint),
            ),
          ),
        const SizedBox(height: AppDimens.s16),
        TimetableCard(
          details: model.details,
          isMobile: isMobile,
          onSave: (List<TimeDetail> draft) async {
            final String? error = await semesters.saveDefaultTimetable(draft);
            if (error != null) {
              // 用例层这道闸通常不会响（面板 _save 已跑过同一个
              // validateTimeDetails），但一旦两处判据分叉，静默 return 就又变成
              // 用户报过的「点了没反应」。回执必须显式变红，不能吞。
              _sayTimetable('保存被拒绝：$error', error: true);
              return;
            }
            await model.load();
            _sayTimetable('作息已保存 · ${draft.length} 节');
          },
        ),
        _Said(
            text: _saidTimetable,
            keyName: 'setup-said-timetable',
            error: _timetableFailed),
        const SizedBox(height: AppDimens.s8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: const ValueKey<String>('setup-done'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('完成'),
          ),
        ),
      ],
    );
  }

  void _saySemester(String text) {
    if (!mounted) return;
    setState(() => _saidSemester = text);
  }

  bool _timetableFailed = false;

  void _sayTimetable(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _saidTimetable = text;
      _timetableFailed = error;
    });
  }
}

/// 「学期与作息」弹层里的导出近路（§9.2：高频操作要有近路）。
///
/// **不另开一份实现**：取数、禁用判据、点击行为与设置 → 课表 → 「导出课表文件」
/// （`settings/course_section.dart` 的 `_exportRow`）逐字对齐，同一个
/// [showExportSheet]。数据不齐时整行禁用并把原因写在副文案里——本项目定案
/// 「占位要么说清原因，要么别出现」，绝不允许「点了没反应」。
class _ExportNearPath extends StatelessWidget {
  const _ExportNearPath({required this.model, required this.isMobile});

  final CoursePaneModel model;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Semester? semester = model.semester;
    final bool ready = semester != null && model.allCourses.isNotEmpty;
    return ListTile(
      key: const ValueKey<String>('setup-export'),
      enabled: ready,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppDimens.s4),
      // 导出朝上、导入朝下（M6-A A7 定案的对称）。
      leading: Icon(Icons.file_upload_outlined,
          size: 20, color: ready ? colors.textSecondary : colors.textFaint),
      title: const Text('导出课表文件'),
      subtitle: Text(
        ready
            ? '当前学期导出成 .ics 日历文件或 .csv 表格（.csv 能原样再导回来）'
            : semester == null
                ? '还没有学期，导出无从取数据：先在下面建一个学期'
                : '这个学期还没有课，导出会是空文件：先加课或导入课表',
        key: const ValueKey<String>('setup-export-reason'),
        style: AppTypography.meta.copyWith(color: colors.textFaint),
      ),
      onTap: ready
          ? () => showExportSheet(context,
              semester: model.semester!,
              courses: model.allCourses,
              details: model.details,
              currentWeek: model.week,
              isMobile: isMobile)
          : null,
    );
  }
}

/// 一行保存回执，紧贴在产生它的那张卡下面。
class _Said extends StatelessWidget {
  const _Said({required this.text, required this.keyName, this.error = false});

  final String? text;
  final String keyName;

  /// 被拒绝的保存也要看得见（灰色「已保存」与红色「保存被拒绝」不能长一样）。
  final bool error;

  @override
  Widget build(BuildContext context) {
    final String? t = text;
    if (t == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(
          top: AppDimens.s4,
          left: AppDimens.s12,
          right: AppDimens.s12), // 与上面那张 Card 的边距对齐，别贴着屏幕边
      child: Text(t,
          key: ValueKey<String>(keyName),
          textAlign: TextAlign.right,
          style: AppTypography.meta
              .copyWith(color: error ? AppColors.of(context).overdue : AppColors.of(context).textSecondary)),
    );
  }
}
