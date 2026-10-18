// ignore_for_file: prefer_initializing_formals — 命名参数不能以 _ 开头
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show FocusNode;

import 'package:qingdan/application/task_use_case.dart';
import 'package:qingdan/domain/task.dart';
import 'package:qingdan/domain/task_list.dart';
import 'package:qingdan/domain/task_priority.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';

import 'task_pane_queries.dart';
import 'task_view_query.dart';

// 排序四档与视图判定搬到 `task_pane_queries.dart`（300 行红线，按职责拆）。
// 这里 re-export 枚举：`tasks_page / task_list_pane / tasks_bar / detail_attributes
// / trash_pane` 与多个测试都是 `import 'task_pane_model.dart'` 拿到 TaskSortMode 的，
// 搬家不能改它们的 import，公开 API 也就一个没动。
export 'task_pane_queries.dart' show TaskSortMode;

/// 任务列表状态：当前视图的任务集合、排序、选中、快捷操作。
///
/// 视图 id 跟随 [SidebarModel.selectedId]（侧栏点击切列表）。
/// [useCase] 为空时（widget 冒烟测试）load 直接返回空态。
class TaskPaneModel extends ChangeNotifier {
  TaskPaneModel({TaskUseCase? useCase, required SidebarModel sidebar})
      : _useCase = useCase,
        _sidebar = sidebar {
    _sidebar.addListener(_onViewChanged);
  }

  final TaskUseCase? _useCase;
  final SidebarModel _sidebar;

  /// 详情面板编辑用（UI 只经用例层，不碰 DAO）。
  TaskUseCase? get useCase => _useCase;

  String get viewId => _sidebar.selectedId;

  /// 当前视图按当前排序排好的任务。
  List<Task> tasks = <Task>[];

  /// 用户清单缓存（详情清单下拉 / 右键移动到清单）。
  List<TaskList> lists = const <TaskList>[];

  /// 排序模式（F9；智能清单固定按日期，不提供手动排序，见设计 §4）。
  TaskSortMode sortMode = TaskSortMode.manual;

  /// 键盘选中行（Space 完成 / Delete 删除 / Enter 开详情 / ↑↓ 移动）。
  String? selectedTaskId;

  /// 详情面板当前展示的任务 id（Enter 打开 / Esc 关闭）。
  String? detailTaskId;

  /// 子任务进度（task id → [完成数, 总数]），行内 ◐n/m。
  Map<String, List<int>> subtaskProgress = <String, List<int>>{};

  /// 标签数（task id → 数量），行内标签计数。
  Map<String, int> tagCounts = <String, int>{};

  /// 智能清单中已勾完成、正在等待 2s 塌缩移除的行。
  final Set<String> collapsing = <String>{};

  /// 快速添加聚焦（Ctrl+N）。
  FocusNode quickAddFocus = FocusNode(debugLabel: 'quickAdd');

  Timer? _collapseTimer;

  bool get isUserList => isUserListView(viewId);

  /// 智能清单 / 回收站视图（快速添加落点为收集箱，listId = null）。
  bool get isSmartView => !isUserList;

  /// 当前视图名（快速添加反馈行「→ 将创建到「…」」用）。
  String get currentViewName => viewDisplayName(viewId, lists);

  /// 快速添加保存（F1）：写库 + 刷新列表与侧栏计数。
  ///
  /// 顶部输入框与右下角「＋」的快捷抽屉**共用这一条写路径**（两者只是入口不同：
  /// 前者一行文本 + 自然语言日期，后者能显式选日期 / 优先级 / 清单）。
  Future<void> createQuickAdd({
    required String title,
    String? listId,
    DateTime? dueDate,
    DateTime? startDate,
    DateTime? endDate,
    TaskPriority priority = TaskPriority.none,
  }) async {
    final TaskUseCase? useCase = _useCase;
    if (useCase == null) return;
    await useCase.create(
        title: title,
        listId: listId,
        dueDate: dueDate,
        startDate: startDate,
        endDate: endDate,
        priority: priority);
    _refreshSidebar();
    await load();
  }

  /// 右键「移动到清单」。
  Future<void> moveToList(Task task, String? listId) async {
    await _useCase?.update(task.copyWith(listId: listId));
    _refreshSidebar();
    await load();
  }

  /// 右键「切换优先级」。
  Future<void> setPriority(Task task, TaskPriority priority) async {
    await _useCase?.update(task.copyWith(priority: priority));
    await load();
  }

  /// 右键「编辑日期」（仅支持改到未来某天，清除日期 M1 不做）。
  Future<void> setDueDate(Task task, DateTime dueLocal) async {
    await _useCase?.update(task.copyWith(dueDate: dueLocal.toUtc()));
    await load();
  }

  /// 智能清单「今天 / 最近 7 天」：完成后 2s 塌缩移除（§3.1）。
  bool get collapsesCompleted => collapsesCompletedView(viewId);

  void _onViewChanged() {
    detailTaskId = null;
    selectedTaskId = null;
    load();
  }

  Future<void> load() async {
    final TaskUseCase? useCase = _useCase;
    if (useCase == null) return;
    try {
      lists = await useCase.findLists();
      final List<Task> all = viewId == kSmartCompleted
          ? await useCase.findCompleted()
          : await useCase.findAllActive();
      tasks = sortTasks(
        filterForView(viewId, all),
        sortMode,
        smart: viewId == kSmartToday ||
            viewId == kSmartNext7 ||
            viewId == kSmartAll,
      );
      final PaneAnnotations marks = await loadAnnotations(useCase, tasks);
      subtaskProgress = marks.subtaskProgress;
      tagCounts = marks.tagCounts;
      notifyListeners();
    } catch (e) {
      notifyListeners();
      rethrow;
    }
  }

  void setSortMode(TaskSortMode mode) {
    sortMode = mode;
    tasks = sortTasks(tasks, mode, smart: !isUserList || viewId == kSmartCompleted);
    notifyListeners();
  }

  // ---- 选中 / 详情 ----

  void selectTask(String? id) {
    selectedTaskId = id;
    notifyListeners();
  }

  void moveSelection(int delta) {
    if (tasks.isEmpty) return;
    int index =
        tasks.indexWhere((Task t) => t.id == selectedTaskId);
    if (index < 0) {
      index = delta > 0 ? -1 : 0;
    }
    index = (index + delta).clamp(0, tasks.length - 1);
    selectTask(tasks[index].id);
  }

  void openDetail([String? taskId]) {
    detailTaskId = taskId ??
        selectedTaskId ??
        (tasks.isNotEmpty ? tasks.first.id : null);
    if (detailTaskId != null) selectTask(detailTaskId);
    notifyListeners();
  }

  void closeDetail() {
    detailTaskId = null;
    notifyListeners();
  }

  void focusQuickAdd() => quickAddFocus.requestFocus();

  // ---- 写操作（全部走用例层）----

  Future<void> toggleComplete(Task task) async {
    final TaskUseCase? useCase = _useCase;
    if (useCase == null) return;
    final bool completing = !task.completed;
    await useCase.setCompleted(task, completing);
    _refreshSidebar();
    if (completing && collapsesCompleted) {
      _scheduleCollapse(task.id);
    } else {
      await load();
    }
  }

  /// §3.1：2s 后 200ms 高度塌缩移除（行保持原位不沉底）。
  void _scheduleCollapse(String taskId) {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(const Duration(seconds: 2), () {
      collapsing.add(taskId);
      notifyListeners();
      Timer(const Duration(milliseconds: 200), () {
        collapsing.remove(taskId);
        tasks.removeWhere((Task t) => t.id == taskId);
        notifyListeners();
      });
    });
  }

  /// 删除（→回收站，§3.6 不确认）。返回标题供 SnackBar；撤销用 [undoDelete]。
  Future<String> deleteTask(Task task) async {
    final TaskUseCase? useCase = _useCase;
    if (useCase == null) return task.title;
    await useCase.moveToTrash(task.id);
    if (detailTaskId == task.id) closeDetail();
    _refreshSidebar();
    await load();
    return task.title;
  }

  Future<void> undoDelete(String taskId) async {
    await _useCase?.restore(taskId);
    _refreshSidebar();
    await load();
  }

  /// 手动拖拽排序结果落库（F9）。
  /// 注意：ReorderableListView.onReorderItem 的 newIndex 已自动调整，
  /// 这里不能再 `newIndex > oldIndex` 时减一（否则双重调整）。
  Future<void> reorderManual(int oldIndex, int newIndex) async {
    final TaskUseCase? useCase = _useCase;
    if (useCase == null || !isUserList || sortMode != TaskSortMode.manual) {
      return;
    }
    final Task moved = tasks.removeAt(oldIndex);
    tasks.insert(newIndex, moved);
    notifyListeners();
    await useCase.reorder(tasks);
    _refreshSidebar();
  }

  void _refreshSidebar() {
    _sidebar.load().catchError((Object e) {});
  }

  @override
  void dispose() {
    _sidebar.removeListener(_onViewChanged);
    _collapseTimer?.cancel();
    quickAddFocus.dispose();
    super.dispose();
  }
}
