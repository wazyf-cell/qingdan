// 导入向导的三种类型：步骤枚举、行处置枚举、校正行包装。
//
// 从 `import_wizard_model.dart` 拆出来是因为模型加上批量操作后会过 300 行红线；
// 这几件事也被校正界面的行组件与零件文件引用，放这里避免互相绕道依赖模型文件。

import 'package:qingdan/import/course/course_row_parser.dart';

/// 向导的五个步骤（序号与界面顶部指示器一致）。
enum WizardStep { file, mapping, setup, correct, confirm }

/// 校正行的处置状态（§4.3 规则 6：忽略与删除语义不同）。
enum RowDisposition { keep, ignored, deleted }

/// 一行解析结果 + 用户对它做的处置。解析结果本身不改动，便于「撤销忽略」。
class CorrectionRow {
  CorrectionRow(this.parsed, {this.disposition = RowDisposition.keep});

  final ParsedCourseRow parsed;
  RowDisposition disposition;

  bool get kept => disposition == RowDisposition.keep;

  /// 落库闸门只看未处理的 ✗ 行（§3.1）。
  bool get blocksImport => parsed.isError && kept;
}

