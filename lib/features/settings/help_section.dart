/// 使用说明（M6-C6）：整页七节。
///
/// **每一句都对着代码核实过**：写已经实现的行为，不写计划中的功能，也不把
/// 「明确不做」的那几件写成有（点卡片跳超星、后台定时刷新、自建服务器都不存在）。
/// 提醒一节按 `待执行-M6C-设置与通知.md` §C2 的定案文案写——那一节与「数据与同步」
/// 「通知」两个设置页由同批交付，本批一起落地。
///
/// 两个入口都由设置侧接线：设置 → 关于 → 使用说明（C1）、首启引导框的
/// 「去看使用说明」（[pushHelpPage] 同一跳）。本文件**不 import settings_page.dart**，
/// 免得和「关于」节的跳转绕成循环。
library;

import 'package:flutter/material.dart';

import 'package:qingdan/theme/app_colors.dart';
import 'package:qingdan/theme/app_dimens.dart';
import 'package:qingdan/theme/app_typography.dart';

/// 一节：一个小标题 + 若干条说明。
class _Chapter {
  const _Chapter(this.title, this.lines);

  final String title;
  final List<String> lines;
}

const List<_Chapter> _chapters = <_Chapter>[
  _Chapter('四个页签', <String>[
    '清单：本地待办。顶部一行输入框快速建任务，下面四枚视图 chip（今天 / 最近 7 天 / 所有 / 已完成），右下角 ＋ 打开添加表单。',
    '学习通：登录超星后，把还没交的作业和课堂活动列在同一页里。它是外部只读快照，不并进你的本地清单。',
    '课表：按学期与作息表排出来的周视图，课程块可以导入，也可以手工加。',
    '设置：外观、同步、提醒这些开关都在这一页。手机上它是第四个页签；宽屏布局在侧栏底部。',
  ]),
  _Chapter('清单', <String>[
    '顶部输入框：写一行话就能建任务，回车保存、Shift+回车换行。日期认「今天 / 明天 / 后天 / 大后天 / 明早 / 今晚 / 明晚」「周X / 礼拜X / 下周X / 下下周X」「M月D日」「M/D」；时刻认「X点 / X点半 / 上午·下午·晚上·中午·凌晨X点」和「H:mm」。例：「明天下午3点 交周报」→ 明天 15:00。',
    '没写时刻时默认 09:00（明早按 08:00，今晚 / 明晚按 20:00）；「M月D日」「M/D」今年已经过了就顺延到明年。',
    '右下角 ＋：添加待办表单，能显式挑清单、优先级、开始日期与到期日期（两个日期都能再带时刻）。它和顶部输入框是两个入口、同一条写路径。',
    '页头右上三个图标：清单列表（半屏面板，首行「全部清单」= 所有清单的待办；每条清单右侧菜单能重命名 / 删除）、添加清单、回收站。',
    '视图 chip 只有一个选中位：停在某个清单上时四枚一律不亮——「这个清单 × 时间视图」不能同时为真，不给你假的选中态。',
    '「今天」页顶部出现「学习通有 N 条 24 小时内到期」时，点它切到学习通页签；学习通的条目不会混进本地任务行。',
    '回收站：删除先进这里，可以「清空回收站」，也会按阈值自动清（7 / 30 / 90 天或永不，默认 30 天，改在 设置 → 数据与同步）。自动清只发生在「应用启动时 + 应用活着期间每 30 分钟」的检查里，没有后台定时——应用被杀掉就不会替你检查。',
  ]),
  _Chapter('学习通', <String>[
    '登录：未登录时页中给「登录学习通」，点了在本应用里打开超星自己的登录页，账号密码或扫码都在那个页面里完成——本应用不碰你的密码，也没有任何服务器。登录成功后自动把会话导出、存进系统凭据库，并立刻拉一次待办；跳转没被自动识别到时，点右上「我登录好了」手动确认。',
    '会话过期时会自动再弹一次登录页；关闭登录页即视为本轮跳过，不会连续弹出第二次。',
    '刷新只有两处：① 每次打开应用后，第一次进学习通页自动拉一次；② 标题行的 ⟳ 按钮，随时可点。距上次拉取不到 15 分钟时，那次自动机会照样用掉但不重复发请求。没有后台定时刷新，也没有下拉刷新。',
    '找东西：右上「筛选」里有搜索（标题或课程）、按课程、仅看未完成、仅看可提交、排序。右上 ⋮ 里是重新登录 / 隐藏列表 / 退出登录。',
    '卡片手势：把卡片往左拖（从右往左滑），右侧露出「详情」和「隐藏」；长按卡片同样能隐藏；点已经滑开的卡片本体就收回。隐藏过的项在 ⋮ → 隐藏列表 里能逐条恢复、全部恢复，或清掉「这次刷新已经不再出现」的项。',
    '数据去向：待办只存在这台设备（内存 + 一份提醒用的本机快照），「不写进应用数据库、不参与设备间同步」；退出登录会清掉凭据。这样一台设备上的隐藏动作不会跑到另一台没登录超星的设备上。',
    '明确不做：点卡片不会跳转超星的作业页面，这里也改不了它的完成状态——交作业请回到超星完成。',
  ]),
  _Chapter('课表', <String>[
    '第一次用：没有学期时页中给「建学期」；已经有学期就点周视图右上的 ⚙ 打开「课表设置」整页。当前学期卡进「学期与作息」页；添加课程、导入 / 从教务抓取 / 导出、课表管理与时间表管理都在课表设置页。手机端这些管理都是整页，宽屏仍是居中对话框。',
    '「学期与作息」页：学期名称、开学第一周的日期、总周数直接改；下面列出每天的作息节次，可进「编辑作息」整页改，或从模板生成一套。',
    '手工加课点周视图右上的 ＋；点课程块能看时间换算、改或删。「课程没有回收站」，删了就找不回。',
    '整张表差一周时（显示的周比实际小或大）：点顶部「第 N 周 / 共 M 周」打开周次网格，点格子翻周，「长按那一周 = 把它设为本周」（改的是开学日期，整张表一起挪过来）。导入的课超出学期周数时，导入完成会自动把总周数扩上去。',
    '导入三条路：入口在「课表设置」页的「导入课表文件 / 从教务系统抓取」，课表管理页顶部也各有一条。三个来源是 ① .xlsx 或 .csv（CSV 认 UTF-8 与 GBK，可一键换编码重读；真实类型按文件内容判，改了后缀也认）；② WakeUp 课程表导出的 .wakeup_schedule 文件；③ 教务系统——只适配南昌航空大学强智教务：在打开页面里登录 → 培养管理 → 我的课表 → 学期课表信息 → 点右上角下载图标（悬停提示「抓当前页」）→ 回到五步向导，按「下一步」走完文件 / 映射 / 学期作息 / 校正，最后点「导入」。',
    '三条路进同一个五步向导：选文件 → 列映射 → 学期与作息 → 逐行校正 → 确认导入（界面上这五步的标签是 文件 / 映射 / 学期作息 / 校正 / 导入）。校正步会挡住解析失败的行（可以改也可以忽略，还能批量改周次 / 老师 / 地点），同一格重叠的课会给提示。重复导入能选合并 / 覆盖 / 仅新增，覆盖只动导入来的课，手工加的课不受影响。',
    '看课：周内容左右滑动切周，也可以用 ‹ › 与「今天」；手机上「周末」按钮展开或收起周六日。今天落在学期内时顶部有今日摘要条，点它翻到今天那一周；今天若是周六日而周末被收着，会顺带展开周末——否则该列不会显示。',
  ]),
  _Chapter('声明与边界', <String>[
    '课表数据来自教务系统或导入文件，可能因教务调整、学期变更而更新不及时；本应用里的课表仅作参考，不保证与学校系统实时一致。需要实时或最终信息，请以「蓝航APP」或学校教务系统为准。',
    '本应用只适配南昌航空大学强智教务的页面结构，未适配其他学校或其他教务系统。想用于自己学校，请 fork 本仓库或拉取源码自行改装解析器；作者不承诺代为适配。',
    '学习通待办是登录状态下现拉的只读快照，可能过期；作业与考试安排以超星页面为准。',
    '只从本应用的 GitHub Releases 下载 APK。不要安装来源不明、非本仓库发布的同名应用；签名不同无法覆盖安装，也可能带来安全风险。',
    '这是自用项目，没有服务器、没有账号体系，按现状提供，不承诺维护时限；使用与数据风险自担。有问题或建议可在 GitHub Issues 提，合适的会采用，但不保证全部实现。',
    '如果这个项目对你有帮助，欢迎到 GitHub 仓库点个 Star（https://github.com/wazyf-cell/qingdan）。',
    '卸载会清空本机数据库；换签名、换包名或重装前，先导出课表并完成同步。',
  ]),
  _Chapter('同步', <String>[
    '配置在 设置 → 数据与同步：启用同步、服务器地址、账号、应用密码，再加测试连接 / 保存 / 解除配置。',
    'WebDAV 是通用协议，其他兼容 WebDAV 的服务也可能可用；本应用主要按坚果云测试，建议优先使用坚果云。用坚果云时地址要带非空子路径，例如 https://dav.jianguoyun.com/dav/qingdan/，直接指根目录会失败。密码那一栏填的是「应用密码」，不是网站登录密码（坚果云：账户信息 → 安全 → 添加应用密码 生成）；填错时「测试连接」会把这句话直接告诉你。',
    '应用密码只写进系统凭据库（Android Keystore），不进配置文件、不进日志。',
    '什么时候同步：改动后防抖 2 秒发起一次，两次同步之间至少隔 60 秒；应用启动 3 秒后同步一次；此外每 30 分钟兜底轮询一次。失败按 1 → 2 → 4 → 8 → 15 分钟退避，401/403 不自动重试（要重新配置）。坚果云免费版 600 请求 / 30 分钟，超了就等窗口。',
    '状态点：手机写在顶栏右侧、宽屏写在侧栏底部，一共六态——「同步未配置」「上次同步 HH:mm」「同步中…」「同步失败 · 点击查看」「需要重新配置」「限流 · HH:mm 恢复」。点它开详情卡：上次成功时间、↑上传 ↓下载 合并 N、最近错误、本窗口请求数，还有「立即同步」。',
    '同步的是八类，按这个顺序落库（父实体先落，外键才不会报错）：学期、作息表、节次、课程、清单、任务、子任务、标签。任务与标签的关联不参与同步（每台设备自己的视图），学习通待办也不参与。同一条记录两边都改过时按字段比时间、各取更新的那个字段，不是整条覆盖。',
    '没有服务器：开了同步才把改动写进你自己配置的那个目录（本地文件夹或 WebDAV），没开就只在这台设备的本地库里。',
  ]),
  _Chapter('提醒', <String>[
    '在 设置 → 通知。第一次进这一页才向你请求系统通知权限；没给权限时页顶会写「系统通知权限未开启，提醒不会响」，但下面的开关可以先设好。',
    '清单提醒是两个独立开关：「到期前提前提醒」（默认开，提前 30 分钟，可选 5 / 15 / 30 / 60 / 120 分钟）与「到期时刻提醒」（默认开）。判据是任务的到期时间——「没设到期时间的任务不会提醒」。',
    '学习通截止提醒也是两个独立开关：「截止前 2 小时」与「截止前 30 分钟」（分钟数可调，默认 120 / 30）。已隐藏、服务端已完成、已过期、或没有截止时间的项不排提醒。',
    '免打扰默认 23:00–07:00，落在区间里的提醒「顺延到区间结束那一刻」（07:00）再响，不是丢弃；跨午夜的区间也算得对。总开关「启用提醒」关掉会取消已排的全部提醒。',
    '要知道的局限：提醒由本应用在打开时排入系统闹钟。应用被系统彻底杀死后，已排入的提醒仍会响；但新增或改动的待办要等应用下次打开才会重新排程。学习通的提醒取决于最近一次刷新的数据。',
    '提醒只在 Android 端生效。',
  ]),
];

/// 使用说明正文（可嵌在任意整页里；[showTitle] 同其他设置分节）。
class HelpSection extends StatelessWidget {
  const HelpSection({super.key, this.showTitle = true});

  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Column(
      key: const ValueKey<String>('help-page'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (showTitle) ...<Widget>[
          Text('使用说明',
              style: AppTypography.panelTitle
                  .copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppDimens.s8),
        ],
        for (final _Chapter c in _chapters) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(top: AppDimens.s16, bottom: AppDimens.s4),
            child: Text(c.title,
                style: AppTypography.panelTitle
                    .copyWith(color: colors.textPrimary)),
          ),
          for (final String line in c.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: AppDimens.s8),
              child: Text(line,
                  style: AppTypography.meta
                      .copyWith(color: colors.textSecondary, height: 1.45)),
            ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: AppDimens.s8),
          child: Text('以上就是当前真实有的功能。界面以后有改动，这一页会跟着改文案。',
              style: AppTypography.meta
                  .copyWith(color: colors.textFaint, height: 1.45)),
        ),
      ],
    );
  }
}

/// 整页外壳：顶栏写「使用说明」，正文自带滚动（411dp 与 1280dp 都不会溢出）。
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colors.surface,
        foregroundColor: colors.textSecondary,
        titleTextStyle: AppTypography.pageTitle
            .copyWith(fontSize: 17, color: colors.textPrimary),
        title: const Text('使用说明'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: colors.divider),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimens.panelPadding),
        child: const HelpSection(showTitle: false),
      ),
    );
  }
}

/// 把说明页推上去（首启引导与「关于」节共用这一跳）。
Future<void> pushHelpPage(BuildContext context) =>
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (BuildContext _) => const HelpPage(),
    ));
