import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/features/settings/first_run_guide.dart';
import 'package:qingdan/features/settings/settings_model.dart';
import 'package:qingdan/features/shell/app_shell.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_theme.dart';
import 'package:qingdan/theme/app_typography.dart';
import 'package:qingdan/theme/theme_mode_model.dart';

/// M1 界面第一入口的根组件：装配主题与主窗口壳。
///
/// 供 `main.dart` 与 widget 冒烟测试复用；[dbInitError] 非空时
/// 渲染初始化失败页（数据库异常不得静默吞掉，见 main.dart）。
/// [themeModel] 由 main 构造（已恢复持久化主题）后注入，null 时
/// 内部自建（测试场景）。
class QingdanApp extends StatelessWidget {
  const QingdanApp({super.key, this.dbInitError, this.themeModel});

  /// 数据库初始化失败的摘要（null = 正常）。
  final String? dbInitError;

  /// 外部注入的主题模型（main 中已恢复持久化值）。
  final ThemeModeModel? themeModel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ThemeModeModel>(
      create: (_) => themeModel ?? ThemeModeModel(ThemeMode.system),
      child: Consumer<ThemeModeModel>(
        builder: (BuildContext context, ThemeModeModel theme, _) {
          return MaterialApp(
            title: 'qingdan',
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: theme.mode,
            home: dbInitError == null
                ? const _FirstRunGate(child: AppShell())
                : _DbInitErrorScreen(message: dbInitError!),
          );
        },
      ),
    );
  }
}

/// 数据库初始化失败页：完整报错原文呈现，不静默。
class _DbInitErrorScreen extends StatelessWidget {
  const _DbInitErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('数据库初始化失败，应用无法启动',
                  style: AppTypography.panelTitle
                      .copyWith(color: colors.overdue)),
              const SizedBox(height: 12),
              SelectableText(message,
                  style: AppTypography.meta
                      .copyWith(color: colors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 首启引导的挂载点（M6-C6）：首帧之后弹一次，两个按钮都置 `ui.guideSeen`。
///
/// 为什么挂在 `home` 外面而不是 `main.dart` 里：弹框要一个**在 MaterialApp 之下**的
/// `BuildContext`（拿 Navigator 与主题），而 `runApp` 之前根本没有这样的 context。
class _FirstRunGate extends StatefulWidget {
  const _FirstRunGate({required this.child});

  final Widget child;

  @override
  State<_FirstRunGate> createState() => _FirstRunGateState();
}

class _FirstRunGateState extends State<_FirstRunGate> {
  @override
  void initState() {
    super.initState();
    // 等第一帧画完再弹：启动路径上任何 await 都会把首屏拖慢，而引导框晚一帧无感。
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  Future<void> _show() async {
    if (!mounted) return;
    final SettingsModel? settings = context.read<SettingsModel?>();
    if (settings == null) return; // 纯 UI 冒烟测试没装配设置层时照常启动
    await maybeShowFirstRunGuide(context, settings);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
