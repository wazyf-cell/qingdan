// 选课表文件的平台层出口（§五 双端差异表：文件选择是**唯一不能复用**的一块）。
//
// 两端都走 `file_selector`（2026-10-10 定案 4，对设计稿「移动端 = file_picker」
// 的有意偏差）：桌面开系统对话框，Android 走 SAF。测试里注入假实现，
// 不依赖真实文件对话框。

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// 选定文件的名称与字节。取消返回 null。
typedef ScheduleFileLoader = Future<({String name, Uint8List bytes})?> Function();

/// 真机用的实现：系统对话框 + 读字节。
///
/// 两组过滤器：`.wakeup_schedule` 是自定义扩展名，Android 的 SAF 按 MIME 过滤会
/// 把它藏起来（选了「看不见文件」也照样是导入失败），所以再给一组「所有文件」兜底；
/// 桌面端会显示成下拉里两个可选项。
Future<({String name, Uint8List bytes})?> pickScheduleFile() async {
  const List<XTypeGroup> groups = <XTypeGroup>[
    XTypeGroup(
      label: '课表文件（xlsx / csv / WakeUp 导出）',
      extensions: <String>['xlsx', 'csv', 'wakeup_schedule'],
    ),
    XTypeGroup(label: '所有文件', mimeTypes: <String>['*/*']),
  ];
  final XFile? picked = await openFile(acceptedTypeGroups: groups);
  if (picked == null) return null;
  return (name: picked.name, bytes: await picked.readAsBytes());
}
