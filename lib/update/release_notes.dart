/// 应用内更新说明：每个版本「改了什么」的短文案，随包发布。
///
/// 为什么自带一份而不是从 GitHub 拉：升级后首次启动时用户多半还没联网、也未必
/// 愿意为一个说明框等一次请求；GitHub 的 `body` 是发布者随手写的长文（可能带
/// Markdown、表格），而这里只需要几句能一眼看完的话。检测更新弹层里仍然优先显示
/// GitHub 的 `body`（见 `update_rows.dart`），这两份来源各管一个场景。
///
/// 纯文本、一行一条、行首 `· `：项目没有 Markdown 渲染器，加了 `**加粗**` 之类
/// 只会把星号原样显示给用户。
library;

/// 键是去掉 `v` 前缀与 `+build` 的版本号，与 `kAppVersion` 同一形状。
const Map<String, String> kReleaseNotes = <String, String>{
  '1.0.3': '· 学习通刷新变快：作业一个来回就上屏，考试随后补上；课堂活动改成切到该页签才拉\n'
      '· 面板头部改成 22:20 更新 这样的绝对时间，跨天才带日期；挤不下时整句不显示，不再出现半个省略号\n'
      '· 刷新失败不再静默变成空列表：保留上次结果，头部一行红字说明原因\n'
      '· 新增「本次更新内容」：升级后首次启动弹一次，只在版本号变化时弹\n'
      '· 检测更新弹层里会显示这一版的更新说明',
  '1.0.2': '· 设置 → 通用 下多了两个控件：检测更新（查 GitHub Releases 有没有新版）'
      '与 GitHub 仓库（打开发布页和源码）\n'
      '· 本应用不会自己下载、也不会自己安装 APK：换签名安装必须先卸载，而卸载会清空'
      '本机数据库，所以装新版由你到发布页自己选包',
};

/// 取某个版本的更新说明；没有（或只有空白）就返回 null。
///
/// 空白也算「没有」：`kReleaseNotes['9.9.9'] = ''` 与漏写这条在用户眼里是同一件事，
/// 界面上都该退到「本次更新没有附说明」，而不是弹一个空框。
String? releaseNotesFor(String version) {
  // 版本号可能带 `v` 前缀或 `+build`（pubspec 的 `version:` 就是 `1.0.2+3` 这种形状）。
  // 先归一化再查表，否则表里写着 1.0.3、传进来 1.0.3+7 就永远查不到。
  final String key = version
      .trim()
      .replaceFirst(RegExp(r'^v', caseSensitive: false), '')
      .split('+')
      .first;
  final String? notes = kReleaseNotes[key];
  return (notes == null || notes.trim().isEmpty) ? null : notes;
}
