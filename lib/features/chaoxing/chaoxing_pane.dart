/// 学习通面板（扩展成品界面的一比一复刻，移动端适配）：
/// 页签（全部作业 / 课堂活动）+ 工具栏（搜索/课程/两个仅看/排序/数据时间）
/// + 条目卡片列表 + 刷新（顶栏按钮与下拉两种）。
///
/// 条目是外部只读快照（不落库、不参与同步）；长按一行 = 隐藏本条。
/// 与扩展的刻意差异只有一处：不做点击跳转（用户明确不要）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

import 'chaoxing_card.dart';
import 'chaoxing_gates.dart';
import 'chaoxing_grouping.dart';
import 'chaoxing_login.dart';
import 'chaoxing_model.dart';
import 'chaoxing_toolbar.dart';

class ChaoxingPane extends StatefulWidget {
  const ChaoxingPane({super.key});

  @override
  State<ChaoxingPane> createState() => _ChaoxingPaneState();
}

class _ChaoxingPaneState extends State<ChaoxingPane> {
  final TextEditingController _search = TextEditingController();
  String _course = '';
  Timer? _ticker;
  bool _reloginOpen = false;

  /// 会话失效 → 自动弹一次 WebView 登录（用户不用先点「登录学习通」）。
  /// 用户把登录页关掉就算「这轮不弄」，等下次刷新再失败才会再弹。
  void _maybeAskRelogin(ChaoxingModel model) {
    if (!model.pendingRelogin || _reloginOpen) return;
    _reloginOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      model.consumeReloginRequest();
      await _login(context);
      _reloginOpen = false;
    });
  }

  @override
  void initState() {
    super.initState();
    // 外部数据是活的，每次打开这个视图都现拉一遍（与课表面板同一套首帧后
    // 加载的写法：load/refresh 会 notifyListeners，build 期间同步通知会炸）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ChaoxingModel model = context.read<ChaoxingModel>();
      if (model.loggedIn && !model.loading) model.refresh();
    });
    // 倒计时得走字：每分钟推进一次模型的时间基准。
    _ticker = Timer.periodic(const Duration(minutes: 1), (Timer _) {
      if (!mounted) return;
      context.read<ChaoxingModel>().tick();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ChaoxingModel model = context.watch<ChaoxingModel>();
    _maybeAskRelogin(model);
    final List<ChaoxingTask> tabTasks =
        tasksOfTab(model.tasks, model.settings.tab);
    final List<ChaoxingRow> rows = buildRows(tabTasks, model.settings, model.now,
        query: _search.text, course: _course);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _header(model),
        if (model.error != null)
          ChaoxingBanner(
              text: model.error.toString(),
              actionLabel: '重新登录',
              onAction: () => _login(context)),
        if (model.loggedIn) ...<Widget>[
          _tabs(model),
          const SizedBox(height: AppDimens.s8),
          ChaoxingToolbar(
            model: model,
            searchController: _search,
            onQueryChanged: (String _) => setState(() {}),
            course: _course,
            onCourseChanged: (String v) => setState(() => _course = v),
            courses: courseOptions(tabTasks),
            count: rows.length,
          ),
        ],
        Expanded(
          child: !model.loggedIn
              ? ChaoxingLoginGate(onLogin: () => _login(context))
              : RefreshIndicator(
                  onRefresh: model.refresh,
                  child: rows.isEmpty
                      ? ChaoxingEmpty(
                          loading: model.loading,
                          courses: model.courseCount,
                          activities: model.activityCount,
                          filteredOut: model.activityCount > 0,
                        )
                      : _list(rows, model),
                ),
        ),
      ],
    );
  }

  Widget _header(ChaoxingModel model) {
    final AppColors colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppDimens.s16, AppDimens.s12, AppDimens.s8, AppDimens.s4),
      child: Row(
        children: <Widget>[
          Expanded(child: Text('学习通待办', style: AppTypography.pageTitle)),
          // 扩展工具栏第一个控件就是「刷新」；这里同时保留下拉刷新。
          TextButton.icon(
            onPressed: model.loading ? null : model.refresh,
            icon: Icon(model.loading ? Icons.sync : Icons.refresh, size: 18),
            label: const Text('刷新', style: AppTypography.meta),
            style: TextButton.styleFrom(foregroundColor: colors.textSecondary),
          ),
          // 会话没失效时也要能主动换号：logout() 早就写好了，之前没接线。
          PopupMenuButton<String>(
            tooltip: '账号',
            onSelected: (String v) =>
                v == 'relogin' ? _login(context) : model.logout(),
            itemBuilder: (BuildContext _) => const <PopupMenuItem<String>>[
              PopupMenuItem(value: 'relogin', child: Text('重新登录')),
              PopupMenuItem(value: 'logout', child: Text('退出登录')),
            ],
            icon: Icon(Icons.more_vert, size: 20, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _tabs(ChaoxingModel model) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.s16),
      child: SegmentedButton<ChaoxingTab>(
        showSelectedIcon: false,
        segments: ChaoxingTab.values
            .map((ChaoxingTab t) => ButtonSegment<ChaoxingTab>(
                value: t,
                label: Text(t.label, style: AppTypography.meta)))
            .toList(),
        selected: <ChaoxingTab>{model.settings.tab},
        onSelectionChanged: (Set<ChaoxingTab> next) {
          setState(() => _course = '');
          model.setTab(next.first);
        },
      ),
    );
  }

  Widget _list(List<ChaoxingRow> rows, ChaoxingModel model) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: rows.length + 1,
      itemBuilder: (BuildContext _, int i) => i == rows.length
          ? const SizedBox(height: AppDimens.s32)
          : ChaoxingCard(
              row: rows[i],
              now: model.now,
              onHide: () => _hide(model, rows[i].task),
            ),
    );
  }

  void _hide(ChaoxingModel model, ChaoxingTask t) {
    model.hide(t.key);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已隐藏「${t.title}」', style: AppTypography.meta),
      duration: const Duration(seconds: 4),
      action:
          SnackBarAction(label: '全部恢复', onPressed: model.unhideAll),
    ));
  }

  Future<void> _login(BuildContext context) async {
    final ChaoxingModel model = context.read<ChaoxingModel>();
    final String? cookie = await showChaoxingLogin(context);
    if (cookie != null) await model.saveCookie(cookie);
  }
}
