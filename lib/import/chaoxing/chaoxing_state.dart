/// 学习通条目的状态枚举、来源页枚举、截止分桶与类型码表（纯数据，无 IO）。
///
/// 从 `chaoxing_models.dart` 拆出（M6B §B3：加 `clazzId` 后单文件撞 300 行红线）。
///
/// **来源声明**：`activeType` 语义与核心类型集合取自油猴脚本 `扩展/作业列表.js`
/// （上游 Cooanyh/chaoxing-list，AGPL-3.0-or-later）——类型映射 :655、
/// 核心类型集合 :137、三个数据来源页 :463 / :467 / :674。
/// 只重写「读哪些字段」这层。
library;

/// 条目**来自哪个页面**。页签分界与「详情」URL 都按它走，不靠猜字段。
///
/// 为什么不能用 `kind` 判：`activelist` 里也有 `kind == '考试'` 的条目
/// （标题含「考试」时 `_kindOf` 就这么标，脚本 :664 同规则），但那是课程活动、
/// 没有 examId，与 `examcode` 两页抓出来的考试不是一回事。
enum ChaoxingSource {
  /// `mooc1-api.chaoxing.com/work/stu-work`（脚本 `extractTasks` :757-791）。
  homework('作业页'),

  /// `mobilelearn…/student/activelist`（脚本 `fetchCourseActivities` :670-722）。
  activity('活动接口'),

  /// `examcode` / `examcode/examlist` 两个考试页（脚本 :793-832 / :832-908）。
  exam('考试页');

  const ChaoxingSource(this.label);

  final String label;
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
