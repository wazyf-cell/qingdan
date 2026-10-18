// 步 5：确认导入（§4.2 步骤 5、§3.5 红字口径）。
//
// 首次导入**隐藏模式选择**并默认「合并」（§3.1:166）；覆盖模式只给一行红字
// 告知将移除多少条，不做逐条确认弹窗（§3.5 末）。落库成功后切到汇总页。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/import/course/import_service.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

import 'import_wizard_model.dart';

class WizardStepConfirm extends StatelessWidget {
  const WizardStepConfirm({super.key, required this.isMobile});

  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final ImportWizardModel model = context.watch<ImportWizardModel>();
    return model.result == null
        ? _BeforeImport(model: model, isMobile: isMobile)
        : _Summary(model: model);
  }
}

class _BeforeImport extends StatelessWidget {
  const _BeforeImport({required this.model, required this.isMobile});

  final ImportWizardModel model;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final ImportPlan? plan = model.plan;
    return Padding(
      padding: const EdgeInsets.all(AppDimens.panelPadding),
      child: ListView(
        children: <Widget>[
          Text('共 ${model.importableCourses.length} 行将写入'
              '（已忽略 ${model.ignoredCount} · 已删除 ${model.deletedCount} 行）',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppDimens.s12),
          if (!model.hadImportedBefore)
            Text('这是该学期的首次导入，按「合并」执行。',
                key: const ValueKey<String>('mode-hidden'),
                style: TextStyle(color: colors.textSecondary, fontSize: 13))
          else
            for (final ImportMode m in ImportMode.values)
              _ModeCard(
                mode: m,
                selected: model.mode == m,
                onTap: () => model.setMode(m),
              ),
          if (plan != null && model.mode == ImportMode.overwrite)
            Padding(
              padding: const EdgeInsets.only(top: AppDimens.s12),
              child: Text(
                  '将移除现有 ${plan.willRemoveImported} 条导入课程'
                  '（手动添加的 ${plan.activeManualCount} 条不受影响）',
                  key: const ValueKey<String>('overwrite-warning'),
                  style: TextStyle(color: colors.overdue, fontSize: 13)),
            ),
          if (plan != null) ...<Widget>[
            const SizedBox(height: AppDimens.s16),
            Text('预计：新增 ${plan.insert.length} · 更新 ${plan.update.length}'
                ' · 跳过 ${plan.skipped.length + plan.duplicated.length}',
                style: TextStyle(color: colors.textSecondary, fontSize: 13)),
          ],
          if (model.finishError != null) ...<Widget>[
            const SizedBox(height: AppDimens.s12),
            Text('导入失败：${model.finishError}',
                style: TextStyle(color: colors.overdue)),
          ],
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard(
      {required this.mode, required this.selected, required this.onTap});

  final ImportMode mode;
  final bool selected;
  final VoidCallback onTap;

  static const Map<ImportMode, String> _hint = <ImportMode, String>{
    ImportMode.merge: '已有的课按文件值更新老师/地点，库里独有的课不动',
    ImportMode.overwrite: '先清空该学期所有导入课，再按文件重建（手动课保留）',
    ImportMode.appendOnly: '只把库里没有的课加进来，其余全部跳过',
  };

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppDimens.s8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
        side: BorderSide(
            color: selected ? colors.accent : colors.divider,
            width: selected ? 2 : 1),
      ),
      child: ListTile(
        key: ValueKey<String>('mode-${mode.name}'),
        onTap: onTap,
        leading: Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 20,
            color: selected ? colors.accent : colors.textFaint),
        title: Text(describeImportMode(mode)),
        subtitle: Text(_hint[mode]!,
            style: TextStyle(fontSize: 12, color: colors.textSecondary)),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.model});

  final ImportWizardModel model;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final ({int inserted, int updated, int skipped, int removed}) r =
        model.result!;
    return Padding(
      padding: const EdgeInsets.all(AppDimens.panelPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('导入完成',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppDimens.s12),
          Text('新增 ${r.inserted} · 更新 ${r.updated} · 跳过 ${r.skipped}'
              '${r.removed > 0 ? ' · 移除 ${r.removed}' : ''}',
              key: const ValueKey<String>('import-summary'),
              style: TextStyle(fontSize: 14, color: colors.textPrimary)),
          const SizedBox(height: AppDimens.s8),
          Text('按「${describeImportMode(model.mode)}」模式执行',
              style: TextStyle(fontSize: 12, color: colors.textSecondary)),
          // 抬过周数必须说一声：它是「这次导入顺手改了学期设置」这件事的唯一痕迹。
          if (model.weeksRaisedTo != null)
            Padding(
              padding: const EdgeInsets.only(top: AppDimens.s8),
              child: Text(
                  '学期总周数已扩到 ${model.weeksRaisedTo} 周'
                  '（有课排在原来那个周数之外）',
                  key: const ValueKey<String>('weeks-raised'),
                  style: TextStyle(fontSize: 12, color: colors.textSecondary)),
            ),
        ],
      ),
    );
  }
}
