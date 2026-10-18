import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 设置二级页外壳：顶栏写节名 + 一节内容（整页独立滚动）。
///
/// 单独成文件是为了让「节组件」能反向跳（通用页里的「通知权限」要能推开通知节），
/// 而不用 import 一级页 `settings_page.dart` —— 那样会绕成一个循环。
class SettingsSectionPage extends StatelessWidget {
  const SettingsSectionPage(
      {super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colors.surface,
        foregroundColor: colors.textSecondary,
        titleTextStyle: AppTypography.pageTitle.copyWith(
            fontSize: 17, color: colors.textPrimary),
        title: Text(title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: colors.divider),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimens.panelPadding),
        child: child,
      ),
    );
  }
}

/// 推开一个设置二级页。`showTitle: false`：顶栏已经写了节名。
Future<void> pushSettingsSection(
  BuildContext context, {
  required String title,
  required Widget Function(bool showTitle) content,
}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (BuildContext _) => SettingsSectionPage(
        title: title,
        child: content(false),
      ),
    ));
