// 导入向导外壳（§4.2）：顶部步骤指示器 + 当前步内容 + 底部「上一步 / 下一步」。
//
// 桌面 = 居中大弹窗（一步一屏，指示器在顶部）；移动 = 全屏页（Stepper 式）。
// 五步的状态与业务逻辑全在 [ImportWizardModel]，本文件只做导航与布局壳。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/features/course/course_pane_model.dart';
import 'package:qingdan/import/course/schedule_file.dart';
import 'package:qingdan/import/course/import_service.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

import 'import_wizard_model.dart';
import 'import_wizard_types.dart';
import 'wizard_shell_parts.dart';
import 'wizard_file_picker.dart';
import 'wizard_step_confirm.dart';
import 'wizard_step_correct.dart';
import 'wizard_step_file.dart';
import 'wizard_step_mapping.dart';
import 'wizard_step_setup.dart';

/// 打开导入向导。[loadFile] 只给测试注入假实现用；[scraped] 给「从教务系统
/// 抓取」那条链用——直接进列映射步，后面五步完全同一条路。
Future<void> showImportWizard(BuildContext context,
    {ScheduleFileLoader? loadFile, ScheduleTable? scraped}) {
  final bool isMobile =
      MediaQuery.sizeOf(context).width < AppDimens.breakpointNarrow;
  // ImportService 由装配根（main.dart）提供；UI 拿不到 DAO。
  final ImportService importer = context.read<ImportService>();
  final CoursePaneModel pane = context.read<CoursePaneModel>();
  final Widget page = ImportWizardPage(
      isMobile: isMobile,
      importer: importer,
      pane: pane,
      loadFile: loadFile,
      scraped: scraped);
  return isMobile
      ? Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => page))
      : showDialog<void>(context: context, builder: (_) => page);
}

class ImportWizardPage extends StatefulWidget {
  const ImportWizardPage({
    super.key,
    required this.isMobile,
    required this.importer,
    required this.pane,
    this.loadFile,
    this.scraped,
  });

  final bool isMobile;
  final ImportService importer;
  final CoursePaneModel pane;
  final ScheduleFileLoader? loadFile;
  final ScheduleTable? scraped;

  @override
  State<ImportWizardPage> createState() => _ImportWizardPageState();
}

class _ImportWizardPageState extends State<ImportWizardPage> {
  late final ImportWizardModel _model = ImportWizardModel(
      importer: widget.importer,
      semester: widget.pane.semester,
      details: widget.pane.details);

  static const List<String> _titles = <String>[
    '文件', '映射', '学期作息', '校正', '导入',
  ];

  @override
  void initState() {
    super.initState();
    final ScheduleTable? scraped = widget.scraped;
    if (scraped == null) return;
    _model.loadTable(fileName: '教务系统抓取（强智课表页）', table: scraped);
    _model.guessMapping();
    _model.go(WizardStep.mapping);
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    switch (_model.step) {
      case WizardStep.file:
        _model.guessMapping();
        _model.go(WizardStep.mapping);
      case WizardStep.mapping:
        _model.go(WizardStep.setup);
      case WizardStep.setup:
        _model.buildRows();
      case WizardStep.correct:
        await _model.preparePlan();
        _model.go(WizardStep.confirm);
      case WizardStep.confirm:
        if (_model.result == null) {
          final bool ok = await _model.finish();
          if (ok) await _raiseSemesterWeeks();
        } else {
          await widget.pane.load();
          if (mounted) Navigator.of(context).pop();
        }
    }
  }

  /// 课排到学期外面时把总周数抬上去（2026-10-18 定案）。
  ///
  /// 不抬的后果不是数据错，是**数据看不见**：周数是翻页上限，排在第 19 周的课
  /// 静静躺在库里，› 按钮在第 16 周就灰了。教务抓取那条路拿不到总周数（强智那张
  /// 表里没有这个字段），所以只能在这里兜。
  Future<void> _raiseSemesterWeeks() async {
    final Semester? s = _model.semester;
    if (s == null || _model.maxImportedWeek <= s.totalWeeks) return;
    final Semester? after = await context
        .read<SemesterUseCase>()
        .raiseTotalWeeks(_model.maxImportedWeek);
    if (after == null) return;
    _model.semester = after;
    _model.weeksRaisedTo = after.totalWeeks;
  }

  Future<void> _back() => _jumpTo(_model.step.index - 1);

  /// 回跳。目标若是映射步且已经做过校正，先问一句——映射一改，行就全变了，
  /// 步 4 的校正必须作废重算（§3.1:168）。
  Future<void> _jumpTo(int index) async {
    if (index < 0 || index >= _model.step.index) return;
    final WizardStep target = WizardStep.values[index];
    if (target.index <= WizardStep.mapping.index && _model.rows.isNotEmpty) {
      final bool ok = await _confirmDiscardCorrections();
      if (!ok) return;
    }
    _model.backTo(target);
  }

  Future<bool> _confirmDiscardCorrections() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('返回会丢失已做的校正'),
        content: const Text('改了列映射后，每行解析结果都会重算，'
            '之前的修正与忽略都需要重做。确定返回？'),
        actions: <Widget>[
          TextButton(
              key: const ValueKey<String>('back-cancel'),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
              key: const ValueKey<String>('back-confirm'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('确定返回')),
        ],
      ),
    );
    return ok ?? false;
  }

  bool get _nextEnabled => switch (_model.step) {
        WizardStep.file => _model.hasFile,
        WizardStep.mapping => _model.mappingReady,
        WizardStep.setup => _model.setupReady,
        WizardStep.correct => _model.gateOpen,
        WizardStep.confirm =>
          _model.result != null || _model.plan != null,
      };

  String get _nextLabel => switch (_model.step) {
        WizardStep.confirm =>
          _model.result == null ? '开始导入' : '完成',
        WizardStep.setup => '下一步：校正',
        _ => '下一步',
      };

  @override
  Widget build(BuildContext context) {
    // 外壳自己必须订阅模型：步骤切换是 `_model.step` 驱动的，只把模型塞进
    // provider 而这里不 watch 的话，「下一步」改了状态但界面不重建
    // （端到端测试第一次点下一步就没走到步 2，就是这么发现的）。
    return ListenableBuilder(
      listenable: _model,
      builder: (BuildContext context, Widget? _) => _page(context),
    );
  }

  Widget _page(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        WizardStepIndicator(
            model: _model,
            colors: colors,
            titles: _titles,
            onJump: _jumpTo),
        Expanded(child: _body()),
        WizardFooter(
            model: _model,
            colors: colors,
            enabled: _nextEnabled,
            label: _nextLabel,
            onNext: _next,
            onBack: _back),
      ],
    );
    return ChangeNotifierProvider<ImportWizardModel>.value(
      value: _model,
      child: widget.isMobile
          ? Scaffold(
              appBar: AppBar(title: const Text('导入课表')),
              body: SafeArea(child: body),
            )
          : Dialog(
              insetPadding:
                  const EdgeInsets.all(AppDimens.s24),
              child: SizedBox(width: 860, height: 600, child: body)),
    );
  }

  Widget _body() {
    return switch (_model.step) {
      WizardStep.file =>
        WizardStepFile(isMobile: widget.isMobile, loadFile: widget.loadFile),
      WizardStep.mapping => const WizardStepMapping(),
      WizardStep.setup => WizardStepSetup(isMobile: widget.isMobile),
      WizardStep.correct => WizardStepCorrect(isMobile: widget.isMobile),
      WizardStep.confirm =>
        WizardStepConfirm(isMobile: widget.isMobile),
    };
  }
}

