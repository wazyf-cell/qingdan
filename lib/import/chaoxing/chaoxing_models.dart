/// 学习通待办域模型（纯数据 + JSON 解析，无 IO）。
///
/// **来源声明**（AGENTS.md 禁止事项要求逐个文件标注）：接口地址、响应结构与
/// `activeType` 语义取自用户的油猴脚本 `扩展/作业列表.js`（上游
/// https://github.com/Cooanyh/chaoxing-list，AGPL-3.0-or-later，作者
/// lcandy2 / Coren）——具体参考位置：课程接口 :467、类型映射 :655、
/// 活动接口 :674、活动字段解析 :701-722、核心类型集合 :137、课程解析 :2264。
/// 这里只重写「读哪些字段」这层契约，未拷贝其 Vue UI 与遥测代码。
///
/// M6B §B3 拆分：课程实体见 `chaoxing_course.dart`，状态/分桶/码表见
/// `chaoxing_state.dart`；本文件用 [export] 兜住旧导入路径（`client` /
/// `time` / `grouping` / 测试都是 `import 'chaoxing_models.dart'`），
/// 搬家不改语义。
library;

import 'chaoxing_state.dart';

export 'chaoxing_course.dart';
export 'chaoxing_state.dart';

/// 一条外部待办（作业 / 考试 / 通知 / 各类课堂活动）。
class ChaoxingTask {
  const ChaoxingTask({
    required this.id,
    required this.courseId,
    required this.courseName,
    required this.title,
    required this.kind,
    required this.ongoing,
    this.startAt,
    this.dueAt,
    this.serverStatus,
    this.serverDone = false,
    this.unread = false,

    /// 班级 id：拼「详情」URL 必需（M6B §B3）。**可空**——`activelist` 的
    /// JSON 里活动条目本身不带 classId，作业页 `li[data]` 也有少数行没带。
    this.clazzId,

    /// 条目来自哪个页面；默认「活动接口」——它是唯一不额外带参数的来源。
    this.source = ChaoxingSource.activity,

    /// 考试的 `examId`（脚本 :823 / :871）。**只有考试解析器会填**：
    /// 拼考试那条 `examnotes` 地址非它不可（`chaoxing_links.dart`），
    /// 而 [id] 在缺 examId 时会被标题顶掉，不能拿 [id] 当它用。
    this.examId,

    /// 考试时长（分钟）/ 考试形式 / 分数：**只有考试解析器会填**
    /// （表格形态的第 [3]/[7]/[6] 列，脚本 :845-848）。扩展成品的考试列表
    /// 并不渲染这三列（它只渲染 名称 / 剩余 / 状态，:1295-1300），我们也不渲染，
    /// 但它们是通知里的字段，留在条目上才能对账与将来导出。
    this.durationMinutes,
    this.examForm,
    this.examScore,

    /// 列表页 `li[data]` 里那条**原样地址**（带服务端算好的 `enc_task`）。
    /// 只有作业解析器会填：它是「进题目页」唯一可用的入口，题目页真正的地址
    /// 连 `enc` 都只在那一页的脚本里（见 `chaoxing_work_detail.dart` 文件头）。
    this.detailEntryUrl,
  });

  /// 活动 id（`id` / `activeId`）或作业的 `taskrefId`。
  final String id;
  final String courseId;
  final String courseName;
  final String title;

  /// 归一化后的类型文案（作业 / 考试 / 签到 / …）。
  final String kind;

  /// 服务端 `status == 1`：这条活动还开着。`status == 2` 是已结束。
  final bool ongoing;

  /// 发布时间（脚本 :711 读 `startTime`）。签到类常常没有。
  final DateTime? startAt;

  /// 截止时间（脚本 :712 读 `endTime`；作业页由「剩余X小时」推得）。
  final DateTime? dueAt;

  /// 作业页服务端给的状态原文（未提交 / 已完成 / 待批阅）。活动类为 null。
  final String? serverStatus;

  /// 作业页服务端说这条已经交了。**活动的完成状态服务端不给**（见文件头）。
  final bool serverDone;

  /// 作业页的红点（`i.redPoint`）= 还没打开看过，扩展里叫「待打开」。
  final bool unread;

  /// 班级 id（作业页 `li[data]` 的 `clazzId`、考试两页的 `classId`）。
  /// 缺省时「详情」不可用。
  final String? clazzId;

  /// 来源页（页签分界与详情 URL 都按它走，见 `chaoxing_state.dart`）。
  final ChaoxingSource source;

  /// 考试的 `examId`；非考试条目恒为 null。见构造函数注释。
  final String? examId;

  /// 考试专属三列（时长分钟 / 形式 / 分数）；非考试条目恒为 null。
  final int? durationMinutes;
  final String? examForm;
  final String? examScore;

  /// 作业的题目入口（确认页地址）；非作业条目恒为 null。见构造函数注释。
  final String? detailEntryUrl;

  /// 完成标记与忽略标记都按这个键存本地（不进数据库、不参与同步）。
  ///
  /// **构成不能改**：`chaoxing.view.hidden` 里已存的隐藏项就是这个形状，
  /// 改了等于把用户隐藏过的条目全部放回来。
  String get key => '$courseId|$id';

  /// 当前时间是否落在 [startAt, dueAt] 闭区间内。**缺失的端点视为不设限**：
  /// 真机数据里大量条目根本没有 `endTime`，把「没有时间」当成「无效」会静默
  /// 吞掉真待办。
  bool inWindow(DateTime now) =>
      (startAt == null || !now.isBefore(startAt!)) &&
      (dueAt == null || !now.isAfter(dueAt!));

  /// 有效 = 服务端还开着 且 在时间窗内（即「仅显示有效作业」的判定）。
  bool isValidAt(DateTime now) => ongoing && inWindow(now);

  ChaoxingTaskState stateAt(DateTime now, {required bool done}) {
    if (done || serverDone) return ChaoxingTaskState.done;
    if (startAt != null && now.isBefore(startAt!)) {
      return ChaoxingTaskState.notStarted;
    }
    if (!ongoing) return ChaoxingTaskState.ended;
    if (dueAt != null && now.isAfter(dueAt!)) return ChaoxingTaskState.ended;
    return ChaoxingTaskState.todo;
  }

  static List<ChaoxingTask> parseActivities(
    Map<String, Object?> json, {
    required String courseId,
    required String courseName,
    String? clazzId,
  }) {
    // activelist 的包壳层级在不同课程下不一致，取第一个能当列表用的。
    final Object? wrapped = json['data'];
    final List<Object?> list = wrapped is Map
        ? ((wrapped['activeList'] as List<Object?>?) ?? const [])
        : (wrapped as List<Object?>? ?? const []);
    return dedupe(list
        .map((Object? raw) {
          final Map<String, Object?> item = (raw! as Map<Object?, Object?>).cast();
          return ChaoxingTask(
            id: (item['id'] ?? item['activeId'] ?? '').toString(),
            courseId: courseId,
            courseName: courseName,
            title: (item['nameOne'] ?? item['name'] ?? item['title'] ?? '未知任务')
                as String,
            kind: _kindOf(item),
            ongoing: item['status'] == 1,
            startAt: _stamp(item['startTime']),
            dueAt: _stamp(item['endTime']),
            // 活动自己不带 classId，用请求参数（= 课程表的班级）兜。
            clazzId: (item['classId'] ?? item['clazzid'] ?? clazzId)?.toString(),
          );
        })
        .toList());
  }

  /// 同一门课的活动列表本身会重复投递（真机第一版看到过同一条出现两次）。
  static List<ChaoxingTask> dedupe(List<ChaoxingTask> tasks) {
    final Set<String> seen = <String>{};
    return tasks.where((ChaoxingTask t) => seen.add(t.key)).toList();
  }

  /// 合并「同一门课、同类型、同标题」的**进行中**条目，只留发布最晚的那条。
  ///
  /// 2026-10-17 真机探针：概率论的「1.3-医疗诊断系统的概率建模」在服务端就是
  /// 两条不同 id、不同 startTime 的记录（老师重发），按 activeId 去重去不掉，
  /// 界面上就是两行一模一样的待办。已结束的不合并——历史要留痕。
  static List<ChaoxingTask> mergeRepublished(List<ChaoxingTask> tasks) {
    final Map<String, ChaoxingTask> newest = <String, ChaoxingTask>{};
    for (final ChaoxingTask t in tasks) {
      // 只合**活动接口**来的条目。作业页与考试页（`serverStatus != null` 或
      // `source != activity`）各自带服务端状态与绝对时刻，同名也不是「重发」
      // 关系——合掉会丢真作业 / 丢另一页形态的考试（两个考试页是互补的，
      // 脚本 :1439-1470 只按 `examId || title` 去重，从不相消）。
      if (!t.ongoing ||
          t.serverStatus != null ||
          t.source != ChaoxingSource.activity) {
        continue;
      }
      final String k = '${t.courseId}|${t.kind}|${t.title}';
      final ChaoxingTask? prev = newest[k];
      if (prev == null || _isNewer(t, prev)) newest[k] = t;
    }
    final Set<ChaoxingTask> keep = newest.values.toSet();
    return tasks
        .where((ChaoxingTask t) =>
            !t.ongoing ||
            t.serverStatus != null ||
            t.source != ChaoxingSource.activity ||
            keep.contains(t))
        .toList();
  }

  static bool _isNewer(ChaoxingTask a, ChaoxingTask b) {
    if (a.startAt == null) return false;
    if (b.startAt == null) return true;
    return a.startAt!.isAfter(b.startAt!);
  }

  /// `startTime` / `endTime` 是毫秒时间戳；脚本用 `new Date(x)` 直接吃，
  /// 这里同样只认数字，字符串日期按 ISO 试解析（超星两种都发过）。
  static DateTime? _stamp(Object? v) {
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    if (v is String && v.isNotEmpty) {
      return DateTime.tryParse(v.replaceAll(' ', 'T'));
    }
    return null;
  }

  /// 类型判定顺序照抄脚本 :661-666：标题关键词优先于 activeType 码表。
  /// AI 那条比脚本放宽了——脚本的 `AI\s*实践` 要求「实践」紧跟 AI，
  /// 真机标题是「…随机事件关系运算 AI 情境对话实践」，中间隔了四个字，
  /// 脚本和我们第一版都漏判成「其他任务」。
  static String _kindOf(Map<String, Object?> item) {
    final String title =
        '${item['nameOne'] ?? item['name'] ?? item['title'] ?? ''}';
    if (RegExp(r'AI', caseSensitive: false).hasMatch(title) &&
        (title.contains('实践') ||
            title.contains('对话') ||
            title.contains('评价'))) {
      return 'AI实践';
    }
    if (title.contains('分组') && title.contains('讨论')) return '分组讨论';
    if (title.contains('考试')) return '考试';
    if (title.contains('测验') || title.contains('练习')) return '测验';
    return kActiveTypeNames[item['activeType']] ??
        kActiveTypeNames[item['type']] ??
        '其他任务';
  }
}
