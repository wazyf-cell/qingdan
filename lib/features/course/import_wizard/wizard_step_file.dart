// 步 1：选文件（§4.2 步骤 1）。
//
// 桌面给大块点击入口，移动端给按钮。选定后必须显式报出**编码结论行**
// （§3.1:162），并允许手动切换编码重读。
// §4.2 原文还要桌面支持「窗口内拖拽投放」——首版未做，见文件内 _PickEntry 注释。

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/import/course/schedule_file.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

import 'import_wizard_model.dart';
import 'wizard_file_picker.dart';

class WizardStepFile extends StatelessWidget {
  const WizardStepFile({super.key, required this.isMobile, this.loadFile});

  final bool isMobile;

  /// 注入点：测试里塞假实现，绕开系统对话框。
  final ScheduleFileLoader? loadFile;

  Future<void> _pick(BuildContext context) async {
    final ImportWizardModel model = context.read<ImportWizardModel>();
    final ({String name, Uint8List bytes})? picked =
        await (loadFile ?? pickScheduleFile)();
    if (picked == null || !context.mounted) return;
    model.loadFile(fileName: picked.name, bytes: picked.bytes);
  }

  @override
  Widget build(BuildContext context) {
    final ImportWizardModel model = context.watch<ImportWizardModel>();
    final AppColors colors = AppColors.of(context);
    final ScheduleTable? table = model.table;
    return Padding(
      padding: const EdgeInsets.all(AppDimens.panelPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (isMobile)
            FilledButton.icon(
              key: const ValueKey<String>('pick-file'),
              onPressed: () => _pick(context),
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('选择课表文件（xlsx / csv / WakeUp 导出）'),
            )
          else
            _PickEntry(colors: colors, onPick: () => _pick(context)),
          const SizedBox(height: AppDimens.s16),
          if (model.fileError != null)
            Text(model.fileError!,
                style: TextStyle(color: colors.overdue, fontSize: 13)),
          if (table != null) ...<Widget>[
            _FileSummary(
              fileName: model.fileName ?? '',
              columns: table.rows.isEmpty ? 0 : table.rows.first.length,
              dataRows: table.dataRowCount,
              encodingLine: '已按 ${describeEncoding(table.encoding)} 读取',
            ),
            const SizedBox(height: AppDimens.s12),
            Align(
              alignment: Alignment.centerLeft,
              child: _EncodingSwitcher(colors: colors),
            ),
          ],
          // 原来这里写「支持从微信 / 文件管理器『用其他应用打开』发送到本应用」，
          // 但清单只有一个 MAIN/LAUNCHER intent-filter、没有 FileProvider，
          // 那句话是假的（2026-10-18 定案第 15 条：删文案，真做属后续）。
        ],
      ),
    );
  }
}

/// 编码结论行 + 手动切换重读。
class _EncodingSwitcher extends StatelessWidget {
  const _EncodingSwitcher({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final ImportWizardModel model = context.read<ImportWizardModel>();
    return Wrap(
      spacing: AppDimens.s8,
      children: <Widget>[
        for (final FileEncoding e in FileEncoding.values)
          TextButton(
            key: ValueKey<String>('encoding-${e.name}'),
            onPressed: () => model.reloadWith(e),
            child: Text('按 ${describeEncoding(e)} 重读',
                style: TextStyle(fontSize: 12, color: colors.accent)),
          ),
      ],
    );
  }
}

class _FileSummary extends StatelessWidget {
  const _FileSummary({
    required this.fileName,
    required this.columns,
    required this.dataRows,
    required this.encodingLine,
  });

  final String fileName;
  final int columns;
  final int dataRows;
  final String encodingLine;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(AppDimens.s12),
      decoration: BoxDecoration(
        color: colors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(fileName,
              key: const ValueKey<String>('file-name'),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppDimens.s4),
          Text('检测到 $columns 列、$dataRows 行数据',
              key: const ValueKey<String>('file-shape'),
              style: TextStyle(color: colors.textSecondary, fontSize: 12)),
          Text(encodingLine,
              key: const ValueKey<String>('file-encoding'),
              style: TextStyle(color: colors.success, fontSize: 12)),
        ],
      ),
    );
  }
}

/// 桌面端的大块投放入口。**首版只做点击选择**——真正的「拖文件进窗口」需要
/// `desktop_drop` 一类新插件（未获同意不加，见变更日志 S5-b 勘误）。
class _PickEntry extends StatelessWidget {
  const _PickEntry({required this.colors, required this.onPick});

  final AppColors colors;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const ValueKey<String>('pick-file'),
      onTap: onPick,
      borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
      child: Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
          border: Border.all(color: colors.divider, width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.upload_file, size: 28, color: colors.textSecondary),
            const SizedBox(height: AppDimens.s8),
            const Text('点击选择课表文件'),
            const SizedBox(height: AppDimens.s4),
            Text('支持 .xlsx 与 .csv',
                style: TextStyle(fontSize: 12, color: colors.textFaint)),
          ],
        ),
      ),
    );
  }
}
