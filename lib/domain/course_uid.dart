import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'week_rule.dart';

/// 课名归一化（§3.5 的四步，**每一步都必须有测试**）：
/// trim → 去全部空白 → 全角转半角 → 转小写。
///
/// 实现上先做全角转半角再剥空白：全角空格 U+3000 只有先转成半角空格，
/// 才会被 `\s+` 去掉（Dart 的 `\s` 不保证覆盖全角空格）。四步集合不变。
///
/// 归一不稳定的后果是同一门课在两台设备上算出不同 UID，同步后课程重复。
String normalizeCourseName(String name) {
  final String halfWidth = toHalfWidth(name);
  return halfWidth.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();
}

/// 课程去重键（§3.5）：
///
/// ```text
/// uid = sha1( normalize(name) + "|" + weekday + "|" + startSection + "|"
///           + endSection + "|" + sortedJoin(weeks, ",") )
/// ```
///
/// **周次必须参与哈希**：样本第 2、3 行（线代与大英同槽不同周次）若不含周次
/// 会被错误合并成一条（§3.5）。[weeks] 在 [Course] 构造时已排序去重，这里再
/// 归一一次以防直接调用者传入乱序。绝不使用对象 `hashCode`（§6.3.3）。
String courseUidOf({
  required String name,
  required int weekday,
  required int startSection,
  required int endSection,
  required List<int> weeks,
}) {
  final List<int> sorted = <int>{...weeks}.toList()..sort();
  final String key = <String>[
    normalizeCourseName(name),
    '$weekday',
    '$startSection',
    '$endSection',
    sorted.join(','),
  ].join('|');
  return sha1.convert(utf8.encode(key)).toString();
}

/// 调色板大小（§1.1:73 按课名 hash 取 8 色之一）。
///
/// 那句「**不做**用户自定义配色」已过期于 M6-D §十：选择器在
/// `features/course/course_color_picker.dart`（`field-color-<i>` /
/// `field-color-auto`），选中的档位存进可空列 `courses.color_index`（迁移 v6）。
/// [courseColorIndex] 没有被废弃——它就是 `colorIndex == null`（「自动」那一档）
/// 时的回落，仍然是跨设备稳定的按课名派生配色。
const int kCoursePaletteSize = 8;

/// 课程配色索引：**跨设备稳定**（同一个课名在两台机器上必须同色）。
///
/// 用 sha1 的前 4 字节取模，而不是 `String.hashCode`——后者的实现不保证跨进程
/// 稳定（§6.3.3 明确禁止）。
int courseColorIndex(String name) {
  final List<int> digest =
      sha1.convert(utf8.encode(normalizeCourseName(name))).bytes;
  final int folded = ((digest[0] << 24) | (digest[1] << 16) |
          (digest[2] << 8) | digest[3]) &
      0x7FFFFFFF;
  return folded % kCoursePaletteSize;
}
