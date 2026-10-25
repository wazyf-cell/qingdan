import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/application/timetable_use_case.dart';
import 'package:qingdan/import/course/schedule_file.dart' show ScheduleTable;
import 'package:qingdan/import/jiaowu/jiaowu_capture.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'course_page_scaffold.dart';
import 'course_pane_model.dart';
import 'import_wizard/import_wizard.dart';
import 'semester_cards.dart';
import 'timetable_library_page.dart' show showTimetableLibrary;

/// 课表管理整页（v1.0.10 重排）。
///
/// 顶部是两条导入入口（高频且决定后续一切），下面是学期卡片：点卡片看详情，
/// 「使用」是独立按钮，编辑/删除/校准收进卡片菜单。
class CourseManagePage extends StatelessWidget {
  const CourseManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final CoursePaneModel model = context.watch<CoursePaneModel>();
    final SemesterUseCase semesters = context.read<SemesterUseCase>();
    final TimetableUseCase? templates = context.read<TimetableUseCase?>();
    final bool isMobile =
        MediaQuery.sizeOf(context).width < AppDimens.breakpointNarrow;
    return CoursePageScaffold(
      title: '课表管理',
      child: ListView(
        padding: const EdgeInsets.all(AppDimens.panelPadding),
        children: <Widget>[
          _section(colors, '课表数据'),
          Card(
            child: Column(
              children: <Widget>[
                _row(context, colors, Icons.file_download_outlined, '导入课表文件',
                    'xlsx / csv / WakeUp 课程表导出文件，进五步向导', () async {
                  await showImportWizard(context);
                  if (context.mounted) await model.load();
                }, key: 'manage-import'),
                _row(context, colors, Icons.public_outlined, '从教务系统抓取',
                    '打开教务网页，自己登录到学生课表页后抓当前页',
                    () => _capture(context), key: 'manage-capture'),
                _row(context, colors, Icons.schedule, '时间表管理',
                    '作息模板库：多套作息，按学期复制使用',
                    () => showTimetableLibrary(context, isMobile: isMobile),
                    key: 'manage-templates'),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.s16),
          _section(colors, '学期'),
          SemesterCards(
            model: model,
            semesters: semesters,
            templates: templates,
            isMobile: isMobile,
          ),
        ],
      ),
    );
  }

  /// 与「学期与作息」那条同一条路：抓到表才开向导，取消就是什么都没发生。
  Future<void> _capture(BuildContext context) async {
    final ScheduleTable? scraped = await showJiaowuCapture(context);
    if (scraped == null || !context.mounted) return;
    await showImportWizard(context, scraped: scraped);
    if (context.mounted) await context.read<CoursePaneModel>().load();
  }

  static Widget _section(AppColors colors, String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppDimens.s8),
        child: Text(text,
            style: AppTypography.panelTitle.copyWith(color: colors.textPrimary)),
      );

  Widget _row(BuildContext context, AppColors colors, IconData icon, String title,
          String what, VoidCallback onTap,
          {required String key}) =>
      ListTile(
        key: ValueKey<String>(key),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppDimens.s12),
        leading: Icon(icon, size: 20, color: colors.textSecondary),
        title: Text(title, style: AppTypography.meta.copyWith(fontSize: 14)),
        subtitle: Text(what, style: AppTypography.meta),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: onTap,
      );
}

Future<void> showCourseManagePage(BuildContext context) =>
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (BuildContext _) => const CourseManagePage(),
    ));
