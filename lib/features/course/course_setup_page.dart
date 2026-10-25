import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/application/course_use_case.dart';
import 'package:qingdan/domain/course.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/import/course/schedule_file.dart';
import 'package:qingdan/import/jiaowu/jiaowu_capture.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'course_editor_sheet.dart' show showCourseEditor;
import 'course_manage_page.dart' show showCourseManagePage;
import 'course_page_scaffold.dart';
import 'course_pane_model.dart';
import 'export_sheet.dart';
import 'import_wizard/import_wizard.dart';
import 'semester_detail_page.dart';
import 'timetable_library_page.dart' show showTimetableLibrary;

/// 课表设置整页（手机端）。v1.0.10 把原来的 0.85 高底部弹层换成页面：
/// 当前学期摘要、添加课程、导入/抓取/导出，以及两个管理入口。
Future<void> showCourseSetupPage(BuildContext context) =>
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (BuildContext _) => const CourseSetupPage(),
    ));

class CourseSetupPage extends StatelessWidget {
  const CourseSetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    final CoursePaneModel model = context.watch<CoursePaneModel>();
    final AppColors colors = AppColors.of(context);
    final Semester? semester = model.semester;
    return CoursePageScaffold(
      title: '课表设置',
      child: ListView(
        padding: const EdgeInsets.all(AppDimens.panelPadding),
        children: <Widget>[
          _section(colors, '当前学期'),
          Card(
            child: InkWell(
              key: const ValueKey<String>('setup-semester'),
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                if (semester == null) {
                  showCourseManagePage(context);
                } else {
                  openSemesterDetailPage(context, semester: semester);
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(AppDimens.s12),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            semester?.name ?? '还没有学期',
                            style: AppTypography.body
                                .copyWith(color: colors.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            semester == null
                                ? '先去课表管理建一个学期'
                                : '开学 ${_ymd(semester.firstWeekMonday)} · '
                                    '共 ${semester.totalWeeks} 周 · '
                                    '第 ${model.week} 周',
                            style: AppTypography.meta,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 20),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppDimens.s16),
          _section(colors, '课程'),
          ListTile(
            key: const ValueKey<String>('setup-add-course'),
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: AppDimens.s4),
            enabled: semester != null,
            leading: Icon(Icons.add_circle_outline,
                size: 20,
                color: semester == null ? colors.textFaint : colors.textSecondary),
            title: const Text('添加课程'),
            subtitle: Text(
              semester == null
                  ? '还没有学期，先建学期'
                  : '手工录入一门课：时间、地点、老师与周次',
              style: AppTypography.meta.copyWith(
                  color: semester == null ? colors.textFaint : null),
            ),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: semester == null ? null : () => _addCourse(context, model),
          ),
          const SizedBox(height: AppDimens.s16),
          _section(colors, '课表数据'),
          ListTile(
            key: const ValueKey<String>('setup-import'),
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: AppDimens.s4),
            leading: const Icon(Icons.file_download_outlined, size: 20),
            title: const Text('导入课表文件'),
            subtitle: const Text('xlsx / csv / WakeUp 导出文件，进五步向导',
                style: AppTypography.meta),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () async {
              await showImportWizard(context);
              if (context.mounted) await model.load();
            },
          ),
          ListTile(
            key: const ValueKey<String>('setup-capture'),
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: AppDimens.s4),
            leading: const Icon(Icons.public_outlined, size: 20),
            title: const Text('从教务系统抓取'),
            subtitle: const Text('打开教务网页，登录到学生课表页后抓当前页',
                style: AppTypography.meta),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () async {
              final ScheduleTable? scraped = await showJiaowuCapture(context);
              if (scraped == null || !context.mounted) return;
              await showImportWizard(context, scraped: scraped);
              if (context.mounted) await model.load();
            },
          ),
          _ExportRow(model: model, onAfter: () => model.load()),
          const SizedBox(height: AppDimens.s16),
          _section(colors, '管理'),
          ListTile(
            key: const ValueKey<String>('setup-manage'),
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: AppDimens.s4),
            leading: const Icon(Icons.grid_on, size: 20),
            title: const Text('课表管理'),
            subtitle: const Text('全部学期：切换、新建、编辑与删除',
                style: AppTypography.meta),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => showCourseManagePage(context),
          ),
          ListTile(
            key: const ValueKey<String>('setup-templates'),
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: AppDimens.s4),
            leading: const Icon(Icons.schedule, size: 20),
            title: const Text('时间表管理'),
            subtitle: const Text('作息模板库：多套作息，按学期复制使用',
                style: AppTypography.meta),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => showTimetableLibrary(context, isMobile: true),
          ),
          const SizedBox(height: AppDimens.s24),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const ValueKey<String>('setup-done'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('完成'),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _section(AppColors colors, String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppDimens.s8),
        child: Text(text,
            style: AppTypography.panelTitle.copyWith(color: colors.textPrimary)),
      );

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _addCourse(BuildContext context, CoursePaneModel model) async {
    final CourseUseCase courses = context.read<CourseUseCase>();
    final Course? draft = await showCourseEditor(
      context,
      isMobile: true,
      totalWeeks: model.totalWeeks,
      maxSection: model.maxSection,
    );
    if (draft == null) return;
    await courses.save(
        draft.copyWith(semesterId: draft.semesterId ?? model.semester?.id));
    await model.load();
  }
}

/// 导出行：与旧设置弹层、设置 → 课表那一行同一份判据与文案。
class _ExportRow extends StatelessWidget {
  const _ExportRow({required this.model, required this.onAfter});

  final CoursePaneModel model;
  final VoidCallback onAfter;

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
      leading: Icon(Icons.file_upload_outlined,
          size: 20, color: ready ? colors.textSecondary : colors.textFaint),
      title: const Text('导出课表文件'),
      subtitle: Text(
        ready
            ? '当前学期导出成 .ics 日历文件或 .csv 表格（.csv 能原样再导回来）'
            : semester == null
                ? '还没有学期，导出无从取数据：先建一个学期'
                : '这个学期还没有课，导出会是空文件：先加课或导入课表',
        style: AppTypography.meta.copyWith(color: colors.textFaint),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: ready
          ? () async {
              await showExportSheet(context,
                  semester: semester,
                  courses: model.allCourses,
                  details: model.details,
                  currentWeek: model.week,
                  isMobile: true);
              onAfter();
            }
          : null,
    );
  }
}
