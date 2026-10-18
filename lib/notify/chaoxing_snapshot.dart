// ignore_for_file: prefer_initializing_formals — 命名参数不能以 _ 开头
/// 学习通提醒快照（M6-C4）：SharedPreferences 里的一份 JSON 数组，**不进 SQLite、
/// 不参与同步**。这不是 2026-10-17「学习通域不落库、不同步」定案的例外，别误读：
/// prefs 不是业务库，同步引擎（op-log + 字段级 LWW + 三路合并）看不见它，另一台设备
/// 也读不到，所以「这台设备排了哪些提醒」这类本地状态不会被同步出去；之所以要落盘，
/// 是因为提醒必须活过「应用被系统杀掉」，而内存数据活不过这一次（用户裁决 Q24）。
/// 凭据不在此处——cookie 只进系统凭据库，本文件没有任何凭据字段。
/// `ChaoxingSnapshotItem` 定义在 `reminder_plan.dart`（那边要保持纯 Dart），这里
/// re-export，写入方只 import 本文件即可。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qingdan/notify/reminder_plan.dart' show ChaoxingSnapshotItem;

export 'package:qingdan/notify/reminder_plan.dart' show ChaoxingSnapshotItem;

/// prefs key，逐字照抄 `待执行-M6总纲.md` §五。
const String kChaoxingSnapshotKey = 'chaoxing.notify.snapshot';

/// 上限：防 prefs 无限膨胀（一次真机抓取也就几十条，300 是十倍余量）。
const int kChaoxingSnapshotMax = 300;

class ChaoxingSnapshotStore {
  ChaoxingSnapshotStore({SharedPreferences? prefs}) : _prefs = prefs;
  final SharedPreferences? _prefs;

  /// 写入时机：`ChaoxingModel.refresh()` 成功后，把**当前会被排通知的那些项**
  /// （未隐藏、未完成、未过期、有 dueAt）写进来；筛选由调用方做完，这里只管排序
  /// 与截断。空列表也照写（`[]`），好让「读回来是空」有唯一含义。
  Future<void> writeSnapshot(List<ChaoxingSnapshotItem> items) async {
    final SharedPreferences p = await _instance();
    final List<Object?> encoded =
        _capped(items).map(_encode).toList(growable: false);
    await p.setString(kChaoxingSnapshotKey, jsonEncode(encoded));
  }

  /// 读回来。JSON 损坏 → 空表 + debugPrint，**不抛**（提醒是增强功能，
  /// 一块坏数据不能把启动路径炸了）；单条字段坏了只丢那一条。
  Future<List<ChaoxingSnapshotItem>> readSnapshot() async {
    final String? raw = (await _instance()).getString(kChaoxingSnapshotKey);
    if (raw == null || raw.isEmpty) return const <ChaoxingSnapshotItem>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) {
        debugPrint('学习通提醒快照不是数组，按空处理');
        return const <ChaoxingSnapshotItem>[];
      }
      final List<ChaoxingSnapshotItem> items = <ChaoxingSnapshotItem>[];
      for (final Object? row in decoded) {
        if (row is! Map) continue;
        try {
          items.add(_decode(Map<String, Object?>.from(row)));
        } catch (e) {
          debugPrint('学习通提醒快照有条目损坏，跳过一条：${e.runtimeType}');
        }
      }
      return items;
    } catch (e) {
      // 只打类型：原文可能整段是用户数据。
      debugPrint('学习通提醒快照 JSON 解析失败，按空处理：${e.runtimeType}');
      return const <ChaoxingSnapshotItem>[];
    }
  }

  /// 清空时机：`logout()`（「退出并取消提醒」路径）与通知总开关关闭。
  Future<void> clearSnapshot() async =>
      (await _instance()).remove(kChaoxingSnapshotKey);

  Future<SharedPreferences> _instance() async =>
      _prefs ?? await SharedPreferences.getInstance();
}

Map<String, Object?> _encode(ChaoxingSnapshotItem i) => <String, Object?>{
      'key': i.key,
      'course': i.courseName,
      'title': i.title,
      'due': i.dueAt?.millisecondsSinceEpoch,
      'hidden': i.hidden,
      'done': i.serverDone,
      'ongoing': i.ongoing,
    };

ChaoxingSnapshotItem _decode(Map<String, Object?> m) => ChaoxingSnapshotItem(
      key: m['key']! as String,
      courseName: m['course'] as String? ?? '',
      title: m['title'] as String? ?? '',
      // 存绝对毫秒，读回**本地** DateTime：免打扰顺延看的是墙上钟点，而快照不参与
      // 同步，跨设备无所谓一致。用 isUtc: true 读会让顺延整体偏 8 小时。
      dueAt: m['due'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(m['due']! as int),
      hidden: m['hidden'] == true,
      serverDone: m['done'] == true,
      ongoing: m['ongoing'] != false,
    );

/// 按 dueAt 升序取前 [kChaoxingSnapshotMax]；无截止时间的排最后（截断先丢它们）。
List<ChaoxingSnapshotItem> _capped(List<ChaoxingSnapshotItem> items) {
  final List<ChaoxingSnapshotItem> sorted = List<ChaoxingSnapshotItem>.of(items)
    ..sort((ChaoxingSnapshotItem a, ChaoxingSnapshotItem b) {
      final DateTime? x = a.dueAt, y = b.dueAt;
      if (x != null && y != null) {
        final int byDue = x.compareTo(y);
        if (byDue != 0) return byDue;
      } else if (x != null) {
        return -1;
      } else if (y != null) {
        return 1;
      }
      // List.sort 不稳定，同刻/同为空时必须有确定次序，截断结果才能复现。
      return a.key.compareTo(b.key);
    });
  return sorted.length <= kChaoxingSnapshotMax
      ? sorted
      : sorted.sublist(0, kChaoxingSnapshotMax);
}
