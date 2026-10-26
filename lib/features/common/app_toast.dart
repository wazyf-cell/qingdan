import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 顶部短回执：替代「已删除 / 已隐藏 / 已复制」这类底部 SnackBar。
///
/// 为什么不用 SnackBar：手机壳的 SnackBar 画在底部页签栏上方，会挡住
/// 切换页签的那一条（2026-10-26 用户报）。这里改成浮在**内容顶部**的窄条，
/// 不占布局、不盖底部导航；总生命周期固定 1.5 秒。
const Duration kAppToastLifetime = Duration(milliseconds: 1500);
const Duration kAppToastFade = Duration(milliseconds: 150);

const ValueKey<String> kAppToastKey = ValueKey<String>('app-toast');
const ValueKey<String> kAppToastActionKey =
    ValueKey<String>('app-toast-action');

/// 一次只留一条：连续操作时旧回执立即退场，新回执接管。
class AppToast {
  AppToast._();

  static OverlayEntry? _active;

  static void show(
    BuildContext context, {
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _removeActive();
    final OverlayState overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (BuildContext _) => _ToastView(
        message: message,
        actionLabel: actionLabel,
        onAction: onAction == null
            ? null
            : () {
                onAction();
                _dismiss(entry);
              },
        onDone: () => _dismiss(entry),
      ),
    );
    _active = entry;
    overlay.insert(entry);
    // 回执短，触感是把「真的做完了」说清楚的另一半；失败时不响。
    HapticFeedback.selectionClick();
  }

  static void dismiss() => _removeActive();

  static void _removeActive() {
    final OverlayEntry? active = _active;
    _active = null;
    if (active != null && active.mounted) active.remove();
  }

  static void _dismiss(OverlayEntry entry) {
    if (!identical(_active, entry)) return;
    _active = null;
    if (entry.mounted) entry.remove();
  }
}

class _ToastView extends StatefulWidget {
  const _ToastView({
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.onDone,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDone;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  Timer? _life;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: kAppToastFade)
      ..forward();
    // 进场也算在这 1.5 秒里：到点先淡出，淡完再摘掉 Overlay。
    _life = Timer(kAppToastLifetime - kAppToastFade, _fadeOut);
  }

  void _fadeOut() {
    if (!mounted) return;
    _anim.reverse().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _life?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(
          // 浮在顶栏这一条里：不进入正文，也不碰底部页签。
          top: AppDimens.s8,
          left: AppDimens.s16,
          right: AppDimens.s16,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: FadeTransition(
              opacity: _anim,
              child: SlideTransition(
                position: Tween<Offset>(
                        begin: const Offset(0, -0.12), end: Offset.zero)
                    .animate(CurvedAnimation(
                        parent: _anim, curve: Curves.easeOut)),
                child: Material(
                  key: kAppToastKey,
                  color: colors.surface,
                  elevation: 8,
                  shadowColor: const Color(0x33000000),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppDimens.radiusDesktop),
                    side: BorderSide(color: colors.divider),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.s12, vertical: AppDimens.s8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.check_circle_outline,
                            size: 16, color: colors.success),
                        const SizedBox(width: AppDimens.s8),
                        Flexible(
                          child: Text(
                            widget.message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.meta
                                .copyWith(color: colors.textPrimary),
                          ),
                        ),
                        if (widget.actionLabel != null) ...<Widget>[
                          const SizedBox(width: AppDimens.s8),
                          InkWell(
                            key: kAppToastActionKey,
                            onTap: widget.onAction,
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppDimens.s8, vertical: 4),
                              child: Text(
                                widget.actionLabel!,
                                style: AppTypography.meta.copyWith(
                                  color: colors.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
