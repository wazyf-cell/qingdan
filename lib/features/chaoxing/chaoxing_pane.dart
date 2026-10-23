/// 学习通面板：一行头部（页签 · N分钟前 · ⟳ · 筛选 · ⋮）+ 卡片列表。
///
/// 条目是外部只读快照（**刻意不落库、不参与同步**，定案见 `chaoxing_model.dart`
/// 头注释）；卡片从右往左滑揭示「详情 / 隐藏」，长按仍保留为隐藏的兜底手势。
/// 与扩展的刻意差异只有一处：不做点击卡片跳转（用户 2026-10-17 明确不要）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:qingdan/import/chaoxing/chaoxing_models.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

import 'chaoxing_actions.dart';
import 'chaoxing_card.dart';
import 'chaoxing_filter_sheet.dart';
import 'chaoxing_gates.dart';
import 'chaoxing_grouping.dart';
import 'chaoxing_header.dart';
import 'chaoxing_keys.dart';
import 'chaoxing_model.dart';
import 'swipe_reveal.dart';

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

  /// 当前滑开的卡片（提升到面板状态：同一时刻只允许一张开着，
  /// 且 `ListView` 复用 item 时打开态必须由外部 key 驱动）。
  String? _openKey;

  @override
  void initState() {
    super.initState();
    // 刷新收敛（M6B §B7）：每次进程只有一次自动刷新机会，距上次拉取不足
    // 15 分钟就跳过；另一个入口是头部的 ⟳ 按钮。下拉刷新已取消。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final ChaoxingModel model = context.read<ChaoxingModel>();
      await model.autoRefreshOnce();
      // 上次停在「课堂活动」页签的话，这次进来也得把那一批补上（活动是按需的，
      // 刷新不再顺带抓）。必须等自动刷新结束：刷新期间活动会被清空重置。
      if (!mounted) return;
      if (model.settings.tab == ChaoxingTab.activities) {
        await model.ensureActivitiesLoaded();
      }
    });
    // 倒计时得走字：每分钟推进一次模型的时间基准（不发请求）。
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

  /// 会话失效 → 自动弹一次 WebView 登录（被动路径，**不弹确认框**：
  /// 用户把登录页关掉就算「这轮不弄」，再套一层确认只会连弹两次）。
  void _maybeAskRelogin(ChaoxingModel model) {
    if (!model.pendingRelogin || _reloginOpen) return;
    _reloginOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      model.consumeReloginRequest();
      await chaoxingLogin(context);
      _reloginOpen = false;
    });
  }

  int get _filterCount {
    final ChaoxingViewSettings s = context.read<ChaoxingModel>().settings;
    return (_search.text.trim().isEmpty ? 0 : 1) +
        (_course.isEmpty ? 0 : 1) +
        (s.onlyUnfinished ? 1 : 0) +
        (s.onlySubmittable ? 1 : 0) +
        (s.sortBy == ChaoxingSortBy.timeAsc ? 0 : 1);
  }

  /// 弹层里的「N 项」要跟着开关实时变，所以给闭包而不是给快照数字。
  int _visibleCount(ChaoxingModel model) => buildRows(
          tasksOfTab(model.tasks, model.settings.tab),
          model.settings,
          model.now,
          query: _search.text,
          course: _course).length;

  /// 头部 ⟳：刷新后如果正停在「课堂活动」页签，把它按需补回来。
  ///
  /// 刷新会把活动作废（旧活动属于上一次快照），不清的话这里的列表会先空掉、
  /// 必须切走再切回才恢复——而用户就站在这一页上按的刷新。
  Future<void> _refresh(ChaoxingModel model) async {
    await model.refresh();
    if (!mounted) return;
    if (model.settings.tab == ChaoxingTab.activities) {
      await model.ensureActivitiesLoaded();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ChaoxingModel model = context.watch<ChaoxingModel>();
    _maybeAskRelogin(model);
    final List<ChaoxingTask> tabTasks =
        tasksOfTab(model.tasks, model.settings.tab);
    final List<ChaoxingRow> rows = buildRows(
        tabTasks, model.settings, model.now,
        query: _search.text, course: _course);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ChaoxingHeader(
          tab: model.settings.tab,
          onTab: (ChaoxingTab t) {
            setState(() {
              _course = '';
              _openKey = null;
            });
            model.setTab(t);
            // 课堂活动不再跟刷新一起抓（它要按班级一个一个请求，实测占 3 秒），
            // 切到这个页签才拉一次。
            if (t == ChaoxingTab.activities) model.ensureActivitiesLoaded();
          },
          statusText: model.statusText,
          statusIsError: model.statusIsError,
          stale: model.stale,
          // 活动的按需拉也要占住这个转圈：否则活动页签上按刷新，转圈先停、
          // 列表空三秒，看起来像「活动被刷没了」。
          loading: model.loading || model.activitiesLoading,
          loggedIn: model.loggedIn,
          onRefresh: () => _refresh(model),
          filterCount: _filterCount,
          onFilter: () => showChaoxingFilter(context,
              search: _search,
              onSearchChanged: (String _) => setState(() {}),
              course: _course,
              onCourseChanged: (String v) => setState(() => _course = v),
              courses: courseOptions(tabTasks),
              count: () => _visibleCount(model)),
          onRelogin: () => confirmAndRelogin(context),
          onHiddenList: () => openChaoxingHiddenList(context),
          onLogout: () => confirmAndLogout(context),
        ),
        if (model.error != null)
          ChaoxingBanner(
              text: model.error.toString(),
              actionLabel: '重新登录',
              onAction: () => confirmAndRelogin(context)),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification n) {
              // 滚动时全部收回：不然复用中的 item 会带着打开态乱跳。
              if (_openKey != null) setState(() => _openKey = null);
              return false;
            },
            child: !model.loggedIn
                ? ChaoxingLoginGate(onLogin: () => chaoxingLogin(context))
                : rows.isEmpty
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

  Widget _list(List<ChaoxingRow> rows, ChaoxingModel model) {
    return ListView.builder(
      itemCount: rows.length + 1,
      itemBuilder: (BuildContext _, int i) => i == rows.length
          ? const SizedBox(height: AppDimens.s32)
          : _row(rows[i], model),
    );
  }

  Widget _row(ChaoxingRow row, ChaoxingModel model) {
    final ChaoxingTask t = row.task;
    final AppColors colors = AppColors.of(context);
    return SwipeReveal(
      key: ChaoxingKeys.vkey(ChaoxingKeys.card(t.key)),
      open: _openKey == t.key,
      onOpen: () => setState(() => _openKey = t.key),
      onClose: () {
        if (_openKey == t.key) setState(() => _openKey = null);
      },
      actions: <SwipeAction>[
        SwipeAction(
          key: ChaoxingKeys.vkey(ChaoxingKeys.actDetail(t.key)),
          label: '详情',
          icon: Icons.description_outlined,
          background: colors.accent,
          onTap: () {
            setState(() => _openKey = null);
            openChaoxingDetail(context, t);
          },
        ),
        SwipeAction(
          key: ChaoxingKeys.vkey(ChaoxingKeys.actHide(t.key)),
          label: '隐藏',
          icon: Icons.visibility_off_outlined,
          background: colors.textSecondary,
          onTap: () {
            setState(() => _openKey = null);
            hideChaoxingTask(context, model, t);
          },
        ),
      ],
      // 长按 = 隐藏（手势发现不了时的兜底，用户确认保留）。
      child: ChaoxingCard(
          row: row, now: model.now, onHide: () => hideChaoxingTask(context, model, t)),
    );
  }
}
