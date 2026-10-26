/// 学习通面板的全部动作：登录 / 重新登录 / 退出登录 / 隐藏一条 / 看详情 / 隐藏列表。
///
/// 收在一处的原因（M6B §B5）：隐藏这条动作有三个入口（滑动按钮、长按、
/// 将来可能有批量），而「生效期要不要弹确认」必须与卡片着色共用同一个判定，
/// 分散写必漂。三个 launcher 是可替换变量，widget 测试里换成假实现
/// （真实 WebView 在测试环境会抛 MissingPluginException）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/features/common/app_toast.dart';
import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/import/chaoxing/chaoxing_time.dart';
import 'package:qingdan/notify/reminder_coordinator.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'chaoxing_detail_page.dart';
import 'chaoxing_hidden_page.dart';
import 'chaoxing_login.dart';
import 'chaoxing_model.dart';
import 'chaoxing_notify_hook.dart';

typedef ChaoxingLoginLauncher = Future<String?> Function(BuildContext context);
typedef ChaoxingDetailLauncher = void Function(
    BuildContext context, ChaoxingTask task);
typedef ChaoxingCookieJarCleaner = Future<void> Function();

/// 测试注入点（登录页是 WebView，测试环境起不了平台通道）。
ChaoxingLoginLauncher chaoxingLoginLauncher = showChaoxingLogin;
ChaoxingDetailLauncher chaoxingDetailLauncher = showChaoxingDetail;
ChaoxingCookieJarCleaner chaoxingCookieJarCleaner = clearChaoxingCookieJar;

/// 登录一次超星：WebView 里用户自己登，成功后 cookie 进系统凭据库并立刻刷新。
Future<void> chaoxingLogin(BuildContext context) async {
  final ChaoxingModel model = context.read<ChaoxingModel>();
  final String? cookie = await chaoxingLoginLauncher(context);
  if (cookie != null) await model.saveCookie(cookie);
}

/// 用户**主动**点「重新登录」才弹的两按钮确认框。
/// 会话失效那条被动路径（`_maybeAskRelogin`）不走这里——弹两次很烦。
Future<void> confirmAndRelogin(BuildContext context) async {
  final bool? go = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: const Text('重新登录学习通'),
      content: const Text('将打开登录页重新获取凭据，登录成功后待办会自动刷新。'),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true), child: const Text('继续')),
      ],
    ),
  );
  if (go != true) return;
  if (!context.mounted) return;
  await chaoxingLogin(context);
}

/// 退出登录：三按钮确认框（保留隐藏列表 / 清空 / 取消），破坏性动作不在默认位。
Future<void> confirmAndLogout(BuildContext context) async {
  final String? choice = await showDialog<String>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: const Text('退出学习通'),
      content: const Text('退出后不再抓取学习通待办，已排的到期提醒会一并取消。'),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.of(ctx).pop('clear'),
            child: const Text('退出并清空隐藏列表')),
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(null), child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop('keep'),
            child: const Text('退出并保留隐藏列表')),
      ],
    ),
  );
  if (choice != 'keep' && choice != 'clear') return;
  if (!context.mounted) return;
  await chaoxingLogout(context, clearHiddenList: choice == 'clear');
}

/// 真正执行退出。顺序：清凭据与内存态 → 按需清隐藏集 → 取消已排提醒 →
/// 清 WebView cookie jar（**这条是 M6B §B4 修的既有缺陷**：以前只删凭据库那串，
/// jar 里的 `_uid` 还在，退出后点登录直接是已登录首页）。
///
/// 协调器必须在**任何 await 之前**取：那是个 Provider，async gap 之后再摸 context
/// 会撞 `use_build_context_synchronously`，而确认框退场后这个 context 未必还在。
/// 用可空读法（`read<T?>`）——建库失败时 `main.dart` 不注册它，取不到就走
/// [cancelChaoxingReminders] 里的降级路径，退出这条路径不能因此半途抛异常。
Future<void> chaoxingLogout(BuildContext context,
    {required bool clearHiddenList}) async {
  final ChaoxingModel model = context.read<ChaoxingModel>();
  final ReminderCoordinator? coordinator = context.read<ReminderCoordinator?>();
  await model.logout(clearHiddenList: clearHiddenList);
  await cancelChaoxingReminders(coordinator);
  await chaoxingCookieJarCleaner();
}

Future<void> openChaoxingHiddenList(BuildContext context) =>
    showChaoxingHiddenList(context);

/// 打开真实作业页；拼不出 URL 时也进详情页（页面自己显示降级文案）。
void openChaoxingDetail(BuildContext context, ChaoxingTask task) =>
    chaoxingDetailLauncher(context, task);

/// 隐藏一条待办。**还在等待处理（卡片带红/黄/绿底）的先弹一次确认**；
/// 已过期 / 已完成 / 无截止时间 → 直接隐藏不问（用户裁决：每次都问，
/// 不做「本次会话不再问」，自用工具误隐藏的代价比多问一句高）。
Future<void> hideChaoxingTask(
    BuildContext context, ChaoxingModel model, ChaoxingTask task) async {
  if (showsUrgencyTint(task, model.now)) {
    final String due = task.dueAt == null
        ? '无截止时间'
        : formatDeadlineLine(task.dueAt!, model.now);
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('确定隐藏？'),
        content: Text('「${task.title}」还没截止（$due），'
            '隐藏后不会在列表里提醒你。确定隐藏？',
            style: AppTypography.body),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('仍然隐藏')),
        ],
      ),
    );
    if (go != true) return;
  }
  await model.hide(task);
  if (!context.mounted) return;
  // 只撤销这一条；要一次恢复全部，仍走 ⋮ → 隐藏列表。
  AppToast.show(
    context,
    message: '已隐藏',
    actionLabel: '撤销',
    onAction: () => model.unhide(task.key),
  );
}
