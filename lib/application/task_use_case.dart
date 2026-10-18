import 'package:qingdan/application/app_services.dart';
import 'package:qingdan/domain/tag.dart';
import 'package:qingdan/domain/task.dart';
import 'package:qingdan/domain/task_list.dart';
import 'package:qingdan/domain/task_priority.dart';

/// 任务用例（M1 最小集）：UI 层唯一入口，封装「写库 + 记 op-log」。
///
/// DAO 的写方法自身持有事务并同步写 op-log；本层负责业务规则
/// （完成时间、排序取值、回收站时间戳）与读聚合，不暴露 DAO。
class TaskUseCase {
  TaskUseCase(this._services);

  final AppServices _services;

  // ---- 读 ----

  /// 智能清单/清单共用的全量未删除任务（UI 侧再过滤，数据量自用可控）。
  Future<List<Task>> findAllActive() => _services.taskDao.findAllActive();

  Future<List<Task>> findCompleted() => _services.taskDao.findCompleted();

  Future<List<Task>> findTrashed() => _services.taskDao.findTrashed();

  Future<Task?> findById(String id) => _services.taskDao.findById(id);

  Future<List<Subtask>> findSubtasks(String taskId) =>
      _services.subtaskDao.findByTask(taskId);

  Future<List<Tag>> findTagsOf(String taskId) =>
      _services.tagDao.findByTask(taskId);

  Future<List<Tag>> findAllTags() => _services.tagDao.findAll();

  Future<List<TaskList>> findLists() => _services.taskListDao.findAll();

  // ---- 写 ----

  /// 新建任务。[sortOrder] 缺省取目标清单当前最小值 -1（新任务排最前）。
  Future<Task> create({
    required String title,
    String? listId,
    DateTime? dueDate,
    DateTime? startDate,
    DateTime? endDate,
    TaskPriority priority = TaskPriority.none,
    String note = '',
    int? sortOrder,
  }) async {
    final int order = sortOrder ??
        await _nextSortOrder(listId);
    return _services.taskDao.insert(
      title: title,
      listId: listId,
      dueDate: dueDate,
      startDate: startDate,
      endDate: endDate,
      priority: priority,
      note: note,
      sortOrder: order,
    );
  }

  /// 完成状态切换（F3）：完成记 completedTime，取消清空。
  Future<void> setCompleted(Task task, bool completed) {
    final DateTime now = DateTime.now().toUtc();
    return _services.taskDao.update(task.copyWith(
      completed: completed,
      completedTime: completed ? now : null,
      modifiedTime: now,
    ));
  }

  /// 字段级更新（标题/备注/优先级/清单/起止/到期）。
  Future<void> update(Task task) =>
      _services.taskDao.update(task.copyWith(
        modifiedTime: DateTime.now().toUtc(),
      ));

  /// 手动排序（F9）：按给定 id 顺序写 sort_order。
  Future<void> reorder(List<Task> ordered) async {
    for (int i = 0; i < ordered.length; i++) {
      if (ordered[i].sortOrder != i) {
        await _services.taskDao
            .update(ordered[i].copyWith(sortOrder: i));
      }
    }
  }

  /// 移入回收站（F4）。返回标题供 SnackBar 展示。
  Future<String> moveToTrash(String id) async {
    final Task? task = await _services.taskDao.findById(id);
    if (task == null) return '';
    await _services.taskDao.moveToTrash(id);
    return task.title;
  }

  /// 从回收站恢复（F4）。
  Future<void> restore(String id) async {
    final Task? task = await _services.taskDao.findById(id);
    if (task == null) return;
    await _services.taskDao.update(task.copyWith(
      deleted: false,
      deletedTime: null,
      modifiedTime: DateTime.now().toUtc(),
    ));
  }

  /// 彻底删除（F4）：不可撤销，子任务外键 CASCADE。
  Future<void> deleteForever(String id) =>
      _services.taskDao.deleteForever(id);

  /// 清空回收站（F4）。
  Future<void> emptyTrash() async {
    final List<Task> trashed = await _services.taskDao.findTrashed();
    for (final Task t in trashed) {
      await _services.taskDao.deleteForever(t.id);
    }
  }

  /// 回收站自动清空（M6-A4）：物理删除入站超过 [days] 天的任务，返回条数。
  /// `days <= 0` = 永不：直接返回 0，不调 DAO。
  /// 阈值语义与界面文案见 `TrashPurgeScheduler`（启动 + 应用存活期每 30 分钟检查）。
  Future<int> purgeExpiredTrash({required int days}) async {
    if (days <= 0) return 0;
    final DateTime cutoff =
        DateTime.now().toUtc().subtract(Duration(days: days));
    return _services.taskDao.purgeTrashedBefore(cutoff);
  }

  // ---- 子任务（F5）----

  Future<Subtask> addSubtask({
    required String taskId,
    required String title,
    int sortOrder = 0,
  }) =>
      _services.subtaskDao.insert(
          taskId: taskId, title: title, sortOrder: sortOrder);

  Future<void> setSubtaskCompleted(Subtask subtask, bool completed) {
    return _services.subtaskDao.update(subtask.copyWith(
      completed: completed,
      modifiedTime: DateTime.now().toUtc(),
    ));
  }

  Future<void> updateSubtask(Subtask subtask) =>
      _services.subtaskDao.update(subtask);

  Future<void> deleteSubtask(String id) => _services.subtaskDao.delete(id);

  // ---- 标签（F11，详情挂/摘）----

  Future<void> attachTag({required String taskId, required String tagId}) =>
      _services.tagDao.attachToTask(taskId: taskId, tagId: tagId);

  Future<void> detachTag({required String taskId, required String tagId}) =>
      _services.tagDao.detachFromTask(taskId: taskId, tagId: tagId);

  Future<Tag> createTag(String name) => _services.tagDao.insert(name: name);

  /// 目标清单当前最小 sort_order - 1（空清单返回 0）。
  Future<int> _nextSortOrder(String? listId) async {
    final List<Task> tasks = await _services.taskDao.findAllActive();
    int min = 0;
    for (final Task t in tasks) {
      if (t.listId == listId && t.sortOrder < min) min = t.sortOrder;
    }
    return min - 1;
  }
}
