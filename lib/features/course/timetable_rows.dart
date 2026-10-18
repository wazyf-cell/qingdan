import 'package:flutter/material.dart';

import 'package:qingdan/domain/time_table.dart';

import 'course_steppers.dart';

/// 时间格的账本键：同一节的「开始」「结束」各占一格。
String timeCellKey(int section, String tag) => '$section-$tag';

/// 一行节次的「值指纹」——用来判断某一格的文本是不是已被草稿真值覆盖回去。
String pairOf(TimeDetail d) => '${d.startMinutes}-${d.endMinutes}';

/// 节次 → 值指纹的快照（改动前后各取一次）。
Map<int, String> snapshotOf(List<TimeDetail> details) => <int, String>{
      for (final TimeDetail d in details) d.section: pairOf(d),
    };

/// 按节次号找行（节次是序号，允许跳号，所以只能线性找）。
TimeDetail? rowOf(List<TimeDetail> details, int section) {
  for (final TimeDetail d in details) {
    if (d.section == section) return d;
  }
  return null;
}

/// 时间格「能不能解析」的账本：**记录与染红分家**（M6-A1）。
///
/// 为什么必须分家：`parseMinutes` 只认完整的 `HH:MM`，用户敲到一半（`0`、`09`、
/// `09:`、`09:3`）必然解析不过。旧版把「解析不过」直接当非法：每敲一个字符红一次，
/// helperText 与 `tt-error` 一出现/消失就把行高与底部按钮行顶得上下抖；清空成空串
/// 也算非法。
///
/// 现在的规矩：
/// - **记录**照旧每次上报都做（键 → 当前解析不过的原文）→ 点保存一定拦得住。
///   这条正是「框里写着 26:00、库里还是旧值」那个静默丢弃 bug 的解药，不能丢。
/// - **染红**只在文本已经长成 5 字符的完整形状却仍解析不过（[isInvalidFullTime]），
///   或用户点了保存（[revealAll]）。红态一旦上就留住，否则退格时又要闪一次。
/// - 空串 = 「这一格还没填」，既不留记录也不红。
class TimeCellRecords {
  final Map<String, String> _raw = <String, String>{};
  final Set<String> _shown = <String>{};

  bool get isEmpty => _raw.isEmpty;
  int get count => _raw.length;

  /// 第一条非法原文（保存被拦住时复述给用户）。不变式 `_shown ⊆ _raw`。
  String? get firstRaw => _raw.isEmpty ? null : _raw.values.first;

  /// 该染红的格子键集合，直接交给 [TimetableRows] 渲染。
  Set<String> get shownKeys => _shown;

  /// 载入就越界的历史脏数据（如 `24:35`）：记账 + 当场红，不自动 clamp。
  void markLoaded(int section, String tag, String raw) {
    final String key = timeCellKey(section, tag);
    _raw[key] = raw;
    _shown.add(key);
  }

  /// 单元格上报「当前文本解析不过」。返回要展示的红色错误文案；
  /// null = 只记账、不上色也不开口；空串 = 红框与错误行都该解除。
  String? mark(int section, String tag, String raw) {
    final String key = timeCellKey(section, tag);
    if (raw.isEmpty) {
      _raw.remove(key);
      _shown.remove(key);
      // 已经没有任何红格子 → 让错误行也退场（账上若只剩「还没敲完」的格子，
      // 它们本来就不该说话，留着上一条错误文案只会指着一个不红的格子）。
      return _shown.isEmpty ? '' : null;
    }
    _raw[key] = raw;
    if (!isInvalidFullTime(raw) && !_shown.contains(key)) return null;
    _shown.add(key);
    final String which = tag == 'start' ? '开始' : '结束';
    return '第 $section 节$which时间「$raw」不合法，应为 HH:MM（00:00–23:59）';
  }

  /// 点保存：把只记了账、还没长成完整形状的格子也一并染红（「拦住」的可见形式）。
  void revealAll() => _shown.addAll(_raw.keys);

  /// 某一格的账清了。返回是否真的动过账（调用方据此决定要不要 setState）。
  bool clear(String key) {
    final bool had = _raw.containsKey(key) || _shown.contains(key);
    _raw.remove(key);
    _shown.remove(key);
    return had;
  }

  void clearAll() {
    _raw.clear();
    _shown.clear();
  }

  /// 草稿变更后清掉「那一节的值已被真值覆盖回去」的账，否则留下找不到主的红框。
  void dropChanged(Map<int, String> before, List<TimeDetail> now) {
    _raw.removeWhere((String key, String _) {
      final int section = int.parse(key.substring(0, key.lastIndexOf('-')));
      final String? old = before[section];
      final TimeDetail? row = rowOf(now, section);
      if (old == null || row == null) return true;
      return old != pairOf(row);
    });
    _shown.removeWhere((String key) => !_raw.containsKey(key));
  }
}

/// 节次行列表：表头 + 每行「节 | 开始 | 结束 | 删除」。
///
/// 从 `timetable_editor.dart` 拆出来是因为 A1 加完校验后面板本体要超 300 行红线。
/// 本组件**无状态**：草稿、非法原文、resync 计数都归面板，行只渲染与上报。
class TimetableRows extends StatelessWidget {
  const TimetableRows({
    super.key,
    required this.details,
    required this.shownKeys,
    required this.revision,
    required this.onStart,
    required this.onEnd,
    required this.onInvalid,
    required this.onDelete,
    this.maxHeight = 240,
  });

  final List<TimeDetail> details;

  /// 面板决定「此刻该红」的格子键集合（键格式 `'$section-$tag'`）。
  /// 注意它**不等于**「解析不过的格子」：敲到一半的那些只记账、不在这里。
  final Set<String> shownKeys;

  /// 面板拒绝一次改动时递增它，逼格子把文本回读成草稿真值。
  final int revision;

  final void Function(int section, int minutes) onStart;
  final void Function(int section, int minutes) onEnd;
  final void Function(int section, String tag, String raw) onInvalid;
  final void Function(TimeDetail target) onDelete;
  final double maxHeight;

  bool _bad(int section, String tag) => shownKeys.contains(timeCellKey(section, tag));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: const <Widget>[
            Expanded(child: Text('节')),
            Expanded(child: Text('开始')),
            Expanded(child: Text('结束')),
            SizedBox(width: 48),
          ],
        ),
        ConstrainedBox(
          // 列表限高可滚，所以错误红字**不能**放在它上面（手机上改第 8 节时
          // 红字已经在可视区外，2026-10-18 用户复测「校验没实现」的一部分）。
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ListView.builder(
            key: const ValueKey<String>('tt-rows'),
            shrinkWrap: true,
            itemCount: details.length,
            itemBuilder: (BuildContext context, int i) {
              final TimeDetail d = details[i];
              return Row(
                key: ValueKey<String>('tt-row-${d.section}'),
                children: <Widget>[
                  Expanded(child: Text('${d.section}')),
                  Expanded(
                    child: CourseTimeCell(
                      section: d.section,
                      tag: 'start',
                      minutes: d.startMinutes,
                      showError: _bad(d.section, 'start'),
                      revision: revision,
                      onSubmitted: (int m) => onStart(d.section, m),
                      onInvalid: (String raw) =>
                          onInvalid(d.section, 'start', raw),
                    ),
                  ),
                  Expanded(
                    child: CourseTimeCell(
                      section: d.section,
                      tag: 'end',
                      minutes: d.endMinutes,
                      showError: _bad(d.section, 'end'),
                      revision: revision,
                      onSubmitted: (int m) => onEnd(d.section, m),
                      onInvalid: (String raw) =>
                          onInvalid(d.section, 'end', raw),
                    ),
                  ),
                  IconButton(
                    key: ValueKey<String>('tt-del-${d.section}'),
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: details.isEmpty ? null : () => onDelete(d),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
