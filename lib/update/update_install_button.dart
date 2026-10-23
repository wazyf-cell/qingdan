/// 「下载并安装」按钮：应用内下载发布页的 APK → 校验 → 调起系统安装器。
///
/// **不是静默安装**：普通应用无权跳过系统那一次「安装」确认（除非 root 或设备
/// 所有者）。这个组件只把「开浏览器 → 找资产 → 下载 → 点安装包」四步收成一步。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:qingdan/platform/system_intents.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'apk_download.dart';
import 'install_policy.dart';
import 'update_checker.dart';
import 'update_install.dart';

enum _Phase { idle, checking, downloading, verifying, launching, done, failed }

class UpdateInstallButton extends StatefulWidget {
  const UpdateInstallButton({
    super.key,
    required this.currentVersion,
    this.release,
    this.checker,
  });

  /// 当前安装的版本，用来判断发布页那条是不是「更新的」。
  final String currentVersion;

  /// 已经查到的新版本。升级通告弹层启动时没查过，传 null 由按钮自己查一次。
  final ReleaseInfo? release;

  final UpdateChecker? checker;

  @override
  State<UpdateInstallButton> createState() => _UpdateInstallButtonState();
}

class _UpdateInstallButtonState extends State<UpdateInstallButton> {
  _Phase _phase = _Phase.idle;
  String? _message;
  int _received = 0;
  int _total = 0;
  bool _canceled = false;

  bool get _busy =>
      _phase == _Phase.checking ||
      _phase == _Phase.downloading ||
      _phase == _Phase.verifying ||
      _phase == _Phase.launching;

  String get _label => switch (_phase) {
        _Phase.idle => '下载并安装',
        _Phase.checking => '正在查发布页…',
        _Phase.downloading =>
          _total > 0 ? '下载中 ${(_received * 100 ~/ _total)}%' : '下载中…',
        _Phase.verifying => '校验中…',
        _Phase.launching => '正在打开安装器…',
        _Phase.done => '再打开一次安装器',
        _Phase.failed => '重试',
      };

  void _set(_Phase phase, [String? message]) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _message = message;
    });
  }

  @override
  void dispose() {
    // 弹层关掉就等于放弃这次下载：不能让它在后台把 25MB 下完、再替用户弹系统安装器。
    _canceled = true;
    super.dispose();
  }

  Future<void> _start() async {
    _canceled = false;
    _set(_Phase.checking);
    // 1) 「安装未知应用」没开就先去开：否则下载完才被系统拦住，白等 25MB。
    if (!await SystemIntents.canInstallPackages()) {
      await SystemIntents.openInstallPermission();
      _set(_Phase.idle, '先在系统页里允许本应用「安装未知应用」，回来后点一次。');
      return;
    }
    // 2) 拿到要装的那一版；通告弹层只有版本号，这里补查一次。
    ReleaseInfo? found = widget.release;
    if (found == null) {
      final UpdateResult r =
          await (widget.checker ?? UpdateChecker()).check(widget.currentVersion);
      if (r.status != UpdateStatus.available || r.latest == null) {
        _set(_Phase.failed,
            r.status == UpdateStatus.failed ? '检查失败：${r.error}' : '已经是最新版');
        return;
      }
      found = r.latest!;
    }
    final ReleaseInfo rel = found;
    // 3) 挑这台设备能装的那份。
    final String? abi = await SystemIntents.deviceAbi();
    final ReleaseAsset? asset = pickApkAsset(rel.assets, abi);
    if (asset == null) {
      _set(_Phase.failed,
          '发布页里没有适合这台设备的安装包（ABI：${abi ?? '未知'}）。');
      return;
    }
    // 4) 下载。
    _received = 0;
    _total = asset.size;
    _set(_Phase.downloading);
    final File file;
    try {
      file = await downloadApk(
        asset,
        onProgress: (int received, int total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total > 0 ? total : asset.size;
          });
        },
        canceled: () => _canceled,
      );
    } on DownloadCanceled {
      _set(_Phase.idle, '已取消下载。');
      return;
    } on DownloadFailed catch (e) {
      _set(_Phase.failed, e.reason);
      return;
    }
    if (!mounted) return; // 下载期间弹层被关掉：不再往下走
    // 5) 校验和（发布页有才校验；拿不到就跳过，不让它卡住安装）。
    _set(_Phase.verifying);
    final String? problem = await _verify(rel, asset, file);
    if (!mounted) return;
    if (problem != null) {
      _set(_Phase.failed, problem);
      return;
    }
    // 6) 签名比对：不一致根本不进系统安装器，那一步只会回一句英文。
    final String? installed = await SystemIntents.packageSignature();
    final String? apkSig = await SystemIntents.apkSignature(file.path);
    if (!signaturesMatch(installed, apkSig)) {
      _set(_Phase.failed,
          '这个包装不上：本机上已装的是另一个签名的旧版本。$kInstallPolicyText');
      return;
    }
    // 7) 交给系统安装器（用户还要在系统界面点一次「安装」）。
    _set(_Phase.launching);
    final bool opened = await SystemIntents.installApk(file.path);
    _set(opened ? _Phase.done : _Phase.failed,
        opened ? '已交给系统安装器，按提示点「安装」即可。' : '打不开系统安装器。');
  }

  Future<String?> _verify(
      ReleaseInfo rel, ReleaseAsset asset, File file) async {
    final ReleaseAsset? sums = sha256Asset(rel.assets);
    if (sums == null) return null;
    final String? text = await fetchSums(sums);
    final String? expected =
        text == null ? null : expectedSha256(text, asset.name);
    if (expected == null) return null;
    final String actual = await sha256OfFile(file);
    if (actual == expected) return null;
    await file.delete().catchError((Object _) => file);
    return '下载的包和发布页的校验和不一致，已删除。请重试。';
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_phase == _Phase.downloading)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                LinearProgressIndicator(
                  key: const ValueKey<String>('update-install-progress'),
                  value: _total > 0 ? _received / _total : null,
                  minHeight: 4,
                ),
                const SizedBox(height: 4),
                Text(
                  _total > 0
                      ? '${formatBytes(_received)} / ${formatBytes(_total)}'
                      : formatBytes(_received),
                  key: const ValueKey<String>('update-install-bytes'),
                  style: AppTypography.meta
                      .copyWith(fontSize: 11, color: colors.textFaint),
                ),
              ],
            ),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              _message!,
              key: const ValueKey<String>('update-install-message'),
              style: AppTypography.meta.copyWith(
                  fontSize: 12,
                  color: _phase == _Phase.failed
                      ? colors.priorityHigh
                      : colors.textSecondary),
            ),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (_phase == _Phase.downloading)
              TextButton(
                key: const ValueKey<String>('update-install-cancel'),
                onPressed: () => setState(() => _canceled = true),
                child: const Text('取消'),
              ),
            FilledButton(
              key: const ValueKey<String>('update-install'),
              onPressed: _busy ? null : _start,
              child: Text(_label),
            ),
          ],
        ),
      ],
    );
  }
}
