/// 隐藏项的展示元数据（M6B §B6）。
///
/// 隐藏集原本只在 prefs 里存一串 `'$courseId|$id'`，隐藏列表页没法渲染，
/// 所以隐藏时顺手把「课程名 / 标题 / 截止时间 / 隐藏时刻」存进
/// `chaoxing.hidden.meta`（JSON 对象，键 = 条目 key）。
///
/// **不进业务库、不参与同步**（学习通域 2026-10-17 的定案：外部只读快照）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:qingdan/import/chaoxing/chaoxing_models.dart';

class ChaoxingHiddenEntry {
  const ChaoxingHiddenEntry({
    required this.key,
    required this.courseName,
    required this.title,
    required this.hiddenAtMs,
    this.dueMs,
    this.dead = false,
  });

  /// = `ChaoxingTask.key`（`'$courseId|$id'`），恢复与去重都按它。
  final String key;
  final String courseName;
  final String title;

  /// 隐藏那一刻的截止时间（毫秒）；服务端可能改截止，刷新后会跟着更新。
  final int? dueMs;
  final int hiddenAtMs;

  /// 最近一次刷新里这条**没有再出现**（可能已过期或被服务端删除）。
  /// 只标记不自动删——留不留由用户决定。
  final bool dead;

  DateTime? get dueAt =>
      dueMs == null ? null : DateTime.fromMillisecondsSinceEpoch(dueMs!);

  ChaoxingHiddenEntry copyWith({int? dueMs, bool? dead}) =>
      ChaoxingHiddenEntry(
        key: key,
        courseName: courseName,
        title: title,
        hiddenAtMs: hiddenAtMs,
        dueMs: dueMs ?? this.dueMs,
        dead: dead ?? this.dead,
      );

  static ChaoxingHiddenEntry of(ChaoxingTask t, DateTime now) =>
      ChaoxingHiddenEntry(
        key: t.key,
        courseName: t.courseName,
        title: t.title,
        dueMs: t.dueAt?.millisecondsSinceEpoch,
        hiddenAtMs: now.millisecondsSinceEpoch,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'courseName': courseName,
        'title': title,
        'dueMs': dueMs,
        'hiddenAtMs': hiddenAtMs,
        'dead': dead,
      };

  /// 解不开的那一项直接丢掉（损坏的 prefs 不该让整个隐藏页崩），
  /// 整体解不开时 [decode] 返回空表。
  static ChaoxingHiddenEntry? fromJson(String key, Map<String, Object?> json) {
    final Object? title = json['title'];
    final Object? at = json['hiddenAtMs'];
    if (title is! String || title.isEmpty || at is! num) return null;
    return ChaoxingHiddenEntry(
      key: key,
      courseName: json['courseName'] is String ? json['courseName']! as String : '',
      title: title,
      dueMs: json['dueMs'] is num ? (json['dueMs']! as num).toInt() : null,
      hiddenAtMs: at.toInt(),
      dead: json['dead'] == true,
    );
  }

  /// JSON 对象（键 = 条目 key），与 `开发文档/02-方案设计/待执行-M6总纲.md` §五
  /// 登记的默认值 `{}` 同形；数组形态解不出来按空表处理。
  static List<ChaoxingHiddenEntry> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const <ChaoxingHiddenEntry>[];
    Object? parsed;
    try {
      parsed = jsonDecode(raw);
    } on FormatException catch (e) {
      // 只打印异常类型说明，绝不把 prefs 原文写进日志（里面可能有用户内容）。
      debugPrint('chaoxing.hidden.meta 解析失败，按空处理：${e.runtimeType}');
      return const <ChaoxingHiddenEntry>[];
    }
    if (parsed is! Map) {
      debugPrint('chaoxing.hidden.meta 形态不是对象，按空处理');
      return const <ChaoxingHiddenEntry>[];
    }
    final List<ChaoxingHiddenEntry> out = <ChaoxingHiddenEntry>[];
    for (final MapEntry<Object?, Object?> e in parsed.entries) {
      if (e.key is! String || e.value is! Map) continue;
      final ChaoxingHiddenEntry? item = ChaoxingHiddenEntry.fromJson(
          e.key! as String, (e.value! as Map<Object?, Object?>).cast());
      if (item != null) out.add(item);
    }
    return out;
  }

  static String encode(List<ChaoxingHiddenEntry> entries) =>
      jsonEncode(<String, Object?>{
        for (final ChaoxingHiddenEntry e in entries) e.key: e.toJson(),
      });
}

/// 刷新成功后对齐隐藏元数据：还存在的条目把课程名/标题/截止更新成最新值
/// （截止时间可能被老师改），本次刷新中不再出现的标 `dead`（**不删**，
/// 让隐藏列表页给用户自己决定）。纯函数、无 IO，从 `ChaoxingModel` 抽出来
/// 是为了让模型留在 300 行红线内（职责也本来就是「隐藏项元数据」这一域）。
List<ChaoxingHiddenEntry> syncHiddenMetaWithTasks(
  List<ChaoxingHiddenEntry> entries,
  List<ChaoxingTask> tasks,
) {
  if (entries.isEmpty) return entries;
  final Map<String, ChaoxingTask> byKey = <String, ChaoxingTask>{
    for (final ChaoxingTask t in tasks) t.key: t,
  };
  return entries.map((ChaoxingHiddenEntry e) {
    final ChaoxingTask? t = byKey[e.key];
    if (t == null) return e.copyWith(dead: true);
    return ChaoxingHiddenEntry(
      key: e.key,
      courseName: t.courseName,
      title: t.title,
      dueMs: t.dueAt?.millisecondsSinceEpoch,
      hiddenAtMs: e.hiddenAtMs,
      dead: false,
    );
  }).toList();
}
