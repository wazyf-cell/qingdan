import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "package:qingdan/sync/sync_backend.dart";
import "package:qingdan/sync/sync_config_store.dart";
import "package:qingdan/sync/webdav_backend.dart";
import "package:qingdan/sync/webdav_transport.dart";
import "package:qingdan/theme/app_colors.dart";
import "package:qingdan/theme/app_dimens.dart";
import "package:qingdan/theme/app_typography.dart";

/// 设置 · 同步节（M3 §3.3，替换 M2 占位）。
///
/// 只经 [SyncConfigStore] 读写配置（非敏感项进 prefs、密码进系统凭据库）；
/// 「测试连接」按 §3.3 造一个临时 WebDavBackend 调 ensureReady，用完立即
/// 关闭传输层（否则每次点按钮泄漏一个 HttpClient）。
///
/// 尺寸沿用既有范式（对话框 640×440、左导航 160dp），不改。
class SyncSection extends StatefulWidget {
  /// [showTitle] 同 [AppearanceSection]：窄屏二级页的顶栏已写节名，不再自绘。
  const SyncSection({super.key, this.showTitle = true});

  final bool showTitle;

  @override
  State<SyncSection> createState() => _SyncSectionState();
}

enum _TestState { none, testing, ok, badCredentials, other }

class _SyncSectionState extends State<SyncSection> {
  final TextEditingController _baseUrl = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _enabled = false;
  bool _loaded = false;
  String? _saveError;
  _TestState _test = _TestState.none;
  String _testMessage = "";

  SyncConfigStore get _store => context.read<SyncConfigStore>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final SyncConfig config = await _store.load();
      if (!mounted) return;
      setState(() {
        _enabled = config.enabled;
        _baseUrl.text = config.baseUrl;
        _username.text = config.username;
        _password.text = config.password;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _saveError = "读取配置失败：$e";
      });
    }
  }

  SyncConfig _currentConfig() => SyncConfig(
        enabled: _enabled,
        baseUrl: _baseUrl.text.trim(),
        username: _username.text.trim(),
        password: _password.text,
      );

  Future<void> _save() async {
    setState(() => _saveError = null);
    try {
      await _store.save(_currentConfig());
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("同步配置已保存")));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saveError = "$e");
    }
  }

  Future<void> _clear() async {
    await _store.clear();
    if (!mounted) return;
    setState(() {
      _enabled = false;
      _baseUrl.clear();
      _username.clear();
      _password.clear();
      _test = _TestState.none;
      _testMessage = "";
    });
  }

  /// 「测试连接」（§3.3）：临时 backend 调 ensureReady，finally 关传输层。
  Future<void> _testConnection() async {
    final SyncConfig config = _currentConfig();
    if (config.baseUrl.isEmpty) {
      setState(() {
        _test = _TestState.other;
        _testMessage = "请先填写服务器地址";
      });
      return;
    }
    setState(() {
      _test = _TestState.testing;
      _testMessage = "测试中…";
    });

    final HttpClientWebDavTransport transport = HttpClientWebDavTransport();
    final WebDavBackend backend = WebDavBackend(
      baseUrl: Uri.parse(config.baseUrl),
      username: config.username,
      password: config.password,
      transport: transport,
    );
    try {
      await backend.ensureReady();
      if (!mounted) return;
      setState(() {
        _test = _TestState.ok;
        _testMessage = "根目录已就绪";
      });
    } on SyncConfigException catch (e) {
      if (!mounted) return;
      final bool creds = e.statusCode == 401 || e.statusCode == 403;
      setState(() {
        _test = creds ? _TestState.badCredentials : _TestState.other;
        _testMessage = creds
            ? "账号或应用密码错误（坚果云须用应用密码，非登录密码）"
            : "HTTP ${e.statusCode}：${e.hint}";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _test = _TestState.other;
        _testMessage = "无法连接：$e";
      });
    } finally {
      transport.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    if (!_loaded) {
      return Center(
        child: Text("读取中…",
            style: AppTypography.meta.copyWith(color: colors.textFaint)),
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (widget.showTitle) ...<Widget>[
            Text("同步",
                style: AppTypography.panelTitle
                    .copyWith(color: colors.textPrimary)),
            const SizedBox(height: AppDimens.s8),
          ],
          SwitchListTile(
            key: const ValueKey<String>("sync-enabled"),
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _enabled,
            onChanged: (bool v) => setState(() => _enabled = v),
            title: Text("启用同步",
                style: AppTypography.body.copyWith(color: colors.textPrimary)),
          ),
          _field(colors, "服务器地址", _baseUrl,
              fieldKey: "sync-url",
              hint: "https://dav.jianguoyun.com/dav/qingdan/"),
          Text("地址必须带非空子路径（如 /dav/qingdan/），直接指向根目录会失败。",
              style: AppTypography.meta.copyWith(color: colors.textFaint)),
          const SizedBox(height: AppDimens.s12),
          _field(colors, "账号", _username,
              fieldKey: "sync-user", hint: "name@example.com"),
          const SizedBox(height: AppDimens.s12),
          _field(colors, "应用密码", _password,
              fieldKey: "sync-password", obscure: true),
          const SizedBox(height: AppDimens.s12),
          Row(
            children: <Widget>[
              OutlinedButton(
                key: const ValueKey<String>("sync-test"),
                onPressed: _test == _TestState.testing ? null : _testConnection,
                child: const Text("测试连接"),
              ),
              const SizedBox(width: AppDimens.s12),
              Flexible(child: _testResultText(colors)),
            ],
          ),
          const SizedBox(height: AppDimens.s12),
          Text("兜底轮询：固定 30 分钟 · 请求数受限流保护（600 / 30 分钟）。",
              style: AppTypography.meta.copyWith(color: colors.textFaint)),
          if (_saveError != null) ...<Widget>[
            const SizedBox(height: AppDimens.s8),
            Text(_saveError!,
                style: AppTypography.meta.copyWith(color: colors.overdue)),
          ],
          const SizedBox(height: AppDimens.s16),
          Row(
            children: <Widget>[
              FilledButton(
                  key: const ValueKey<String>("sync-save"),
                  onPressed: _save,
                  child: const Text("保存")),
              const SizedBox(width: AppDimens.s12),
              TextButton(
                key: const ValueKey<String>("sync-clear"),
                onPressed: _clear,
                child: Text("解除配置",
                    style: TextStyle(color: colors.overdue)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _testResultText(AppColors colors) {
    final (Color color, IconData? icon) = switch (_test) {
      _TestState.ok => (colors.success, Icons.check_circle_outline),
      _TestState.badCredentials => (colors.overdue, Icons.error_outline),
      _TestState.other => (colors.overdue, Icons.error_outline),
      _TestState.testing => (colors.textSecondary, null),
      _TestState.none => (colors.textFaint, null),
    };
    return Row(
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppDimens.s4),
        ],
        Flexible(
          child: Text(_testMessage,
              key: const ValueKey<String>("sync-result"),
              style: AppTypography.meta.copyWith(color: color)),
        ),
      ],
    );
  }

  Widget _field(
    AppColors colors,
    String label,
    TextEditingController controller, {
    String? fieldKey,
    String? hint,
    bool obscure = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label,
            style: AppTypography.meta.copyWith(color: colors.textSecondary)),
        const SizedBox(height: AppDimens.s4),
        TextField(
          key: fieldKey == null ? null : ValueKey<String>(fieldKey),
          controller: controller,
          obscureText: obscure,
          style: AppTypography.body.copyWith(color: colors.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: AppTypography.body.copyWith(color: colors.textFaint),
            filled: true,
            fillColor: colors.surfaceHigh,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusDesktop),
            ),
          ),
        ),
      ],
    );
  }
}
