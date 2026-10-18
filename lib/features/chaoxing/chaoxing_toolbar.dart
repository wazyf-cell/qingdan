/// 学习通面板工具栏，控件清单与扩展成品一一对应：
/// 搜索标题或课程 / 课程筛选 / 仅看未完成 / 仅看可提交 / 排序 /
/// 「数据 · N 分钟前（· 建议刷新）」/「<页签> · <排序>」+「N 项」。
///
/// 移动端适配：扩展在桌面侧栏里竖排的控件，这里压成一行横向滚动；
/// 搜索框独占一行（411dp 宽放不下并排）。
library;

import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'chaoxing_grouping.dart';
import 'chaoxing_model.dart';

class ChaoxingToolbar extends StatelessWidget {
  const ChaoxingToolbar({
    super.key,
    required this.model,
    required this.searchController,
    required this.onQueryChanged,
    required this.course,
    required this.onCourseChanged,
    required this.courses,
    required this.count,
  });

  final ChaoxingModel model;

  /// 控制器由面板持有：在 build 里新建会每次重建都丢焦点与光标。
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final String course;
  final ValueChanged<String> onCourseChanged;
  final List<String> courses;
  final int count;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final ChaoxingViewSettings s = model.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.s16),
          child: TextField(
            controller: searchController,
            onChanged: onQueryChanged,
            style: AppTypography.body,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: colors.surfaceHigh,
              hintText: '搜索标题或课程',
              hintStyle:
                  AppTypography.body.copyWith(color: colors.textFaint),
              prefixIcon:
                  Icon(Icons.search, size: 18, color: colors.textFaint),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.s12, vertical: AppDimens.s8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(height: AppDimens.s8),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppDimens.s12),
            children: <Widget>[
              _menu<String>(
                context,
                label: course.isEmpty ? '课程：全部课程' : '课程：$course',
                values: <String>['', ...courses],
                labelOf: (String v) => v.isEmpty ? '全部课程' : v,
                onSelected: onCourseChanged,
              ),
              _chip(context,
                  label: '仅看未完成',
                  selected: s.onlyUnfinished,
                  onTap: model.toggleOnlyUnfinished),
              _chip(context,
                  label: '仅看可提交',
                  selected: s.onlySubmittable,
                  onTap: model.toggleOnlySubmittable),
              _menu<ChaoxingSortBy>(
                context,
                label: '排序：${s.sortBy.label}',
                values: ChaoxingSortBy.values,
                labelOf: (ChaoxingSortBy v) => v.label,
                onSelected: model.setSortBy,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimens.s4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.s16),
          child: Text.rich(
            TextSpan(
              style: AppTypography.meta.copyWith(color: colors.textFaint),
              children: <InlineSpan>[
                TextSpan(text: '数据 · ${_ago(model)}'),
                if (model.stale)
                  TextSpan(
                      text: ' · 建议刷新',
                      style:
                          AppTypography.meta.copyWith(color: colors.overdue)),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppDimens.s16, AppDimens.s8, AppDimens.s16, AppDimens.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('${s.tab.label} · ${s.sortBy.label}',
                  style: AppTypography.groupHeader
                      .copyWith(color: colors.textSecondary)),
              Text('$count 项',
                  style:
                      AppTypography.meta.copyWith(color: colors.textFaint)),
            ],
          ),
        ),
      ],
    );
  }

  String _ago(ChaoxingModel model) {
    if (model.fetchedAt == null) return '尚未拉取';
    final int m = model.now.difference(model.fetchedAt!).inMinutes;
    return m < 1 ? '刚刚' : '$m 分钟前';
  }

  Widget _chip(BuildContext context,
      {required String label,
      required bool selected,
      required VoidCallback onTap}) {
    final AppColors colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: AppDimens.s8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        backgroundColor: colors.surfaceHigh,
        selectedColor: colors.accentFaint,
        labelStyle: AppTypography.meta.copyWith(
          color: selected ? colors.accent : colors.textSecondary,
        ),
        side: BorderSide(color: colors.divider),
        onSelected: (bool _) => onTap(),
      ),
    );
  }

  Widget _menu<T>(BuildContext context,
      {required String label,
      required List<T> values,
      required String Function(T) labelOf,
      required void Function(T) onSelected}) {
    final AppColors colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: AppDimens.s8),
      child: PopupMenuButton<T>(
        tooltip: label,
        onSelected: onSelected,
        itemBuilder: (BuildContext _) => values
            .map((T v) => PopupMenuItem<T>(
                value: v,
                height: 40,
                child: Text(labelOf(v), style: AppTypography.body)))
            .toList(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(label,
                style: AppTypography.meta
                    .copyWith(color: colors.textSecondary)),
            Icon(Icons.arrow_drop_down, size: 18, color: colors.textFaint),
          ],
        ),
      ),
    );
  }
}
