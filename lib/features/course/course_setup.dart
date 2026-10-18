import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/import/course/schedule_file.dart';
import 'package:qingdan/import/jiaowu/jiaowu_capture.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'course_edit_panel.dart';
import 'course_pane_model.dart';
import 'import_wizard/import_wizard.dart';
import 'semester_timetable_cards.dart';

/// 课表设置弹层（§4.2 步骤 3 的「学期卡 + 作息卡」，平时也从头部 ⚙ 进来）。
///
/// 形态按 §2.6/§五 的双端约定：桌面 = 居中弹窗两卡并排；移动 = 底部抽屉上下堆叠。
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
              icon: const Icon(Icons.file_upload_outlined, size: 18),
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
        const SizedBox(height: AppDimens.s16),
        TimetableCard(
          details: model.details,
          isMobile: isMobile,
          onSave: (List<TimeDetail> draft) async {
            final String? error = await semesters.saveDefaultTimetable(draft);
            if (error != null) return; // 校验错误由面板自己展示，不关弹层
            await model.load();
            _sayTimetable('作息已保存 · ${draft.length} 节');
          },
        ),
        _Said(text: _saidTimetable, keyName: 'setup-said-timetable'),
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

  void _sayTimetable(String text) {
    if (!mounted) return;
    setState(() => _saidTimetable = text);
  }
}

/// 一行保存回执，紧贴在产生它的那张卡下面。
class _Said extends StatelessWidget {
  const _Said({required this.text, required this.keyName});

  final String? text;
  final String keyName;

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
              .copyWith(color: AppColors.of(context).textSecondary)),
    );
  }
}

/// 课程编辑弹层：新建或修改一门课，返回要落库的 [Course]（取消返回 null）。
///
/// [totalWeeks] / [maxSection] 由调用方给——导入向导的校正界面没有
/// `CoursePaneModel`，不该为了弹层去伪造一个。
Future<Course?> showCourseEditor(BuildContext context,
    {Course? course,
    required bool isMobile,
    required int totalWeeks,
    required int maxSection}) async {
  if (isMobile) {
    return showModalBottomSheet<Course>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext ctx) => Padding(
        // 键盘避让：不垫 viewInsets 时「保存」会被 IME 整个盖住（真机 411dp
        // 实测点不到，只能靠收起键盘再点）。与 [showCourseSetup] 同一处理。
        padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom, top: AppDimens.s8),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          builder: (BuildContext ctx, ScrollController controller) =>
              CourseEditPanel(
            totalWeeks: totalWeeks,
            maxSection: maxSection,
            initial: course,
            isMobile: true,
            scrollController: controller,
            onSave: (Course c) => Navigator.of(ctx).pop(c),
          ),
        ),
      ),
    );
  }
  return showDialog<Course>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(course == null ? '添加课程' : '编辑课程'),
      content: SizedBox(
        width: 560,
        child: CourseEditPanel(
          totalWeeks: totalWeeks,
          maxSection: maxSection,
          initial: course,
          onSave: (Course c) => Navigator.of(ctx).pop(c),
        ),
      ),
    ),
  );
}

