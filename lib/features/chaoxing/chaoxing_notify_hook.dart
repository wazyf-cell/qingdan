/// 退出学习通时取消「到期提醒」的**真实**路径（M6B §B4 立项，本轮兑现）。
///
/// 这里原本是一个默认空实现的可替换变量 `cancelAllChaoxingNotifications`，
/// 且全仓库没有任何赋值点——于是退出登录确认框那句「已排的到期提醒会一并取消」
/// 是假的：`chaoxing.notify.snapshot` 不随 logout 清，协调器每次重排都还会读到
/// 同一份快照，用户退了学习通，那些「某门课 · 作业1 截止前 2 小时」照样会响。
/// 现在直接作用在 [ReminderCoordinator] 上，占位不再存在（项目的定案是
/// 「占位要么说清原因，要么别出现」）。
///
/// 为什么签名收可空的协调器、而不是 [BuildContext]：调用点 `chaoxingLogout` 必须
/// 在第一个 `await` 之前把 provider 取出来（async gap 之后再摸 context 会撞
/// `use_build_context_synchronously`，而且弹层退场后那个 context 可能已经没了），
/// 「协调器不存在」这种降级形态就在本函数里处理掉，调用点不用到处写 try/catch。
library;

import 'package:flutter/foundation.dart';

import 'package:qingdan/notify/chaoxing_snapshot.dart';
import 'package:qingdan/notify/reminder_coordinator.dart';

/// 只清学习通那一路的数据源并重排：清单提醒照排不误（判据与实现见
/// [ReminderCoordinator.dropChaoxingReminders]）。
///
/// [coordinator] 为 null 是真实存在的形态——`main.dart` 只在建库成功时注册它。
/// 那种情况下退一步**只清快照**：本次会话没有引擎实例，OS 里上一次会话排的通知
/// 取消不了（诚实写明，不假装成功），但快照清了，下次成功启动就不会把已退出账号
/// 的学习通提醒重新排回来。
Future<void> cancelChaoxingReminders(ReminderCoordinator? coordinator) async {
  if (coordinator != null) {
    await coordinator.dropChaoxingReminders();
    debugPrint('chaoxing: 已取消学习通到期提醒并重排（清单提醒不受影响）');
    return;
  }
  try {
    await ChaoxingSnapshotStore().clearSnapshot();
    debugPrint('chaoxing: 提醒协调器未装配，已清快照（本次无法重排）');
  } catch (e) {
    // 只打类型：这里没有任何用户数据，但保持与 notify/ 一处同样的写法。
    debugPrint('chaoxing: 提醒快照清理失败：${e.runtimeType}');
  }
}
