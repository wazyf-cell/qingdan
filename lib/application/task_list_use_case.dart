import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/domain/task.dart';
import 'package:qingdan/domain/task_list.dart';

/// 清单用例（F6）+ 侧栏聚合数据装载（自 `sidebar_model.dart` 上移，M1 定案）。
///
/// 侧栏与任务列表共用同一份读模型，任何写操作后由调用方触发重载。
class TaskListUseCase {
  TaskListUseCase(this._services);

  final AppServices _services;

  Future<List<TaskList>> findAll() => _services.taskListDao.findAll();

  Future<TaskList> create({required String name, int sortOrder = 0}) =>
      _services.taskListDao.insert(name: name, sortOrder: sortOrder);

  Future<void> rename(TaskList list, String name) =>
      _services.taskListDao
          .update(list.copyWith(name: name, modifiedTime: DateTime.now().toUtc()));

  Future<void> reorder(List<TaskList> ordered) async {
    for (int i = 0; i < ordered.length; i++) {
      if (ordered[i].sortOrder != i) {
        await _services.taskListDao
            .update(ordered[i].copyWith(sortOrder: i));
      }
    }
  }

  /// 删除清单：其任务由外键 SET NULL 落回收集箱（迁移 v2 语义）。
  Future<void> delete(String id) => _services.taskListDao.delete(id);

  /// 侧栏聚合读模型（原 `sidebar_model.load` 的直读 DAO 逻辑上移至此）：
  /// 清单 + 智能清单计数一次取回。
  Future<SidebarSnapshot> loadSidebar() async {
    final List<TaskList> lists = await _services.taskListDao.findAll();
    final List<Task> active = await _services.taskDao.findAllActive();
    final List<Task> completed = await _services.taskDao.findCompleted();

    final DateTime now = DateTime.now();
    final DateTime todayStart = DateTime(now.year, now.month, now.day);
    final DateTime todayEnd = todayStart.add(const Duration(days: 1));
    final DateTime next7End = todayEnd.add(const Duration(days: 6));

    int today = 0;
    int next7 = 0;
    final Map<String, int> listCounts = <String, int>{};
    String? inboxId;
    for (final TaskList l in lists) {
      if (l.name == '收集箱') inboxId = l.id;
    }

    for (final Task t in active) {
      if (t.completed) continue;
      final String key = t.listId ?? inboxId ?? 'inbox';
      listCounts[key] = (listCounts[key] ?? 0) + 1;
      final DateTime? due = t.dueDate?.toLocal();
      if (due == null) continue;
      // 计入口径（M1 简化）：今天 = 到期早于今日 24 点（含往日逾期）；
      // 最近 7 天 = 到期早于今天 +7 天。
      if (due.isBefore(todayEnd)) {
        today++;
        next7++;
      } else if (due.isBefore(next7End)) {
        next7++;
      }
    }

    return SidebarSnapshot(
      lists: lists,
      todayCount: today,
      next7Count: next7,
      allCount: active.where((Task t) => !t.completed).length,
      completedCount: completed.length,
      listCounts: listCounts,
    );
  }
}

/// 侧栏一次装载的不可变快照。
class SidebarSnapshot {
  const SidebarSnapshot({
    required this.lists,
    required this.todayCount,
    required this.next7Count,
    required this.allCount,
    required this.completedCount,
    required this.listCounts,
  });

  final List<TaskList> lists;
  final int todayCount;
  final int next7Count;
  final int allCount;
  final int completedCount;
  final Map<String, int> listCounts;

  int countFor(String listId) => listCounts[listId] ?? 0;
}
