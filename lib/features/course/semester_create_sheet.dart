import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/application/timetable_use_case.dart';
import 'package:qingdan/domain/default_timetable.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'semester_create_templates.dart';
import 'semester_switcher.dart' show showSemesterSheetShell;
import 'timetable_library_page.dart';
import 'week_picker_sheet.dart' show weekMondayText;

/// prefs key：新建学期时默认选中的作息模板（§7.2 + 总纲 §五）。
/// **设备本地偏好、不参与同步**——两台设备可以各有默认。
const String kDefaultTemplateIdKey = 'course.defaultTemplateId';

/// 新建学期弹层（M6-D §7.2）。桌面 = 居中弹窗，移动 = 底部抽屉（§2.6）。
/// 返回建出来的学期（直接关掉 = null），调用方（学期面板）拿它刷新列表。
Future<Semester?> showSemesterCreateSheet(
  BuildContext context, {
  required CoursePaneModel model,
  required SemesterUseCase semesters,
  TimetableUseCase? templates,
  required bool isMobile,
}) {
  // 表单比半屏高是常态（日期 + 模板 + 开关 + 回执），自己带滚动。
  final Widget form = SingleChildScrollView(
    padding: const EdgeInsets.only(bottom: AppDimens.s16),
    child: _CreateForm(model: model, semesters: semesters, templates: templates),
  );
  return showSemesterSheetShell<Semester>(context,
      isMobile: isMobile, body: (BuildContext _) => form);
}

class _CreateForm extends StatefulWidget {
  const _CreateForm({
    required this.model,
    required this.semesters,
    required this.templates,
  });

  final CoursePaneModel model;
  final SemesterUseCase semesters;

  /// 模板库用例。装配缺失（没注册 provider）时也必须能建学期：退化成只有
  /// 内置模板一项——内置内容在领域层是常量，不依赖库。
  final TimetableUseCase? templates;

  @override
  State<_CreateForm> createState() => _CreateFormState();
}

class _CreateFormState extends State<_CreateForm> {
  final TextEditingController _name = TextEditingController();
  DateTime _firstWeek = Semester.mondayOf(DateTime.now());
  int _totalWeeks = Semester.defaultTotalWeeks;
  bool _setActive = true;
  List<SemesterTemplateChoice> _choices = const <SemesterTemplateChoice>[];
  String _templateId = kBuiltInTimetableId;

  /// 保存回执。**不能是 SnackBar**：本弹层是 modal route，SnackBar 画在它
  /// 下面那层 Scaffold 上，用户完全看不见（总纲陷阱表第 1 条）。
  String? _said;
  bool _failed = false;
  Semester? _created;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadChoices());
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// 候选 = `templates()`（内置排第一、标「默认」），默认选中 prefs
  /// `course.defaultTemplateId`；那个模板已被删掉时回落到第一项。
  Future<void> _loadChoices() async {
    final List<SemesterTemplateChoice> choices =
        await readTemplateChoices(widget.templates);
    String picked = choices.first.id;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? saved = prefs.getString(kDefaultTemplateIdKey);
      if (saved != null && choices.any((SemesterTemplateChoice c) => c.id == saved)) {
        picked = saved;
      }
    } catch (_) {
      // prefs 读不到（平台通道缺失）只是少个默认值，不该让「新建学期」打不开。
    }
    if (!mounted) return;
    setState(() {
      _choices = choices;
      _templateId = picked;
    });
  }

  bool get _ok => _name.text.trim().isNotEmpty;

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _firstWeek,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '选择开学第一周的任意一天',
    );
    if (picked != null) setState(() => _firstWeek = picked);
  }

  SemesterTemplateChoice get _choice => _choices
      .firstWhere((SemesterTemplateChoice c) => c.id == _templateId,
          orElse: builtinTemplateChoice);

  /// 「管理时间表…」**在本表单之上**再开一层模板库模态，不先关这张表单：用户
  /// 多半就是发现缺一个模板才点过去的，已填的名字/日期不能丢。两层都挂在 root
  /// navigator 上（`showModalBottomSheet` / `showDialog` 默认 useRootNavigator:
  /// true），关掉库里那层就回到这层；库自己内部本来也这么叠（新建 → 逐节编辑）。
  /// 回来重扫候选：库里新建的模板要能立刻被选中（进候选），被删掉的那条不能再
  /// 挂在选中项上。
  Future<void> _openLibrary() async {
    await showTimetableLibrary(context,
        isMobile: MediaQuery.sizeOf(context).width < AppDimens.breakpointNarrow);
    if (!mounted) return;
    final List<SemesterTemplateChoice> cs =
        await readTemplateChoices(widget.templates);
    if (!mounted) return;
    setState(() {
      _choices = cs;
      if (cs.any((SemesterTemplateChoice c) => c.id == _templateId)) return;
      _templateId = cs.first.id;
    });
  }

  Future<void> _save() async {
    final SemesterTemplateChoice choice = _choice;
    try {
      final Semester created = await widget.semesters.createSemester(
          name: _name.text,
          firstWeekDate: _firstWeek,
          totalWeeks: _totalWeeks,
          templateId: choice.id,
          setActive: _setActive);
      // 建完立刻重载：周视图读的是当前学期，不重载就停在旧学期的课上。
      await widget.model.load();
      if (!mounted) return;
      setState(() {
        _created = created;
        _failed = false;
        _said = '已创建「${created.name}」，作息来自「${choice.name}」'
            '（${choice.count} 节）';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _said = '创建被拒绝：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('新建学期', style: AppTypography.panelTitle),
        const SizedBox(height: AppDimens.s12),
        TextField(
          key: const ValueKey<String>('create-name'),
          controller: _name,
          decoration:
              InputDecoration(labelText: '学期名称', errorText: _ok ? null : '必填'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppDimens.s12),
        InkWell(
          key: const ValueKey<String>('create-date'),
          onTap: _pickDate,
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: '开学第一周的任意一天',
              border: OutlineInputBorder(),
            ),
            child: Text(weekMondayText(_firstWeek)),
          ),
        ),
        const SizedBox(height: AppDimens.s12),
        Row(
          children: <Widget>[
            const Text('总周数'),
            const Spacer(),
            IconButton(
              key: const ValueKey<String>('create-weeks-minus'),
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: _totalWeeks > Semester.minTotalWeeks
                  ? () => setState(() => _totalWeeks--)
                  : null,
            ),
            Text('$_totalWeeks',
                key: const ValueKey<String>('create-weeks-value'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16)),
            IconButton(
              key: const ValueKey<String>('create-weeks-plus'),
              icon: const Icon(Icons.add_circle_outline, size: 20),
              onPressed: _totalWeeks < Semester.maxTotalWeeks
                  ? () => setState(() => _totalWeeks++)
                  : null,
            ),
          ],
        ),
        // 候选没读回来之前不给下拉：DropdownButtonFormField 的首值只在第一次
        // build 取，先渲染空 items 会把默认模板永久卡在「未选」。
        if (_choices.isNotEmpty)
          DropdownButtonFormField<String>(
            key: const ValueKey<String>('create-template'),
            // isExpanded：不套 Expanded 时长模板名会把内部 Row 撑爆（S5 实测）。
            isExpanded: true,
            initialValue: _templateId,
            decoration: const InputDecoration(labelText: '作息模板'),
            items: <DropdownMenuItem<String>>[
              for (final SemesterTemplateChoice c in _choices)
                DropdownMenuItem<String>(value: c.id, child: Text(c.label)),
            ],
            onChanged: (String? v) =>
                v == null ? null : setState(() => _templateId = v),
          ),
        SwitchListTile(
          key: const ValueKey<String>('create-set-active'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('创建后设为当前学期'),
          value: _setActive,
          onChanged: (bool v) => setState(() => _setActive = v),
        ),
        // §7.2 契约的「管理时间表… → §7.3」这一行。模板用例没装配（`templates`
        // 为 null = 只剩内置模板那条退化路径）时**整行不出现**：那个壳里
        // `context.read<TimetableUseCase>()` 会当场抛，比没有这行更糟。
        if (widget.templates != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
                key: const ValueKey<String>('create-manage-timetable'),
                onPressed: _openLibrary,
                child: const Text('管理时间表…')),
          ),
        if (_said != null)
          Text(_said!,
              key: const ValueKey<String>('create-said'),
              style: AppTypography.meta.copyWith(
                  color: _failed ? colors.overdue : colors.textSecondary)),
        const SizedBox(height: AppDimens.s8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              key: const ValueKey<String>('create-close'),
              onPressed: () => Navigator.of(context).pop(_created),
              child: Text(_created == null ? '取消' : '完成'),
            ),
            const SizedBox(width: AppDimens.s8),
            FilledButton(
              key: const ValueKey<String>('create-save'),
              onPressed: _ok ? _save : null,
              child: const Text('保存'),
            ),
          ],
        ),
      ],
    );
  }
}
