import 'package:qingdan/application/task_use_case.dart';
import 'package:qingdan/domain/tag.dart';
import 'package:qingdan/domain/task.dart';
import 'package:qingdan/domain/task_list.dart';
import 'package:qingdan/features/shell/sidebar/sidebar_model.dart';

/// 任务面板的**查询 / 视图判定**侧（M6 总纲铁律 2：单文件 ≤300 行）。
///
/// 从 `task_pane_model.dart` 按职责搬过来，行为与公开语义一字未改：这里全是
/// 「给它视图 id（和清单缓存）就能算出答案」的纯判定，不碰 ChangeNotifier 状态，
/// 所以模型只留「状态 + 写路径」这一半。

/// 列表排序四档（F9）。
enum TaskSortMode { manual, due, priority, title }

/// 用户清单视图（收集箱与真实清单都算）；四个智能视图与回收站不算。
///
/// `course` / `chaoxing` 也不在这五张表里 → 一并算「用户清单」。这是搬家前的既有
/// 语义，照搬不改（那两个面板不渲染任务列表，判错了也没有可见后果）。
bool isUserListView(String viewId) =>
    viewId != kSmartToday &&
    viewId != kSmartNext7 &&
    viewId != kSmartAll &&
    viewId != kSmartCompleted &&
    viewId != kTrash;

/// 智能清单「今天 / 最近 7 天」：完成后 2s 塌缩移除（§3.1）。
bool collapsesCompletedView(String viewId) =>
    viewId == kSmartToday || viewId == kSmartNext7;

/// 当前视图名（快速添加反馈行「→ 将创建到「…」」与窄屏顶栏标题用）。
String viewDisplayName(String viewId, List<TaskList> lists) {
  switch (viewId) {
    case kSmartToday:
      return '今天';
    case kSmartNext7:
      return '最近 7 天';
    case kSmartAll:
      return '所有';
    case kSmartCompleted:
      return '已完成';
    case kTrash:
      return '回收站';
    case kCourseWeek:
      return '课表';
    case kChaoxing:
      return '学习通';
  }
  for (final TaskList list in lists) {
    if (list.id == viewId) return list.name;
  }
  return '收集箱';
}

/// 一次 `load()` 查回来的行内标注（子任务进度 + 标签数）。
class PaneAnnotations {
  const PaneAnnotations({
    required this.subtaskProgress,
    required this.tagCounts,
  });

  final Map<String, List<int>> subtaskProgress;
  final Map<String, int> tagCounts;
}

/// 逐行查子任务进度与标签数（行内 ◐n/m 与标签计数）。全部走用例层，不碰 DAO。
Future<PaneAnnotations> loadAnnotations(
  TaskUseCase useCase,
  List<Task> tasks,
) async {
  final Map<String, List<int>> progress = <String, List<int>>{};
  final Map<String, int> tags = <String, int>{};
  for (final Task t in tasks) {
    final List<Subtask> subs = await useCase.findSubtasks(t.id);
    if (subs.isNotEmpty) {
      progress[t.id] = <int>[
        subs.where((Subtask s) => s.completed).length,
        subs.length,
      ];
    }
    final List<Tag> taskTags = await useCase.findTagsOf(t.id);
    if (taskTags.isNotEmpty) tags[t.id] = taskTags.length;
  }
  return PaneAnnotations(subtaskProgress: progress, tagCounts: tags);
}
