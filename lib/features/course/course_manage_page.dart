import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/application/timetable_use_case.dart';
import 'package:qingdan/import/course/schedule_file.dart' show ScheduleTable;
import 'package:qingdan/import/jiaowu/jiaowu_capture.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'course_pane_model.dart';
import 'import_wizard/import_wizard.dart';
import 'semester_sheet.dart' show SemesterListView;
import 'timetable_library_page.dart';

/// 课表管理整页（M6-D §7.4）= 学期面板的整页版本，复用同一个 [SemesterListView]。
///
/// 用整页而不是弹层：这里的内容要能装下「一屏学期 + 两条导入入口」，而设置树
/// 的二级页本来就是整页（`SettingsSectionPage`），形态一致才不用解释两种导航。
/// 「导入课表文件 / 从教务系统抓取」是 `course_setup.dart` 那两条的**第二入口**，
/// 行为一字不差：拿到表就进五步向导，向导开在本页之上，关掉回到本页。
class CourseManagePage extends StatelessWidget {
  const CourseManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final CoursePaneModel model = context.watch<CoursePaneModel>();
    final SemesterUseCase semesters = context.read<SemesterUseCase>();
    final TimetableUseCase templates = context.read<TimetableUseCase>();
    final bool isMobile =
        MediaQuery.sizeOf(context).width < AppDimens.breakpointNarrow;
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colors.surface,
        foregroundColor: colors.textSecondary,
        titleTextStyle: AppTypography.pageTitle
            .copyWith(fontSize: 17, color: colors.textPrimary),
        title: const Text('课表管理'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: colors.divider),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppDimens.panelPadding),
        children: <Widget>[
          _row(colors, Icons.file_download_outlined, '导入课表文件',
              'xlsx / csv / WakeUp 课程表导出文件，进五步向导',
              () => showImportWizard(context), key: 'manage-import'),
          _row(colors, Icons.public_outlined, '从教务系统抓取',
              '打开教务网页，自己登录到学生课表页后抓当前页',
              () => _capture(context), key: 'manage-capture'),
          _row(colors, Icons.schedule, '时间表管理',
              '作息模板库：多套作息，按学期复制使用',
              () => showTimetableLibrary(context, isMobile: isMobile),
              key: 'manage-templates'),
          const SizedBox(height: AppDimens.s16),
          SemesterListView(
              model: model,
              semesters: semesters,
              templates: templates,
              isMobile: isMobile),
        ],
      ),
    );
  }

  /// 与「学期与作息」弹层里那条同一条路：抓到表才开向导，取消就是什么都没发生。
  Future<void> _capture(BuildContext context) async {
    final ScheduleTable? scraped = await showJiaowuCapture(context);
    if (scraped == null || !context.mounted) return;
    await showImportWizard(context, scraped: scraped);
  }

  Widget _row(AppColors colors, IconData icon, String title, String what,
          VoidCallback onTap,
          {required String key}) =>
      ListTile(
        key: ValueKey<String>(key),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppDimens.s4),
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
