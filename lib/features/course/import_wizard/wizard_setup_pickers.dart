// 导入向导步 3 的两条下拉（M6-D §7.5）：
//   * 「导入到学期」key `adopt-semester` —— 从「沿用现有学期」变来的学期选择，
//     选定后步 4 解析、步 5 落库、扩周数全部跟着走；
//   * 「作息」key `adopt-timetable` —— 沿用该学期现有作息 / 换成某个模板两选。
//
// 从 `wizard_step_setup.dart` 拆出（300 行红线），纯展示壳：状态与写库动作
// 都留在步 3 的 State 里，这里只回调。

import 'package:flutter/material.dart';

import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';

/// `adopt-timetable` 下拉的「沿用现有作息」哨兵值（其余 item 都是模板 id）。
const String kWizardKeepTimetable = 'keep';

class WizardSetupPickers extends StatelessWidget {
  const WizardSetupPickers({
    super.key,
    required this.semesters,
    required this.selected,
    required this.templates,
    required this.timetableChoice,
    required this.onPickSemester,
    required this.onPickTimetable,
  });

  final List<Semester> semesters;
  final Semester? selected;
  final List<TimeTable> templates;
  final String timetableChoice;
  final ValueChanged<Semester?> onPickSemester;
  final ValueChanged<String?> onPickTimetable;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: 84,
                child: Text('导入到学期',
                    style: TextStyle(fontSize: 13, color: colors.textSecondary)),
              ),
              Expanded(
                child: DropdownButton<Semester>(
                  key: const ValueKey<String>('adopt-semester'),
                  isExpanded: true,
                  value: semesters.any((Semester s) => s.id == selected?.id)
                      ? selected
                      : null,
                  hint: const Text('（还没有学期——下面先建一个）'),
                  items: <DropdownMenuItem<Semester>>[
                    for (final Semester s in semesters)
                      DropdownMenuItem<Semester>(
                        value: s,
                        child: Text(
                            '${s.name}${s.isActive ? '（当前）' : ''} · ${s.totalWeeks} 周',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: onPickSemester,
                ),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              SizedBox(
                width: 84,
                child: Text('作息',
                    style: TextStyle(fontSize: 13, color: colors.textSecondary)),
              ),
              Expanded(
                child: DropdownButton<String>(
                  key: const ValueKey<String>('adopt-timetable'),
                  isExpanded: true,
                  value: timetableChoice,
                  items: <DropdownMenuItem<String>>[
                    const DropdownMenuItem<String>(
                        value: kWizardKeepTimetable,
                        child: Text('沿用该学期现有作息')),
                    for (final TimeTable t in templates)
                      DropdownMenuItem<String>(
                        value: t.id,
                        child: Text(
                            t.isBuiltin ? '${t.name}（内置）' : t.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: onPickTimetable,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
