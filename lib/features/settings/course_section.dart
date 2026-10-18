/// 设置 · 课表节（M6-C §C1 目标结构的第 4 行）。
///
/// C 批只有一件事是真能用的：跳进已有的「学期与作息」弹层——与课表面板头部
/// ⚙ 同一条 [showCourseSetup]，不另开一份实现。
/// 「时间表管理 / 课表管理 / 导出课表文件」属于 D 批，这里按**禁用置灰 + 明说
/// 「下一批开放」**占位：用户看得见这节将来有什么，但不会得到一次「点了没反应」
/// 的空反馈（M5 定案：占位要么说清原因，要么别出现）。
library;

import 'package:flutter/material.dart';

import 'package:qingdan/features/course/course_setup.dart';
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
          onTap: () => showCourseSetup(context, isMobile: isMobile),
        ),
        _placeholder(colors, kCourseManageTimetableKey, Icons.schedule,
            '时间表管理', '按学期存多套作息，切换哪一套生效'),
        _placeholder(colors, kCourseManageScheduleKey, Icons.grid_on,
            '课表管理', '按课程批量改时间、地点、老师与周次'),
        _placeholder(colors, kCourseExportKey, Icons.ios_share,
            '导出课表文件', '导出 CSV / xlsx，可给别的课表应用用'),
        _note(colors, '上面三行是下一批（D 批）的入口，现在还没有界面。'
            '课表数据本身在「学期与作息」里改，导入课程表也在那里。'),
      ],
    );
  }

  static Widget _placeholder(AppColors colors, String key, IconData icon,
          String title, String what) =>
      ListTile(
        key: ValueKey<String>(key),
        enabled: false, // 置灰：不接 onTap，也就不会「点了没反应」
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppDimens.s4),
        leading: Icon(icon, size: 20, color: colors.textFaint),
        title: Text(title, style: AppTypography.meta.copyWith(fontSize: 14)),
        subtitle: Text('$what · 下一批开放',
            style: AppTypography.meta.copyWith(color: colors.textFaint)),
      );

  static Widget _note(AppColors colors, String text) => Padding(
        padding: const EdgeInsets.only(top: AppDimens.s8),
        child: Text(text,
            style:
                AppTypography.meta.copyWith(color: colors.textFaint, height: 1.4)),
      );
}
