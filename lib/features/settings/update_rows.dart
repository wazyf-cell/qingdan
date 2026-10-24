import 'package:flutter/material.dart';

import 'package:qingdan/platform/system_intents.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';
import 'package:qingdan/update/install_policy.dart';
import 'package:qingdan/update/update_checker.dart';
import 'package:qingdan/update/update_install_button.dart';

import 'about_section.dart' show kAppVersion;

/// 更新通道的两行控件（v1.0.2：把 M6-E 的说明占位换成真功能）。
///
/// 拆成两行是用户的原话：「就做成 2 个，一个检测更新和一个 github 按钮」。
/// 前者只查一次、把结论写在行上；后者只是跳浏览器，两件事的失败方式不一样，
/// 合并成一行就会互相顶包（跳不动被当成查不到新版）。
class UpdateRows extends StatefulWidget {
  const UpdateRows({super.key, this.checker});

  /// 测试注入用的假检查器；为 null 时用默认的（真打 GitHub API）。
  final UpdateChecker? checker;

  @override
  State<UpdateRows> createState() => _UpdateRowsState();
}

class _UpdateRowsState extends State<UpdateRows> {
  bool _running = false;
  UpdateResult? _last;

  /// 「打不开」的本地回执。**不用 SnackBar**：设置二级页是 push 出来的路由，
  /// 弹层关掉之后 SnackBar 会画在已经没人看的那一层（这条在课表弹层栽过两次）。
  String? _said;

  Future<void> _check() async {
    if (_running) return;
    setState(() {
      _running = true;
      _said = null;
    });
    final UpdateResult r =
        await (widget.checker ?? UpdateChecker()).check(kAppVersion);
    if (!mounted) return;
    setState(() {
      _running = false;
      _last = r;
    });
    await _showResult(r);
  }

  Future<void> _showResult(UpdateResult r) => showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('检查更新'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // 只有正文滚：发布说明可能很长，但「下载并安装」必须始终看得见，
                // 否则用户要先把整篇 Release 正文滚到底才知道能装。
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(_detailText(r),
                        style: AppTypography.body,
                        key: const ValueKey<String>('update-result-text')),
                  ),
                ),
                if (r.status == UpdateStatus.available) ...<Widget>[
                  const SizedBox(height: AppDimens.s12),
                  // 有新版才给装：已是最新版时这一块只会让人以为还有东西可装。
                  UpdateInstallButton(
                    key: const ValueKey<String>('update-result-install'),
                    currentVersion: kAppVersion,
                    release: r.latest,
                    checker: widget.checker,
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            // 失败时不能只给「关闭」：网络访问不了 GitHub API 的时候，浏览器里的
            // 发布页仍是唯一的手动下载路径（2026-10-24 截图里就是一条死路）。
            if (r.status == UpdateStatus.failed)
              TextButton(
                key: const ValueKey<String>('update-result-retry'),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _check();
                },
                child: const Text('重试'),
              ),
            TextButton(
              key: const ValueKey<String>('update-result-close'),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('关闭'),
            ),
            if (r.status != UpdateStatus.upToDate)
              TextButton(
                key: const ValueKey<String>('update-result-open'),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _open(r.latest?.url ?? '$kRepoUrl/releases/latest', '发布页');
                },
                child: const Text('打开发布页'),
              ),
          ],
        ),
      );

  Future<void> _openRepo() => _open(kRepoUrl, '仓库主页');

  Future<void> _open(String url, String what) async {
    final bool ok = await SystemIntents.openUrl(url);
    if (ok || !mounted) return;
    setState(() => _said =
        '「$what」打不开：这台设备上没有能打开网页的应用。地址是 $url');
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ListTile(
          key: const ValueKey<String>('settings-update'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          enabled: !_running,
          title: Text('检测更新',
              style: AppTypography.body.copyWith(color: colors.textPrimary)),
          subtitle: Text(_subtitle(),
              key: const ValueKey<String>('settings-update-subtitle'),
              style: AppTypography.meta),
          trailing: _running
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.chevron_right, size: 20),
          onTap: _check,
        ),
        ListTile(
          key: const ValueKey<String>('settings-update-github'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('GitHub 仓库',
              style: AppTypography.body.copyWith(color: colors.textPrimary)),
          subtitle: Text('$kRepoSlug · 发布页与源码',
              style: AppTypography.meta),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: _openRepo,
        ),
        if (_said != null)
          Padding(
            padding: const EdgeInsets.only(top: AppDimens.s4),
            child: Text(_said!,
                key: const ValueKey<String>('update-open-failed'),
                style: AppTypography.meta.copyWith(color: colors.overdue)),
          ),
      ],
    );
  }

  String _subtitle() {
    if (_running) return '正在检查 GitHub Releases…';
    if (_last != null) return _last!.summary;
    return '当前 v$kAppVersion · 从 GitHub Releases 查新版本';
  }
}

String _detailText(UpdateResult r) {
  final StringBuffer b = StringBuffer(r.summary);
  switch (r.status) {
    case UpdateStatus.upToDate:
      // 「GitHub 上最新是 vX」必须带版本号。本机包比 GitHub 那条 release 更新是
      // 正常状态（发了版还没推 tag / 用户装的是预发布的包），只写「最新发布：日期」
      // 会被读成「最新的就是我今天这个」，而那个日期其实是旧版的发布日。
      b.write('\n\nGitHub 上最新是 v${r.latest!.version}'
          '（发布于 ${_ymd(r.latest!.publishedAt)}）');
      b.write('\n版本源：$kRepoUrl/releases/latest');
    case UpdateStatus.available:
      final ReleaseInfo l = r.latest!;
      b.write('\n\n当前 v$kAppVersion → 最新 v${l.version}'
          '（发布于 ${_ymd(l.publishedAt)}）');
      // 发布说明只在「真的能升级」时有用：已是最新版的提示里塞一遍改动内容，
      // 只会让那一屏更长，而用户并没有东西可装。
      final String? notes = _cappedNotes(l.notes);
      if (notes != null) {
        b.write('\n\n这一版改了什么：\n$notes');
      }
      if (l.assetNames.isNotEmpty) {
        b.write('\n\n发布页里的文件：\n${l.assetNames.join('\n')}');
      }
      b.write('\n\n$kInstallPolicyText');
      b.write('\n\n点「下载并安装」会在这里下载这一版的 APK，校验签名后调起系统安装器；'
          '系统仍会让你点一次「安装」——普通应用无权跳过那一步。');
    case UpdateStatus.failed:
      b.write('\n\n没有拿到 GitHub 的发布页。检查更新只是读一个公开网页，'
          '失败不影响任务、课表与同步。'
          '\n可以点「重试」，或点「打开发布页」用浏览器手动下载；'
          '如果浏览器也打不开 GitHub，说明这个网络访问不了它，换一个网络再试。');
  }
  return b.toString();
}

String _ymd(DateTime? t) {
  if (t == null) return '未知';
  final DateTime local = t.toLocal();
  final String mm = local.month.toString().padLeft(2, '0');
  final String dd = local.day.toString().padLeft(2, '0');
  return '${local.year}-$mm-$dd';
}

/// 发布说明的长度上限。GitHub 的 `body` 没有长度限制，真发过一篇带变更表格的长文
/// 就会把弹层撑成一屏读不完的墙；这里只留够看清「改了什么」的前 1200 字。
const int kMaxNoteChars = 1200;

/// 取发布说明、压成纯文本并截断。没有说明就返回 null，让调用方保持原有版式。
String? _cappedNotes(String? raw) {
  final String text = _plainNotes(raw?.trim() ?? '');
  if (text.isEmpty) return null;
  if (text.length <= kMaxNoteChars) return text;
  int end = kMaxNoteChars;
  // 不把代理对（emoji 之类）劈成半个字符——那会在界面上显示成一个「豆腐块」。
  final int last = text.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) end -= 1;
  return '${text.substring(0, end)}…';
}

/// 把 GitHub 的 Markdown 发布说明压成纯文本。
///
/// 项目里没有 Markdown 渲染器：`## 这一版改了什么`、`**加粗**`、反引号会连同
/// 符号原样显示在弹层里，用户看到的第一行就是几个井号。只处理发布说明里
/// 真会用到的那几种标记，不追求完整的 Markdown 语义。
String _plainNotes(String raw) {
  if (raw.isEmpty) return raw;
  final StringBuffer out = StringBuffer();
  for (final String line in raw.split('\n')) {
    String l = line.trimRight();
    l = l.replaceFirst(RegExp(r'^\s*#{1,6}\s+'), ''); // 标题
    l = l.replaceFirst(RegExp(r'^\s*[-*]\s+'), '· '); // 无序列表 → 与自带说明同形
    l = l.replaceAll('**', '').replaceAll('`', ''); // 加粗 / 行内代码
    // 链接只留文字：URL 在弹层里既长又点不动。
    l = l.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1] ?? '');
    out.writeln(l);
  }
  return out.toString().trim();
}
