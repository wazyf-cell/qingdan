// 学期卡与作息卡：`course_setup.dart`（设置弹层）与导入向导步 3 共用同一对卡，
// 差别只在「保存之后把结果同步给谁」——那部分留在调用方，卡片本身只发回调。

import 'package:flutter/material.dart';

import 'package:qingdan/domain/semester.dart';
import 'package:qingdan/domain/time_table.dart';
import 'package:qingdan/theme/app_dimens.dart';

import 'semester_editor.dart';
import 'timetable_editor.dart';

class SemesterCard extends StatelessWidget {
  const SemesterCard({
    super.key,
    required this.semester,
    required this.onSave,
  });

  final Semester? semester;
  final void Function(
      {required String name,
      required DateTime firstWeekDate,
      required int totalWeeks}) onSave;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.s12),
        child: SemesterEditPanel(initial: semester, onSave: onSave),
      ),
    );
  }
}

class TimetableCard extends StatelessWidget {
  const TimetableCard({
    super.key,
    required this.details,
    required this.isMobile,
    required this.onSave,
  });

  final List<TimeDetail> details;
  final bool isMobile;
  final void Function(List<TimeDetail> draft) onSave;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.s12),
        child: TimetableEditPanel(
          initialDetails: details,
          isMobile: isMobile,
          onSave: onSave,
        ),
      ),
    );
  }
}
