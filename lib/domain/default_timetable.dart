import 'time_table.dart';

/// 内置默认作息模板（M6-D §三，2026-10-18 用户定案）。
///
/// 用户原文 12 行**逐字照抄**（每节 45 分钟、课间 10 分钟、11:40~14:00 午休），
/// 一个数字都不许改。注意这张表 `generateTimeDetails()` 生成不出来：
/// 第 2 节 09:40 结束后第 3 节是 10:00（**20 分钟大课间**，不是 10 分钟），
/// 午休是 **140 分钟**（不是表单默认的 90）——所以它必须是硬编码常量。
///
/// 表内数字是「当日分钟数」（§1.2 强制约定），每行注释保留用户原文时刻。
const String kBuiltInTimetableId = 'builtin-college';
const String kBuiltInTimetableName = '大学默认';

/// 固定 id 前缀后缀格式：'builtin-college-01' … 'builtin-college-12'。
/// **必须用固定 id**（不用 IdGenerator.next()），否则两台设备 seed 出不同 id
/// 会各自同步一份，模板库会变成两份「大学默认」。
String builtInDetailId(int section) =>
    '$kBuiltInTimetableId-${section.toString().padLeft(2, '0')}';

/// 12 节内容（start / end 为当日分钟数，注释为用户原文 HH:MM）。
const List<({int section, int start, int end})> kBuiltInTimeDetails =
    <({int section, int start, int end})>[
  (section: 1, start: 480, end: 525), // 08:00 – 08:45
  (section: 2, start: 535, end: 580), // 08:55 – 09:40
  (section: 3, start: 600, end: 645), // 10:00 – 10:45
  (section: 4, start: 655, end: 700), // 10:55 – 11:40
  (section: 5, start: 840, end: 885), // 14:00 – 14:45
  (section: 6, start: 895, end: 940), // 14:55 – 15:40
  (section: 7, start: 960, end: 1005), // 16:00 – 16:45
  (section: 8, start: 1015, end: 1060), // 16:55 – 17:40
  (section: 9, start: 1140, end: 1185), // 19:00 – 19:45
  (section: 10, start: 1195, end: 1240), // 19:55 – 20:40
  (section: 11, start: 1250, end: 1295), // 20:50 – 21:35
  (section: 12, start: 1305, end: 1350), // 21:45 – 22:30
  ];

/// 转成领域对象（[timetableId] 传落库用的表 id，测试与 seed 共用这一份真源）。
///
/// 返回的 `TimeDetail.id` 为 `'<timetableId>-NN'`（两位补零，§2.3 的固定 id）。
List<TimeDetail> builtInDetails(String timetableId) => <TimeDetail>[
      for (final ({int section, int start, int end}) d in kBuiltInTimeDetails)
        TimeDetail(
          id: '$timetableId-${d.section.toString().padLeft(2, '0')}',
          timetableId: timetableId,
          section: d.section,
          startMinutes: d.start,
          endMinutes: d.end,
        ),
    ];