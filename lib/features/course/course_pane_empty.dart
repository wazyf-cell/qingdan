import 'package:flutter/material.dart';

import 'package:qingdan/domain/course.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 作息表（节次时间）为空时的周视图状态。
///
/// 这不是「没有课」也不是错误，但用户读起来就是「课表坏了」：课程按节次定位，
/// 一节作息都没填时网格画不出任何块，全部课程掉进「未排时间」
/// （2026-10-18 模拟器实测：教务抓取导入 30 门课 + `time_details` 空表，
/// 界面只剩一张空网格 + 一列 12 条的收纳区）。所以这里必须把因果讲清楚，
/// 并给一个能直接点进去填的出口，而不是让用户自己猜。
class NoTimetableState extends StatelessWidget {
  const NoTimetableState({
    super.key,
    required this.courseCount,
    required this.onFill,
  });

  /// 本学期未删除课程数（0 时文案换成「先填时间」，不说「一门都没丢」）。
  final int courseCount;
  final VoidCallback onFill;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.schedule_outlined, size: 44, color: colors.textFaint),
            const SizedBox(height: AppDimens.s12),
            Text('作息表还是空的',
                key: const ValueKey<String>('no-timetable-title'),
                style: AppTypography.body),
            const SizedBox(height: AppDimens.s4),
            Text(
              courseCount == 0
                  ? '先填每节课的起止时间，课程才能按节次画进网格'
                  : '库里有 $courseCount 门课，但节次时间一节都没填，网格无从定位。'
                      '课一门都没丢，全在「未排时间」里等着。',
              key: const ValueKey<String>('no-timetable-hint'),
              textAlign: TextAlign.center,
              style:
                  AppTypography.meta.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppDimens.s16),
            FilledButton.icon(
              key: const ValueKey<String>('no-timetable-fill'),
              onPressed: onFill,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('去填作息'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「未排时间」收纳区：节次不在作息表里的课收在这里（§3.4 绝不静默截断）。
///
/// 展开后的高度**必须有上限**：本条在面板的 Column 里是非弹性子节点，拿到的是
/// 无上限的高度约束，12 条 ListTile 会顺着撑爆整列（2026-10-18 模拟器实测
/// 「BOTTOM OVERFLOWED BY 256 PIXELS」）。所以展开内容放进限高滚动区，
/// 上限取视口高的 35%——网格是主角，收纳区不能反客为主。
class UnscheduledStrip extends StatelessWidget {
  const UnscheduledStrip({super.key, required this.courses});

  final List<Course> courses;

  static const List<String> _weekdayCn = <String>[
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final double cap = MediaQuery.sizeOf(context).height * 0.35;
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: AppDimens.s12),
      childrenPadding: EdgeInsets.zero,
      title: Text('未排时间（${courses.length}）',
          key: const ValueKey<String>('unscheduled-title'),
          style: AppTypography.body.copyWith(color: colors.textSecondary)),
      subtitle: Text('这些课占的节次不在作息表里，先收在这里，不截断',
          style: AppTypography.meta.copyWith(color: colors.textFaint)),
      children: <Widget>[
        SizedBox(
          height: cap,
          child: ListView(
            key: const ValueKey<String>('unscheduled-list'),
            padding: const EdgeInsets.only(bottom: AppDimens.s8),
            children: <Widget>[
              for (final Course c in courses)
                ListTile(
                  dense: true,
                  title: Text(c.name, style: AppTypography.body),
                  // 一屏十几条时必须带星期，否则「计算机网络」出现三次分不清。
                  subtitle: Text(
                    '${_weekdayCn[c.weekday - 1]} · 第 ${c.startSection}-${c.endSection} 节'
                    '${c.location == null ? '' : ' · ${c.location}'}',
                    style: AppTypography.meta,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
