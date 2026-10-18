// 节次 → 像素的**纯函数**映射（`方案设计-课表域.md` §1.2 强制、细化 §2.2:68-80）。
//
// 渲染与「今日课程时间计算」必须调同一个函数（§6.3.2），所以这里不放 widget
// 代码、不读 `MediaQuery`，只暴露 [SectionLayout.yOf] 这一个分段线性函数。

import 'time_table.dart';

/// 每分钟对应的逻辑像素（dp）。细化 §2.2:70。
const double kMinutesToDp = 0.9;

/// 空档不超过该分钟数时**按比例**渲染（细化 §2.2:74：`g <= 15 -> g * k`）。
const int kGapProportionalMaxMinutes = 15;

/// 大空档（午休）压缩后的上下限（细化 §2.2:75：`g > 15 -> clamp(g * k, 14, 24)`）。
const double kGapMinDp = 14;
const double kGapMaxDp = 24;

/// 网格首节前与末节后各留的边距（细化 §2.2:76：映射不从 00:00 开始）。
const double kGridEdgePaddingDp = 8;

/// 课程块相对其槽位上下各缩进的像素（细化 §2.2:78：`top+1`、`height-2`），
/// 让相邻块之间露出 1dp 网格线。
const double kBlockInsetDp = 1;

/// 一节课在网格里的位置（dp，相对网格顶部）。
class SectionSlot {
  const SectionSlot({
    required this.section,
    required this.startMinutes,
    required this.endMinutes,
    required this.top,
    required this.height,
  });

  final int section;
  final int startMinutes;
  final int endMinutes;
  final double top;
  final double height;

  double get bottom => top + height;
}

/// 整张作息表换算出的网格布局。
class SectionLayout {
  SectionLayout({required this.slots})
      : totalHeight = slots.isEmpty
            ? 0
            : slots.last.bottom + kGridEdgePaddingDp,
        _bySection = <int, SectionSlot>{
            for (final SectionSlot s in slots) s.section: s,
          };

  final List<SectionSlot> slots;
  final double totalHeight;
  final Map<int, SectionSlot> _bySection;

  SectionSlot? slot(int section) => _bySection[section];

  /// 当日分钟数 → 网格 y 坐标（dp）。
  ///
  /// 节内线性插值，空档按**压缩后**的空档高度线性累积（细化 §2.2:77）。
  /// 越界不外推：早于第一节取第一节顶，晚于最后一节取最后一节底。
  double yOf(int minutes, {double k = kMinutesToDp}) {
    if (slots.isEmpty) return 0;
    if (minutes <= slots.first.startMinutes) return slots.first.top;
    for (int i = 0; i < slots.length; i++) {
      final SectionSlot s = slots[i];
      if (minutes <= s.endMinutes) {
        return s.top + (minutes - s.startMinutes) * k;
      }
      if (i + 1 >= slots.length) break;
      final SectionSlot next = slots[i + 1];
      if (minutes < next.startMinutes) {
        final int gapMinutes = next.startMinutes - s.endMinutes;
        final double gapPx = next.top - s.bottom;
        return s.bottom + (minutes - s.endMinutes) / gapMinutes * gapPx;
      }
    }
    return slots.last.bottom;
  }

  /// 课程块的位置；[missingSections] 非空时返回 null（该块进「未排时间」收纳区）。
  ({double top, double height})? rectFor(int startSection, int endSection) {
    if (missingSections(startSection, endSection).isNotEmpty) return null;
    final SectionSlot first = _bySection[startSection]!;
    final SectionSlot last = _bySection[endSection]!;
    final double top = yOf(first.startMinutes) + kBlockInsetDp;
    final double bottom = yOf(last.endMinutes) - kBlockInsetDp;
    return (top: top, height: bottom - top);
  }

  /// [startSection..endSection] 里有哪些节次不在作息表上。
  ///
  /// **绝不静默截断**（§3.4）：13-14 节的课不能因为作息表只到 12 节就画成 12 节。
  List<int> missingSections(int startSection, int endSection) => <int>[
        for (int s = startSection; s <= endSection; s++)
          if (!_bySection.containsKey(s)) s,
      ];

  /// 某节次的起止时间（当日分钟数）。
  ({int startMinutes, int endMinutes})? timeOf(int section) {
    final SectionSlot? s = _bySection[section];
    return s == null
        ? null
        : (startMinutes: s.startMinutes, endMinutes: s.endMinutes);
  }
}

/// 空档渲染高度：`g <= 15` 按比例，`g > 15` 压缩到 14~24dp（细化 §2.2:73-75）。
double gapHeightOf(int gapMinutes, {double k = kMinutesToDp}) =>
    gapMinutes <= kGapProportionalMaxMinutes
        ? gapMinutes * k
        : (gapMinutes * k).clamp(kGapMinDp, kGapMaxDp);

/// 按节次顺序排布 [details]。允许跳号（§2.2）：跳号处只是没有槽，不影响定位。
SectionLayout layoutSections(
  List<TimeDetail> details, {
  double k = kMinutesToDp,
}) {
  final List<TimeDetail> sorted = <TimeDetail>[...details]
    ..sort((TimeDetail a, TimeDetail b) => a.section.compareTo(b.section));
  final List<SectionSlot> slots = <SectionSlot>[];
  double cursor = kGridEdgePaddingDp; // 首节前的 8dp
  for (int i = 0; i < sorted.length; i++) {
    final TimeDetail d = sorted[i];
    if (i > 0) {
      cursor += gapHeightOf(d.startMinutes - sorted[i - 1].endMinutes, k: k);
    }
    final double height = (d.endMinutes - d.startMinutes) * k;
    slots.add(SectionSlot(
      section: d.section,
      startMinutes: d.startMinutes,
      endMinutes: d.endMinutes,
      top: cursor,
      height: height,
    ));
    cursor += height;
  }
  return SectionLayout(slots: slots);
}

/// `HH:MM` → 当日分钟数；格式不合法返回 null（UI 层输入校验用）。
///
/// 与 [formatMinutes] 成对：全链路只有「当日分钟数 int」一种时间表示（§1.2），
/// `TimeOfDay` 只允许出现在 UI 层，边界就在这里换算。
int? parseMinutes(String text) {
  final RegExpMatch? m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text.trim());
  if (m == null) return null;
  final int h = int.parse(m.group(1)!);
  final int min = int.parse(m.group(2)!);
  if (h < 0 || h > 23 || min < 0 || min > 59) return null;
  return h * 60 + min;
}

/// 当日分钟数 → `HH:MM`（节次轴与课程块显示用）。
String formatMinutes(int minutes) {
  final int h = minutes ~/ 60;
  final int m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}
