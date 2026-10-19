/// 学习通「考试」两个页面形态的 HTML 解析（纯函数，无 IO）。
///
/// **来源声明**（AGENTS.md 移植必须声明来源）：选择器与取值位置逐条照抄用户目录
/// 里的油猴脚本 `扩展/作业列表.js`（上游 https://github.com/Cooanyh/chaoxing-list，
/// AGPL-3.0-or-later，作者 lcandy2 / Coren）——
///  - **两个地址都要抓**：`URL_EXAM` :463（卡片形态）与 `API_EXAM_LIST` :911
///    （表格形态）。脚本自己就是两个各抓一次、再按 `examId || title` 合并去重
///    （`todo-list` :1433-1473、仪表盘 :3405-3432）——它们是**不同页面形态**，
///    不是冗余，所以两条解析全部移植。
///  - 卡片形态 = `extractExams` :793-832：`#chaoxing-assignment-wrapper
///    ul.ks_list > li`（退路 `ul.ks_list > li`）、`dl > dt`=标题、`dl > dd`=
///    相对剩余时间、`span.ks_state`=状态、`div.ks_pic > img` 的 `src` 含
///    `ks_02`=已过期、`li[data]` 里 `taskrefId`→examId / `courseId` / `classId`
///    （:816-827）、完成判定 :828（状态含「已完成」或「待批阅」）。
///  - 表格形态 = `extractExamsFromTable` :832-908：`table.dataTable tr.dataTr`、
///    不足 9 个 `td` 整行跳过（:840）、列序 :842-849（[1]名称 [2]时间区间
///    [3]时长 [4]考试状态 [5]作答状态 [6]分数（空则 `---`）[7]考试形式
///    [8]操作链接）、三个 id 从 `onclick` 的 `go('…')` 里那串地址的 `refer`
///    参数解出（:861-871），解不动退回在 `onclick` 上直接正则
///    `moocId=` / `clazzid=` / `examId=`（:873-878）、判据 :882-885。
///  - 相对时间 :3268-3281（与作业页共用 `chaoxing_time.dart` 的 [parseRemaining]）。
///
/// 只重写「读哪些字段」这层：未拷贝其 Vue 模板、`v-data-table` 组件与遥测代码。
/// 页面本身不给、由我们补的两件事（卡片形态的绝对截止时刻、表格形态的时间区间
/// 拆分）各自写在函数注释里。
library;

import 'chaoxing_html.dart';
import 'chaoxing_models.dart';
import 'chaoxing_time.dart';

class ChaoxingExam {
  ChaoxingExam._();

  /// 两个考试页都不给课程名：卡片形态只有 courseId，表格形态连 courseId 都要从
  /// 操作链接里捞。回查课程表拿真名，拿不到就用脚本自己在待办区写的那个占位
  /// （:1445 / :1466 的 `"考试课程"`），不编课程名。
  static const String kUnknownCourse = '考试课程';

  // ---- 卡片形态（examcode 页）----
  static final RegExp _kLi = RegExp(r'<li\b([^>]*)>([\s\S]*?)</li>');
  static final RegExp _kDl = RegExp(r'<dl\b[^>]*>([\s\S]*?)</dl>');
  static final RegExp _kDt = RegExp(r'<dt\b[^>]*>([\s\S]*?)</dt>');
  static final RegExp _kDd = RegExp(r'<dd\b[^>]*>([\s\S]*?)</dd>');
  static final RegExp _kState = RegExp(
      r'<span\b[^>]*class="[^"]*\bks_state\b[^"]*"[^>]*>([\s\S]*?)</span>');
  static final RegExp _kPic = RegExp(
      r'<div\b[^>]*class="[^"]*\bks_pic\b[^"]*"[^>]*>([\s\S]*?)</div>');
  static final RegExp _kImgSrc = RegExp(r'<img\b[^>]*\bsrc="([^"]*)"');

  // ---- 表格形态（examlist 页）----
  static final RegExp _kTr = RegExp(
      r'<tr\b[^>]*class="[^"]*\bdataTr\b[^"]*"[^>]*>([\s\S]*?)</tr>');
  static final RegExp _kTd = RegExp(r'<td\b[^>]*>([\s\S]*?)</td>');
  static final RegExp _kAnchor = RegExp(r'<a\b([^>]*)>');
  static final RegExp _kGo = RegExp('''go\\(\\s*['"]([^'"]+)['"]''');
  static final RegExp _kStamp =
      RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})');

  /// 卡片形态：`ul.ks_list > li`（脚本 `extractExams` :793-832）。
  ///
  /// 页面只给相对时间（`dd` 里的「剩余X小时」），**绝对截止 = 抓取时刻 + 剩余**，
  /// 与作业页同一补法（`chaoxing_homework.dart` 同规则）；没有开始时间可给，
  /// `startAt` 留空。
  static List<ChaoxingTask> parseCards(
    String html, {
    required Map<String, String> courseNames,
    required DateTime now,
  }) {
    final List<ChaoxingTask> out = <ChaoxingTask>[];
    for (final RegExpMatch li in _kLi.allMatches(html)) {
      final String body = li.group(2)!;
      // 脚本 :799 先取 `dl` 再在它里面找 dt/dd（dl 之外的 dt 不算标题），同形。
      final String dl = _kDl.firstMatch(body)?.group(1) ?? body;
      final String title = htmlText(_kDt.firstMatch(dl)?.group(1) ?? '');
      if (title.isEmpty) continue;
      final String timeLeft = htmlText(_kDd.firstMatch(dl)?.group(1) ?? '');
      final String status = htmlText(_kState.firstMatch(body)?.group(1) ?? '');
      // :812-813 只看 `div.ks_pic` 里那张图的 src：含 `ks_02` = 换成了「已截止」图。
      bool expired = (_kImgSrc
                  .firstMatch(_kPic.firstMatch(body)?.group(1) ?? '')
                  ?.group(1) ??
              '')
          .contains('ks_02');
      // 文字形态的同一件事：脚本 :885 给过期行写的就是「已结束」，:3272 把含
      // 「过期」当已过去。两种写法都收在同一个标记上。
      if (timeLeft.contains('过期') || timeLeft.contains('已结束')) expired = true;
      final Map<String, String> p = queryOf(attrOf(li.group(1)!, 'data'));
      final Duration? left = parseRemaining(timeLeft);
      out.add(_task(
        examId: p['taskrefId'] ?? '',
        title: title,
        courseId: p['courseId'] ?? '',
        courseNames: courseNames,
        clazzId: p['classId'],
        dueAt: left == null ? null : now.add(left),
        status: status,
        expired: expired,
        // :828 同判：状态含「已完成」或「待批阅」就是交过了。
        finished: status.contains('已完成') || status.contains('待批阅'),
      ));
    }
    return ChaoxingTask.dedupe(out);
  }

  /// 表格形态：`table.dataTable tr.dataTr`（脚本 `extractExamsFromTable`
  /// :832-908）。这一页的时间列是**绝对值**，直接拆成开始/结束两个时刻。
  static List<ChaoxingTask> parseTable(
    String html, {
    required Map<String, String> courseNames,
    required DateTime now,
  }) {
    final List<ChaoxingTask> out = <ChaoxingTask>[];
    for (final RegExpMatch tr in _kTr.allMatches(html)) {
      final List<String> cells = <String>[], raw = <String>[];
      for (final RegExpMatch td in _kTd.allMatches(tr.group(1)!)) {
        raw.add(td.group(1)!);
        cells.add(htmlText(td.group(1)!));
      }
      if (cells.length < 9) continue; // :840 同规则：列数不足的行整行不要
      if (cells[1].isEmpty) continue; // 没有考试名称的行留不住（隐藏键会撞）
      final ({DateTime? start, DateTime? end}) span = _rangeOf(cells[2]);
      final String examStatus = cells[4], answerStatus = cells[5];
      final Map<String, String> ids = _idsOf(raw[8]);
      // :882 只认「考试状态」列里的「已结束」。但那一列不刷新、结束时刻却已经
      // 过去的情况真实存在（2026-10-19 用户那条「10-11 22:00 结束」的单元测验
      // 就是），所以再加一道**按绝对结束时刻**判的闸：过点了就算关掉了——
      // 卡片显示「已过期」、「仅看未完成」筛掉、提醒快照排除。
      final bool expired = examStatus.contains('已结束') ||
          (span.end != null && !span.end!.isAfter(now));
      out.add(_task(
        // :871 的 examId 可能是空串（那一行没有可解析的链接），交给 _task 兜底。
        examId: ids['examId'] ?? '',
        title: cells[1],
        courseId: ids['courseId'] ?? '',
        courseNames: courseNames,
        clazzId: ids['classId'],
        startAt: span.start,
        dueAt: span.end,
        // :884：作答状态优先，没有才退到考试状态。
        status: answerStatus.isNotEmpty ? answerStatus : examStatus,
        expired: expired,
        // :883 同判（「待批阅」也算交过了，扩展显示成「已完成」:5674）。
        finished: answerStatus.contains('已完成') || answerStatus.contains('待批阅'),
        durationMinutes: parseRemaining(cells[3])?.inMinutes,
        examForm: cells[7],
        examScore: cells[6].isEmpty ? '---' : cells[6], // :848 的缺省值
      ));
    }
    return ChaoxingTask.dedupe(out);
  }

  /// 一行考试 → 条目。作业 / 活动两条解析路径不共用它（字段形状不同，硬合会
  /// 让「考试专属列是 null」这件事变成所有人的默认值）。
  static ChaoxingTask _task({
    required String examId,
    required String title,
    required String courseId,
    required Map<String, String> courseNames,
    required String status,
    required bool expired,
    bool finished = false,
    String? clazzId,
    DateTime? startAt,
    DateTime? dueAt,
    int? durationMinutes,
    String? examForm,
    String? examScore,
  }) =>
      ChaoxingTask(
        // 脚本 :1440 / :1461 的判重键就是 `examId || title`：缺 id 时用标题顶，
        // 否则同一门课两条无名考试会撞成同一个隐藏键（`courseId|`）。
        // 标题为空的行在两个 parse* 里就被丢掉了，这里不会拿到空标题。
        id: examId.isNotEmpty ? examId : title,
        courseId: courseId,
        courseName: courseNames[courseId] ?? kUnknownCourse,
        title: title,
        kind: '考试',
        source: ChaoxingSource.exam,
        // 服务端还开着 = 没被判过期。绝对结束时刻已过去的情况在上面已经并进
        // expired，所以这条也挡住了「状态列没刷新但已经考完」的考试。
        ongoing: !expired,
        startAt: startAt,
        dueAt: dueAt,
        serverStatus: status.isEmpty ? null : status,
        serverDone: finished,
        clazzId: (clazzId == null || clazzId.isEmpty) ? null : clazzId,
        examId: examId.isEmpty ? null : examId,
        durationMinutes: durationMinutes,
        examForm: examForm,
        examScore: examScore,
      );

  /// 时间区间列拆成开始 / 结束两个绝对时刻。
  ///
  /// 脚本 :844 把整列当一根不透明字符串（只用于展示与「已结束」判定），我们
  /// 必须拆：考试比作业多一个**开始时间**，而提醒链路只认绝对 `dueAt`。
  /// `yyyy-M-d H:mm` 全部命中项，第一个当开始、最后一个当结束；
  /// **只命中一个时两个都不填**——分不清那是开始还是结束，猜错会把「还没开始」
  /// 排成「快截止」的提醒，宁可不给（与 `chaoxing_models.dart` 的「缺失端点
  /// 视为不设限」同一取向）。
  static ({DateTime? start, DateTime? end}) _rangeOf(String text) {
    final List<DateTime> hits = <DateTime>[
      for (final RegExpMatch m in _kStamp.allMatches(text))
        DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!),
            int.parse(m.group(3)!), int.parse(m.group(4)!), int.parse(m.group(5)!)
        ),
    ];
    if (hits.length < 2) return (start: null, end: null);
    return (start: hits.first, end: hits.last);
  }

  /// 操作单元格里的三个 id：`courseId` / `classId` / `examId`。
  ///
  /// 照脚本 :861-878 的三段退路：`onclick="go('…')"` 里那串地址 → 它的 `refer`
  /// 参数（再解一次百分号）→ 退路直接在 onclick/地址上正则 `moocId=` /
  /// `clazzid=` / `examId=`。**额外加一条退路**：有些行是普通 `<a href="…">`
  /// 而不是 go()（脚本没这形态，会连 courseId 都拿不到），这里把 href 也当
  /// 那串地址用。三个都拿不到就返回空——详情 URL 拼不出来时如实返回 null
  /// （见 `chaoxing_links.dart`），不编参数。
  static Map<String, String> _idsOf(String cellHtml) {
    final String anchor = _kAnchor.firstMatch(cellHtml)?.group(1) ?? '';
    final String onclick = attrOf(anchor, 'onclick');
    final String href = attrOf(anchor, 'href');
    final String raw = _kGo.firstMatch(onclick)?.group(1) ?? href;
    final Map<String, String> outer = queryOf(raw);
    String refer = outer['refer'] ?? '';
    // refer 可能被整体二次转义（脚本 :867 又 decode 了一次）：解完还剩 %3D/%26
    // 就再解一次。解不动保持原样，后面还有正则退路。
    if (refer.contains('%3D') || refer.contains('%26')) {
      try {
        refer = Uri.decodeFull(refer);
      } catch (_) {}
    }
    final Map<String, String> inner = queryOf(refer);
    final String blob = '$onclick$raw$href';
    return <String, String>{
      'courseId': _pair(inner['courseId'], outer['moocId'], blob, 'moocId'),
      'classId': _pair(inner['classId'], outer['clazzid'], blob, 'clazzid'),
      'examId': _pair(inner['examId'], '', blob, 'examId'),
    };
  }

  /// 取值优先序：refer 里的 > 外层地址里的 > 在整串 onclick 上正则到的
  /// （脚本 :869-871 与 :873-878 正是这个次序）。
  static String _pair(String? a, String? b, String blob, String name) {
    if ((a ?? '').isNotEmpty) return a!;
    if ((b ?? '').isNotEmpty) return b!;
    return RegExp('$name=(\\d+)').firstMatch(blob)?.group(1) ?? '';
  }
}
