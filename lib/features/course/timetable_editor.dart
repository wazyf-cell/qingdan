import 'package:flutter/material.dart';

import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/theme/app_dimens.dart';

import 'timetable_generate_form.dart';
import 'timetable_editor_footer.dart';
import 'timetable_rows.dart';

/// 作息时间表编辑面板（§2.3）：预设 → 参数 → 生成预览 → 逐节微调 → 保存。
///
/// 三条设计稿要求都落在这里：**用户确认前不落库**；改某节开始时间后该节之后
/// 整体顺移、之前不动；删除中间一节后节次号补位重排。
///
/// 非法输入的账本在 [TimeCellRecords]（`timetable_rows.dart`）：**记录与染红分家**
/// ——每次 `onChanged` 都如实记账（点保存一定拦得住），但只有敲满 `HH:MM` 的
/// 5 个字符仍解析不过、或点过保存才上色（逐键飘红会让行高与按钮行跟着抖）。
class TimetableEditPanel extends StatefulWidget {
  const TimetableEditPanel({
    super.key,
    required this.initialDetails,
    this.onSave,
    this.isMobile = false,
    this.showSaveButton = true,
    this.onDirty,
    this.onSaveHandle,
  });

  final List<TimeDetail> initialDetails;
  final void Function(List<TimeDetail> draft)? onSave;
  final bool isMobile;

  /// 整页形态把保存放到 AppBar，面板自己不再渲染底部按钮。
  final bool showSaveButton;

  /// 任意节次变化时回调：整页用它决定返回是否要拦。
  final VoidCallback? onDirty;

  /// 整页形态取走「提交」动作，AppBar 的保存按钮调用它。
  final ValueChanged<VoidCallback>? onSaveHandle;

  @override
  State<TimetableEditPanel> createState() => _TimetableEditPanelState();
}

class _TimetableEditPanelState extends State<TimetableEditPanel> {
  late List<TimeDetail> _draft;
  String? _error;
  int _breakMinutes = 10;

  /// 上一次**从库里拿到的那套**节次（不是用户正在敲的草稿）。
  /// 比内容用它、不比 identity：`model.load()` 每轮都产一个新列表，按 identity
  /// 重挂会把用户敲了一半的草稿抹掉——那是另一种「点了没反应」。
  List<TimeDetail> _seeded = const <TimeDetail>[];

  /// 时间格账本（键 `'$section-$tag'`）：记「哪一格当前的文本解析不过」。
  final TimeCellRecords _rec = TimeCellRecords();

  /// 递增它逼所有时间格把文本回读成草稿真值（面板**拒绝**一次改动时用）。
  int _resync = 0;

  @override
  void initState() {
    super.initState();
    _draft = <TimeDetail>[...widget.initialDetails];
    _seeded = <TimeDetail>[...widget.initialDetails];
    _auditLoaded();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSaveHandle?.call(_save);
    });
  }

  @override
  void didUpdateWidget(covariant TimetableEditPanel old) {
    super.didUpdateWidget(old);
    // 父级换了一套节次（切学期、套用模板、建完学期后重读）→ 草稿必须跟着换，
    // 否则卡片继续画着**上一张表**的时刻，界面说的就不是真话。
    // 比的是**内容**不是 identity：`model.load()` 每轮都产一个新列表对象，
    // 按 identity 重挂会抹掉用户敲了一半的草稿（`sameDetailsContent` 的理由）。
    if (sameDetailsContent(_seeded, widget.initialDetails)) return;
    setState(() {
      _draft = <TimeDetail>[...widget.initialDetails];
      _seeded = <TimeDetail>[...widget.initialDetails];
      _error = null;
      _rec.clearAll(); // 整张表都换了，旧账找不到新格子上，留着就是幽灵红框。
      _resync++;
    });
  }

  /// 载入既有数据时体检：越界格子（历史脏数据）标红并要求改正再保存。
  /// **不自动 clamp**——静默改数据比报错更糟。
  void _auditLoaded() {
    final String? first = firstOutOfRange(_draft);
    if (first == null) return;
    for (final TimeDetail d in _draft) {
      if (minuteOutOfRange(d.startMinutes)) {
        _rec.markLoaded(d.section, 'start', formatMinutes(d.startMinutes));
      }
      if (minuteOutOfRange(d.endMinutes)) {
        _rec.markLoaded(d.section, 'end', formatMinutes(d.endMinutes));
      }
    }
    _error = '$first（历史数据，请改正后再保存）';
  }

  /// 草稿换一遍：顺带清掉「那一节已被真值覆盖回去」的账（幽灵红框就是这么来的）。
  void _applyDraft(List<TimeDetail> next) {
    widget.onDirty?.call();
    final Map<int, String> before = snapshotOf(_draft);
    setState(() {
      _draft = next;
      _error = null;
      _rec.dropChanged(before, _draft);
    });
  }

  void _generate(GenerateParams p) {
    widget.onDirty?.call();
    _breakMinutes = p.breakMinutes;
    final List<TimeDetail> next = generateTimeDetails(
      timetableId: '',
      firstStartMinutes: p.firstStartMinutes,
      lessonMinutes: p.lessonMinutes,
      breakMinutes: p.breakMinutes,
      sectionCount: p.sectionCount,
      lunchAfterSection:
          p.lunchAfterSection == 0 ? null : p.lunchAfterSection,
      lunchMinutes: p.lunchMinutes,
    );
    // 预览也要过闸：节数填 999、第一节开始 23:50 都能生成一张越界的表。
    final String? err = validateTimeDetails(next);
    if (err != null) {
      setState(() => _error = '生成结果不合法：$err');
      return;
    }
    setState(() {
      _error = null;
      _rec.clearAll(); // 整张表都是新的，旧账找不到新格子上，留着就是幽灵。
      _draft = next;
    });
  }

  void _addSection() {
    if (_draft.isEmpty) return;
    if (_draft.length >= kMaxSectionsPerDay) {
      setState(() => _error = '一天最多 $kMaxSectionsPerDay 节');
      return;
    }
    final TimeDetail last = _draft.last;
    final int length = last.endMinutes - last.startMinutes;
    final TimeDetail added = TimeDetail(
      id: '',
      timetableId: '',
      section: last.section + 1,
      startMinutes: last.endMinutes + _breakMinutes,
      endMinutes: last.endMinutes + _breakMinutes + length,
    );
    if (minuteOutOfRange(added.endMinutes)) {
      setState(() => _error = '再加一节会超过 23:59，请先缩短前面的节次');
      return;
    }
    _applyDraft(<TimeDetail>[..._draft, added]);
  }

  /// 删中间一节后节次号补位重排（节次本质是序号，不是 ID）。
  void _deleteSection(TimeDetail target) => _applyDraft(renumber(<TimeDetail>[
        ..._draft.where((TimeDetail d) => d.section != target.section),
      ]));

  /// 时间格上报「当前文本解析不过」：先记账，只有该上色时才动红框与错误行。
  /// 每次上报都重建：账变了红态就得跟着变，少一次 setState 会留一个下不来的红框。
  void _onCellUnparsed(int section, String tag, String raw) {
    widget.onDirty?.call();
    final String? message = _rec.mark(section, tag, raw);
    setState(() {
      if (message != null) _error = message.isEmpty ? null : message;
    });
  }

  /// 拒绝这次改动：说清原因、清掉这一格的账，并让文本回读草稿真值
  /// （不回读就退回「框里是新值、草稿是旧值」的静默丢弃，正是 A1 的病根）。
  void _reject(String key, String message) {
    setState(() {
      _error = message;
      _rec.clear(key);
      _resync++;
    });
  }

  /// 改某节开始时间 → 该节之后整体顺移同样分钟数（§2.3 最常见诉求）。
  /// 平移后必须体检：越界就整次拒绝，否则后续节能被推到 `24:35` 存进库。
  void _changeStart(int section, int minutes) {
    final TimeDetail? target = rowOf(_draft, section);
    if (target == null) return;
    final String key = timeCellKey(section, 'start');
    final int delta = minutes - target.startMinutes;
    // 值没变（键盘确认键会把同一个值再报一次）：只销这一格的账，不再顺移一遍。
    if (delta == 0) {
      if (_rec.clear(key)) {
        setState(() => _error = _rec.isEmpty ? null : _error);
      }
      return;
    }
    final int length = target.endMinutes - target.startMinutes;
    final List<TimeDetail> next = shiftSectionsAfter(
      <TimeDetail>[
        for (final TimeDetail d in _draft)
          d.section == section
              ? d.copyWith(
                  startMinutes: minutes, endMinutes: minutes + length)
              : d,
      ],
      section,
      delta,
    );
    final String? over = firstOutOfRange(next);
    if (over != null) {
      _reject(key, '顺移后 $over，请先缩短前面的节次或减少节数');
      return;
    }
    _applyDraft(next);
  }

  void _changeEnd(int section, int minutes) {
    final TimeDetail? target = rowOf(_draft, section);
    if (target == null) return;
    final String key = timeCellKey(section, 'end');
    if (minutes <= target.startMinutes) {
      _reject(key, '第 $section 节结束时间必须晚于开始时间');
      return;
    }
    _applyDraft(<TimeDetail>[
      for (final TimeDetail d in _draft)
        d.section == section ? d.copyWith(endMinutes: minutes) : d,
    ]);
  }

  void _save() {
    if (!_rec.isEmpty) {
      setState(() {
        // 点保存 = 把只记了账、还没长成完整形状的格子一并染红：拦住要有看得见的原因。
        _rec.revealAll();
        _error = '还有 ${_rec.count} 处时间不合法：「${_rec.firstRaw}」，改成 HH:MM 后再保存';
      });
      return;
    }
    final String? invalid = validateTimeDetails(_draft);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() => _error = null);
    widget.onSave?.call(_draft);
  }

  bool get _canAdd => _draft.isNotEmpty && _draft.length < kMaxSectionsPerDay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TimetableGenerateForm(
          onGenerate: _generate,
          initialFirstStart:
              _draft.isNotEmpty ? _draft.first.startMinutes : 480,
        ),
        const SizedBox(height: AppDimens.s8),
        TimetableRows(
          details: _draft,
          shownKeys: _rec.shownKeys,
          revision: _resync,
          onStart: _changeStart,
          onEnd: _changeEnd,
          onInvalid: _onCellUnparsed,
          onDelete: _deleteSection,
        ),
        // 红字紧贴底部按钮行上方：与用户刚点的那一下同屏，不需要滚动。
        TimetableEditorFooter(
          error: _error,
          canAdd: _canAdd,
          canSave: _draft.isNotEmpty,
          showSaveButton: widget.showSaveButton,
          onAdd: _addSection,
          onSave: _save,
        ),
      ],
    );
  }
}
