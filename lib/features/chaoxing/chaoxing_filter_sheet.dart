/// 学习通筛选弹层（M6B §B1）：搜索 / 课程 / 仅看未完成 / 仅看可提交 / 排序
/// 从原来的常驻工具栏整体搬进来，面板头才压得进一行 52dp。
///
/// **来源声明**（AGENTS.md 禁止事项要求逐个文件标注）：弹层里排序与两个筛选开关的
/// 取值取自用户的油猴脚本 `扩展/作业列表.js`（上游 https://github.com/Cooanyh/chaoxing-list，
/// AGPL-3.0-or-later，作者 lcandy2 / Coren）——排序档位 `sortOptions` :3258-3264
/// （本文件下方引用的是同一段），「未完成 / 可提交」两条筛选的判据见智能排序
/// :3283 与默认排序注释 :3352。只重写「弹层里放哪几项、每档叫什么」这层视图语义，
/// 未拷贝其 Vue 模板与遥测代码；界面是本项目自己画的（扩展的工具栏在网页里）。
///
/// 四条实现约定：
/// - 开关与排序**即时生效**（改完就写 prefs），「完成」只负责关弹层，不搞草稿态；
///   「重置」清掉筛选但不动页签与隐藏集（`ChaoxingModel.resetFilters`）。
/// - 搜索控制器由面板持有并传进来：在弹层里 new 出来、`await` 之后再 dispose，
///   就是 S5-f 真机那条「开着键盘点确定/取消/遮罩必红屏」的根因。
/// - 弹层是独立路由，面板 setState 不会重建它，所以搜索/课程的变化要在**本层**
///   再 setState 一次，否则「N 项」统计行会停在旧数字。
/// - 「当前 页签 · 排序 · N 项」用回调现算，弹层自己不需要会筛。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'chaoxing_grouping.dart';
import 'chaoxing_keys.dart';
import 'chaoxing_model.dart';

Future<void> showChaoxingFilter(
  BuildContext context, {
  required TextEditingController search,
  required ValueChanged<String> onSearchChanged,
  required String course,
  required ValueChanged<String> onCourseChanged,
  required List<String> courses,
  required int Function() count,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => Padding(
        // 键盘弹起时把整块顶上去，否则「完成」按钮会被挡住（S4b 真机教训）。
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (BuildContext _, ScrollController controller) => _FilterBody(
            search: search,
            onSearchChanged: onSearchChanged,
            course: course,
            onCourseChanged: onCourseChanged,
            courses: courses,
            count: count,
            controller: controller,
          ),
        ),
      ),
    );

class _FilterBody extends StatefulWidget {
  const _FilterBody({
    required this.search,
    required this.onSearchChanged,
    required this.course,
    required this.onCourseChanged,
    required this.courses,
    required this.count,
    required this.controller,
  });

  final TextEditingController search;
  final ValueChanged<String> onSearchChanged;
  final String course;
  final ValueChanged<String> onCourseChanged;
  final List<String> courses;
  final int Function() count;
  final ScrollController controller;

  @override
  State<_FilterBody> createState() => _FilterBodyState();
}

class _FilterBodyState extends State<_FilterBody> {
  /// 下拉的选中值本层也要存一份：弹层不会被面板的重建刷新。
  late String _course = widget.course;

  void _setCourse(String value) {
    setState(() => _course = value);
    widget.onCourseChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Consumer<ChaoxingModel>(
      builder: (BuildContext _, ChaoxingModel model, Widget? _) {
        final ChaoxingViewSettings s = model.settings;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // 统计行与「重置 / 完成」固定在弹层底部：411×915 的 0.55 弹层里
            // 排序五档已经贴到视口下缘，若把它们也排进滚动列表，「完成」会
            // 落在视口外（真机上表现为「弹层关不掉」，测试里表现为 off-screen）。
            Expanded(
              child: ListView(
                controller: widget.controller,
                padding: const EdgeInsets.fromLTRB(
                    AppDimens.s16, 0, AppDimens.s16, AppDimens.s12),
                children: <Widget>[
                  Text('筛选', style: AppTypography.panelTitle),
                  const SizedBox(height: AppDimens.s12),
                  _searchField(colors),
                  const SizedBox(height: AppDimens.s12),
                  _courseField(colors),
                  SwitchListTile(
                    key: ChaoxingKeys.vkey(ChaoxingKeys.filterUnfinished),
                    contentPadding: EdgeInsets.zero,
                    title: Text('仅看未完成', style: AppTypography.body),
                    value: s.onlyUnfinished,
                    onChanged: (bool v) => model.toggleOnlyUnfinished(),
                  ),
                  SwitchListTile(
                    key: ChaoxingKeys.vkey(ChaoxingKeys.filterSubmittable),
                    contentPadding: EdgeInsets.zero,
                    title: Text('仅看可提交', style: AppTypography.body),
                    value: s.onlySubmittable,
                    onChanged: (bool v) => model.toggleOnlySubmittable(),
                  ),
                  const SizedBox(height: AppDimens.s4),
                  Text('排序',
                      style: AppTypography.groupHeader
                          .copyWith(color: colors.textSecondary)),
                  // 五档照抄扩展（脚本 :3258-3265）；用单选列表而不是 SegmentedButton：
                  // 五段在 411dp 宽里放不下。
                  // groupValue / onChanged 挂在 RadioGroup 上——3.32 之后
                  // RadioListTile 的同名参数已被标记废弃，用它们会带红 flutter analyze。
                  RadioGroup<ChaoxingSortBy>(
                    groupValue: s.sortBy,
                    onChanged: (ChaoxingSortBy? next) {
                      if (next != null) model.setSortBy(next);
                    },
                    child: Column(
                      key: ChaoxingKeys.vkey(ChaoxingKeys.filterSort),
                      children: ChaoxingSortBy.values
                          .map((ChaoxingSortBy v) => RadioListTile<ChaoxingSortBy>(
                                key: ChaoxingKeys.vkey(
                                    ChaoxingKeys.sortOption(v.name)),
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: Text(v.label, style: AppTypography.body),
                                value: v,
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppDimens.s16, 0, AppDimens.s16, AppDimens.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    key: ChaoxingKeys.vkey(ChaoxingKeys.filterCount),
                    '${s.tab.label} · ${s.sortBy.label} · ${widget.count()} 项',
                    style: AppTypography.meta.copyWith(color: colors.textFaint),
                  ),
                  const SizedBox(height: AppDimens.s12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      TextButton(
                        key: ChaoxingKeys.vkey(ChaoxingKeys.filterReset),
                        onPressed: () {
                          model.resetFilters();
                          widget.search.clear();
                          widget.onSearchChanged('');
                          _setCourse('');
                        },
                        child: const Text('重置'),
                      ),
                      const SizedBox(width: AppDimens.s8),
                      FilledButton(
                        key: ChaoxingKeys.vkey(ChaoxingKeys.filterApply),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('完成'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _searchField(AppColors colors) {
    return TextField(
      key: ChaoxingKeys.vkey(ChaoxingKeys.filterSearch),
      controller: widget.search,
      onChanged: (String v) {
        setState(() {}); // 统计行跟着变
        widget.onSearchChanged(v);
      },
      style: AppTypography.body,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: colors.surfaceHigh,
        hintText: '搜索标题或课程',
        hintStyle: AppTypography.body.copyWith(color: colors.textFaint),
        prefixIcon: Icon(Icons.search, size: 18, color: colors.textFaint),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppDimens.s12, vertical: AppDimens.s8),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none),
      ),
    );
  }

  /// 课程下拉：`isExpanded` + 单行省略，避免 S5-d 那条「dense 模式长文案撑爆
  /// 内部 Row」的坑（课程名可能很长）。
  Widget _courseField(AppColors colors) {
    final List<String> values = <String>['', ...widget.courses];
    return DropdownButtonFormField<String>(
      key: ChaoxingKeys.vkey(ChaoxingKeys.filterCourse),
      initialValue: values.contains(_course) ? _course : '',
      isExpanded: true,
      isDense: true,
      decoration: const InputDecoration(
          isDense: true, labelText: '课程', border: OutlineInputBorder()),
      style: AppTypography.body,
      items: <DropdownMenuItem<String>>[
        DropdownMenuItem<String>(
            value: '',
            child: Text('全部课程',
                style:
                    AppTypography.body.copyWith(color: colors.textSecondary))),
        ...widget.courses.map((String c) => DropdownMenuItem<String>(
            value: c,
            child: Text(c, maxLines: 1, overflow: TextOverflow.ellipsis))),
      ],
      onChanged: (String? v) => _setCourse(v ?? ''),
    );
  }
}
