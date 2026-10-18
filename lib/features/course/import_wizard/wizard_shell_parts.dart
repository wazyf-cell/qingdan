// 向导外壳的两块零件：顶部步骤指示器与底部导航条。
//
// 与 `import_wizard.dart` 分文件是因为合起来过了 300 行硬红线。

import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

import 'import_wizard_model.dart';
import 'import_wizard_types.dart';

class WizardStepIndicator extends StatelessWidget {
  const WizardStepIndicator(
      {super.key, required this.model,
      required this.colors,
      required this.titles,
      required this.onJump});

  final ImportWizardModel model;
  final AppColors colors;
  final List<String> titles;
  final void Function(int index) onJump;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.s12, vertical: AppDimens.s8),
      // Wrap 而非 Row：411dp 上五个步骤标签加连接线放不下（实测溢出 27px），
      // 让它自然换行比缩字号稳。
      child: Wrap(
        spacing: 2,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          for (int i = 0; i < titles.length; i++) ...<Widget>[
            if (i > 0)
              Container(width: 12, height: 1, color: colors.divider),
            WizardStepChip(
              index: i,
              title: titles[i],
              state: _stateOf(i),
              onTap: _stateOf(i) == WizardStepState.done
                  ? () => onJump(i)
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  WizardStepState _stateOf(int index) {
    if (index < model.step.index) return WizardStepState.done;
    if (index == model.step.index) return WizardStepState.current;
    return WizardStepState.todo;
  }
}

enum WizardStepState { done, current, todo }

class WizardStepChip extends StatelessWidget {
  const WizardStepChip(
      {super.key, required this.index,
      required this.title,
      required this.state,
      this.onTap});

  final int index;
  final String title;
  final WizardStepState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Color color = switch (state) {
      WizardStepState.current => colors.accent,
      WizardStepState.done => colors.textSecondary,
      WizardStepState.todo => colors.textFaint,
    };
    return InkWell(
      key: ValueKey<String>('step-$index'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.s8, vertical: AppDimens.s4),
        child: Text('${index + 1}·$title',
            style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: state == WizardStepState.current
                    ? FontWeight.w700
                    : FontWeight.w400)),
      ),
    );
  }
}

class WizardFooter extends StatelessWidget {
  const WizardFooter({
    super.key,
    required this.model,
    required this.colors,
    required this.enabled,
    required this.label,
    required this.onNext,
    required this.onBack,
  });

  final ImportWizardModel model;
  final AppColors colors;
  final bool enabled;
  final String label;
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDimens.s12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: <Widget>[
          if (model.step != WizardStep.file)
            TextButton(
                key: const ValueKey<String>('wizard-back'),
                onPressed: onBack,
                child: const Text('← 上一步')),
          const Spacer(),
          FilledButton(
              key: const ValueKey<String>('wizard-next'),
              onPressed: enabled ? onNext : null,
              child: Text(label)),
        ],
      ),
    );
  }
}
