/// 新建学期表单（§7.2）的作息模板候选：一行候选 = 一个时间表模板。
///
/// 从 `semester_create_sheet.dart` **原样搬出**（该文件搬前 307 行、破 AGENTS.md
/// 的 300 行红线；这里只是搬家，取数顺序与回落规则一字未改）：候选来自
/// `templates()`，内置排第一并标「默认」，节数逐个查真值。
library;

import 'package:qingdan/application/timetable_use_case.dart';
import 'package:qingdan/domain/default_timetable.dart';
import 'package:qingdan/domain/time_table.dart';

/// 一行模板候选：[name] 给回执（{模板名}），[label] 给下拉展示，[count] 是节数。
typedef SemesterTemplateChoice = ({String id, String name, String label, int count});

SemesterTemplateChoice builtinTemplateChoice() => (
      id: kBuiltInTimetableId,
      name: kBuiltInTimetableName,
      label: '$kBuiltInTimetableName（默认）',
      count: kBuiltInTimeDetails.length,
    );

/// 候选 = `templates()`（内置排第一、标「默认」）。
///
/// 装配缺失（[useCase] 为 null，没注册 provider）时退化成只有内置模板一项——
/// 内置内容在领域层是常量，不依赖库。
Future<List<SemesterTemplateChoice>> readTemplateChoices(
    TimetableUseCase? useCase) async {
  if (useCase == null) return <SemesterTemplateChoice>[builtinTemplateChoice()];
  final List<SemesterTemplateChoice> out = <SemesterTemplateChoice>[];
  for (final TimeTable t in await useCase.templates()) {
    // 节数逐个查：回执里的 {N} 必须是复制进学期的那个真值，不能拿文案凑。
    final int n = (await useCase.templateDetails(t.id)).length;
    out.add((
      id: t.id,
      name: t.name,
      label: t.isBuiltin ? '${t.name}（默认）' : '${t.name}（$n 节）',
      count: n,
    ));
  }
  return out.isEmpty ? <SemesterTemplateChoice>[builtinTemplateChoice()] : out;
}
