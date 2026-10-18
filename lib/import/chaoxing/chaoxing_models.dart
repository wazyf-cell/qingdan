/// 学习通待办域模型（纯数据 + JSON 解析，无 IO）。
///
/// **来源声明**（AGENTS.md 禁止事项要求逐个文件标注）：接口地址、响应结构与
/// `activeType` 语义取自用户的油猴脚本 `扩展/作业列表.js`（上游
/// https://github.com/Cooanyh/chaoxing-list，AGPL-3.0-or-later，作者
/// lcandy2 / Coren）——具体参考位置：课程接口 :467、类型映射 :655、
/// 活动接口 :674、活动字段解析 :701-722、核心类型集合 :137、课程解析 :2264。
/// 这里只重写「读哪些字段」这层契约，未拷贝其 Vue UI 与遥测代码。
library;

/// 一门课（= 一个班级）。学习通的作业/考试都挂在 (courseId, clazzId) 上。
class ChaoxingCourse {
  const ChaoxingCourse({
    required this.courseId,
    required this.clazzId,
    required this.name,
  });

  final String courseId;
  final String clazzId;
  final String name;

  String get key => '$courseId|$clazzId';

  /// `backclazzdata?view=json` → `channelList[]`：只取 `cataid == 100000002`
  /// 的条目，课程在 `content.course.data[]`，班级 id 在外层 `key`。
  static List<ChaoxingCourse> parseCourseList(Map<String, Object?> json) {
    final List<ChaoxingCourse> out = <ChaoxingCourse>[];
    for (final Object? raw in (json['channelList'] as List<Object?>? ?? const [])) {
      final Map<String, Object?> channel = (raw! as Map<Object?, Object?>).cast();
      if (channel['cataid'].toString() != '100000002') continue;
      final Map<String, Object?> content =
          ((channel['content'] as Map<Object?, Object?>?) ?? const {}).cast();
      final Map<String, Object?> courseWrap =
          ((content['course'] as Map<Object?, Object?>?) ?? const {}).cast();
      for (final Object? c
          in (courseWrap['data'] as List<Object?>? ?? const [])) {
        final Map<String, Object?> course = (c! as Map<Object?, Object?>).cast();
        out.add(ChaoxingCourse(
          courseId: course['id'].toString(),
          clazzId: channel['key'].toString(),
          name: (course['name'] ?? '') as String,
        ));
      }
    }
    return dedupe(out);
  }

  /// 同一 (courseId, clazzId) 在 `channelList` 里会出现多次，不去重就会
  /// 对同一门课发重复请求，并把同一条活动收两遍（真机第一版就撞到了）。
  static List<ChaoxingCourse> dedupe(List<ChaoxingCourse> courses) {
    final Set<String> seen = <String>{};
    return courses.where((ChaoxingCourse c) => seen.add(c.key)).toList();
  }
}

/// 条目状态。**「已完成」是本地标记，不是服务端真值**：activelist 只有
/// `status` 1=进行中 / 2=已结束（脚本 :702-704），拿不到「用户交没交」；
/// 真完成状态只存在于 `stu-work` / `examcode` 两个 HTML 页（脚本 :757-832）。
/// 所以这里诚实地区分「已结束」（时间到了）与「已完成」（用户自己勾的）。
enum ChaoxingTaskState {
  todo('待办'),
  notStarted('未开始'),
  done('已完成'),
  ended('已结束');

  const ChaoxingTaskState(this.label);

  final String label;
}

/// 截止时间分桶（「按截止时间分类」用）。
enum ChaoxingDueBucket {
  overdue('已逾期'),
  today('今天'),
  tomorrow('明天'),
  week('7 天内'),
  later('更晚'),
  none('无截止');

  const ChaoxingDueBucket(this.label);

  final String label;

  static ChaoxingDueBucket of(DateTime? due, DateTime now) {
    if (due == null) return ChaoxingDueBucket.none;
    if (due.isBefore(now)) return ChaoxingDueBucket.overdue;
    if (due.year == now.year && due.month == now.month && due.day == now.day) {
      return ChaoxingDueBucket.today;
    }
    final DateTime tomorrow = DateTime(now.year, now.month, now.day + 1);
    if (due.year == tomorrow.year &&
        due.month == tomorrow.month &&
        due.day == tomorrow.day) {
      return ChaoxingDueBucket.tomorrow;
    }
    return due.difference(now).inDays < 7
        ? ChaoxingDueBucket.week
        : ChaoxingDueBucket.later;
  }
}

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

  /// 完成标记与忽略标记都按这个键存本地（不进数据库、不参与同步）。
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
      // 作业页条目（有 serverStatus）自带截止时间与提交状态，不参与合并——
      // 它和活动页同名条目不是「重发」关系，合掉会丢真作业。
      if (!t.ongoing || t.serverStatus != null) continue;
      final String k = '${t.courseId}|${t.kind}|${t.title}';
      final ChaoxingTask? prev = newest[k];
      if (prev == null || _isNewer(t, prev)) newest[k] = t;
    }
    final Set<ChaoxingTask> keep = newest.values.toSet();
    return tasks
        .where((ChaoxingTask t) =>
            !t.ongoing || t.serverStatus != null || keep.contains(t))
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

/// `activeType` 码表（学习通内部编号，逐条照抄脚本 :656-659）。
///
/// 11 / 46 / 74 三条是 2026-10-17 真机探针补的：样本标题分别是「选人」、
/// 一条音乐会公告、「位置签到20251110-签退」，语义明确才敢写进表。
/// **77 / 59 / 44 不写**：探针里它们是「计算投资收益数字特征」「讲解P12-14的
/// 练习」「推荐阅读书目.doc」这类杂项，JSON 里没有官方名称字段，猜一个标签
/// 比显示「其他任务」更糟。
const Map<Object, String> kActiveTypeNames = <Object, String>{
  0: '签到', 2: '签到', 4: '抢答', 5: '分组讨论', 6: '投票',
  11: '选人', 14: '问卷', 17: '直播', 23: '随堂练习', 35: '分组任务',
  42: '随堂练习', 43: '评分', 45: '拍照', 46: '通知', 47: '作业',
  64: '笔记', 74: '位置签到',
};

/// 核心类型（脚本 :137）——「只看核心类型」开关用它，把签到/投票/笔记这类
/// 一次性活动折叠掉。
const Set<String> kCoreKinds = <String>{
  '作业', '视频/任务点', 'AI实践', '分组讨论', '分组任务', '测验', '随堂练习', '考试',
};
