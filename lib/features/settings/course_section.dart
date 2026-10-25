/// 设置 · 课表节（M6-C §C1 目标结构的第 4 行）。
///
/// C 批只有一件事是真能用的：跳进已有的「学期与作息」弹层——与课表面板头部
/// ⚙ 同一条 [showCourseSetup]，不另开一份实现。
/// D 批把这一节四个入口全部接通：时间表管理（模板库 §7.3）、课表管理（学期整页
/// §7.4）、导出课表文件（§9.2）。**这一节不再有禁用行**——M5 定案「占位要么说清
/// 原因，要么别出现」，现在四行都点得动，占位文本随之删掉，不留过期承诺。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/features/course/course_manage_page.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/features/course/course_setup.dart';
import 'package:qingdan/features/course/export_sheet.dart';
import 'package:qingdan/features/course/semester_detail_page.dart';
import 'package:qingdan/features/course/timetable_library_page.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

const String kCourseOpenSetupKey = 'course-open-setup';
const String kCourseManageTimetableKey = 'course-manage-timetable';
const String kCourseManageScheduleKey = 'course-manage-schedule';
const String kCourseExportKey = 'course-export-file';

class CourseSection extends StatelessWidget {
  const CourseSection({super.key, this.showTitle = true});

  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    // 与课表面板同一判据：窄屏 = 底部抽屉，宽屏 = 居中弹窗。
    final bool isMobile =
        MediaQuery.sizeOf(context).width < AppDimens.breakpointNarrow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (showTitle) ...<Widget>[
          Text('课表',
              style:
                  AppTypography.panelTitle.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppDimens.s8),
        ],
        ListTile(
          key: const ValueKey<String>(kCourseOpenSetupKey),
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppDimens.s4),
          leading: const Icon(Icons.calendar_today_outlined, size: 20),
          title: const Text('学期与作息'),
          subtitle: Text('学期名称、开学日期、总周数，以及每天各节课的上/下课时间',
              style: AppTypography.meta),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () {
            if (isMobile) {
              // 手机端这一行直接进「学期与作息」详情页；还没有学期时去管理页建。
              final CoursePaneModel? model =
                  context.read<CoursePaneModel?>();
              final semester = model?.semester;
              if (semester == null) {
                showCourseManagePage(context);
              } else {
                openSemesterDetailPage(context, semester: semester);
              }
            } else {
              showCourseSetup(context, isMobile: false);
            }
          },
        ),
        ListTile(
          key: const ValueKey<String>(kCourseManageTimetableKey),
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppDimens.s4),
          leading: const Icon(Icons.schedule, size: 20),
          title: const Text('时间表管理'),
          subtitle: Text('模板库：多套作息，按学期复制使用（改模板不影响已建学期）',
              style: AppTypography.meta),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () => showTimetableLibrary(context, isMobile: isMobile),
        ),
        ListTile(
          key: const ValueKey<String>(kCourseManageScheduleKey),
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppDimens.s4),
          leading: const Icon(Icons.grid_on, size: 20),
          title: const Text('课表管理'),
          subtitle: Text('一屏管全部学期：切换、新建、改开学日期与总周数、删除，'
              '两条导入入口也在这里',
              style: AppTypography.meta),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () => showCourseManagePage(context),
        ),
        _exportRow(context, colors, isMobile),
        _note(colors, '改某一门课的时间、地点、老师是点周视图里的课程块；'
            '按课程批量改目前只有导入向导的校正步里有，落库之后不再提供批量入口。'),
      ],
    );
  }

  /// 导出行。课表数据从 [CoursePaneModel] 拿（UI 不碰 DAO，铁律）。
  ///
  /// 用**可空**读法：设置树在纯 UI 测试里、以及课表模型尚未装配时也要能渲染，
  /// 拿不到就整行禁用并说明原因，而不是抛 ProviderNotFoundException。
  Widget _exportRow(BuildContext context, AppColors colors, bool isMobile) {
    final CoursePaneModel? model = context.watch<CoursePaneModel?>();
    final bool ready =
        model != null && model.semester != null && model.allCourses.isNotEmpty;
    return ListTile(
      key: const ValueKey<String>(kCourseExportKey),
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
            : model == null
                ? '课表数据未装配，先从底部「课表」页进来'
                : '还没有学期或还没有课，导出无从取数据',
        style: AppTypography.meta.copyWith(color: colors.textFaint),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => showExportSheet(context,
          semester: model!.semester!,
          courses: model.allCourses,
          details: model.details,
          currentWeek: model.week,
          isMobile: isMobile),
    );
  }

  static Widget _note(AppColors colors, String text) => Padding(
        padding: const EdgeInsets.only(top: AppDimens.s8),
        child: Text(text,
            style:
                AppTypography.meta.copyWith(color: colors.textFaint, height: 1.4)),
      );
}
