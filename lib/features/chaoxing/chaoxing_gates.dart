/// 学习通面板的三种占位态：未登录、空列表、错误横幅。
library;

import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'chaoxing_keys.dart';

class ChaoxingLoginGate extends StatelessWidget {
  const ChaoxingLoginGate({super.key, required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Center(
      key: ChaoxingKeys.vkey(ChaoxingKeys.login),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.school_outlined, size: 48, color: colors.textFaint),
          const SizedBox(height: AppDimens.s12),
          Text('登录一次超星账号，这里就会列出还没交的作业和考试',
              style: AppTypography.meta.copyWith(color: colors.textSecondary)),
          const SizedBox(height: AppDimens.s16),
          FilledButton(onPressed: onLogin, child: const Text('登录学习通')),
        ],
      ),
    );
  }
}

/// 空列表要能分清三种情况：正在拉 / 会话没通（0 门课）/ 拉到了但被筛掉了。
class ChaoxingEmpty extends StatelessWidget {
  const ChaoxingEmpty({
    super.key,
    required this.loading,
    required this.courses,
    required this.activities,
    required this.filteredOut,
  });

  final bool loading;
  final int courses;
  final int activities;

  /// 拉到了条目但当前筛选下全被过滤掉（M6B §B1 后筛选住在弹层里，不在头部）。
  final bool filteredOut;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final String text = loading
        ? '正在拉取…'
        : courses == 0
            ? '没拉到任何课程（会话可能没通，或账号下没有课）'
            : filteredOut
                ? '当前筛选下没有条目（共 $activities 条活动）——'
                    '点右上角「筛选」把开关放回来'
                : '没有有效待办（$courses 门课 · 共 $activities 条活动）';
    return Center(
      key: ChaoxingKeys.vkey(ChaoxingKeys.empty),
      child: loading
          ? const CircularProgressIndicator()
          // 下拉刷新已取消（M6B §B7），所以不再强制 AlwaysScrollableScrollPhysics。
          : ListView(
              children: <Widget>[
                const SizedBox(height: 120),
                Center(
                  child: Text(text,
                      textAlign: TextAlign.center,
                      style: AppTypography.meta
                          .copyWith(color: colors.textFaint)),
                ),
              ],
            ),
    );
  }
}

class ChaoxingBanner extends StatelessWidget {
  const ChaoxingBanner(
      {super.key,
      required this.text,
      required this.actionLabel,
      required this.onAction});

  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Container(
      key: ChaoxingKeys.vkey(ChaoxingKeys.banner),
      color: colors.surfaceHigh,
      padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.s16, vertical: AppDimens.s8),
      child: Row(
        children: <Widget>[
          Expanded(
              child: Text(text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      AppTypography.meta.copyWith(color: colors.overdue))),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
