import 'package:flutter/material.dart';

import 'package:qingdan/application/semester_use_case.dart';
import 'package:qingdan/domain/semester.dart';

import 'semester_editor.dart';

/// 「编辑学期」对话框（从 `semester_sheet.dart` 按行数红线搬出，行为不变）。
///
/// 三个字段一次写完：拆三次写各自拿同一份旧快照整行写回，后一次盖掉前一次
/// （2026-10-18 用户报的「点了没反应」）。
Future<bool?> showSemesterEditDialog(
  BuildContext context, {
  required Semester semester,
  required SemesterUseCase semesters,
}) =>
    showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('编辑学期「${semester.name}」'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: SemesterEditPanel(
              initial: semester,
              onSave: ({
                required String name,
                required DateTime firstWeekDate,
                required int totalWeeks,
              }) async {
                await semesters.saveSemester(semester,
                    name: name,
                    firstWeekDate: firstWeekDate,
                    totalWeeks: totalWeeks);
                if (ctx.mounted) Navigator.of(ctx).pop(true);
              },
            ),
          ),
        ),
      ),
    );
