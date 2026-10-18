import 'package:flutter/material.dart';

/// 字号层级 token（§1.3）。
///
/// 行高以 `height` 比例表达（21/14=1.5 等），随字号缩放。
abstract final class AppTypography {
  /// 页标题 20sp / w600 / 28dp —— 列表区顶部清单名。
  static const TextStyle pageTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 28 / 20,
  );

  /// 面板标题 16sp / w600 / 24dp —— 详情面板任务标题。
  static const TextStyle panelTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 24 / 16,
  );

  /// 正文 14sp / w400 / 21dp —— 任务标题、输入框、备注正文。
  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 21 / 14,
  );

  /// 元信息 12sp / w400 / 16dp —— 到期时间、标签、子任务进度。
  static const TextStyle meta = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 16 / 12,
  );

  /// 分组头 12sp / w600 / 16dp，字距 +0.5。
  static const TextStyle groupHeader = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 16 / 12,
    letterSpacing: 0.5,
  );

  /// 计数 11sp / w500 / 14dp —— 侧栏清单右侧数字。
  static const TextStyle counter = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 14 / 11,
  );
}
