# AGENTS.md — qingdan（自用任务清单）

> 📋 管理规范见: 开发文档/00-必读/开发文档管理.md
>
> **注意**：本文件提到的 `开发文档/`、`需求总结/`、`相关来源或素材/` 是作者本地的过程文档目录，
> **不随本仓库发布**（里面记着真实课程、作业、教师名与真机验收数据）。
> clone 下来构建只需要 `README.md`；本文件是给**在这个仓库里工作的 AI 代理**看的约定。

## 项目定位

给一个人、多台设备（Windows + Android）的自用任务清单：数据完全归自己、可离线、能把课表与日历合并进来。**无自建服务端**（需求定死）。

## 当前状态

里程碑进度与逐条教训已移到 `开发文档/00-必读/当前状态.md`（过程文档不随公开仓库发布，理由见 `.gitignore` 末段注释）。摘要：**P0–P3、M1–M6 全部落地**；Android 端自用，无自建服务端；`flutter analyze` 0 告警、全量 **1012 测试绿**（`--concurrency=1`）、`lib/` 与 `test/` 全部 ≤300 行；正式签名钥匙与 CI 出包工作流已就位，第一个 GitHub Release 由本轮收尾创建。

## 技术栈（P3 锁定的真实版本）

| 项 | 版本 | 说明 |
| --- | --- | --- |
| Flutter | 3.47.5 stable | 本机安装路径不写进公开文档；构建步骤见 `README.md` |
| Dart | 3.13.4 | pubspec 环境 SDK `^3.13.4` |
| sqflite_common_ffi | 2.4.3 | SQLite（Windows 经 FFI；业务库路径显式指定，见 `lib/data/database.dart`） |
| path_provider | 2.1.6 | 应用数据目录（数据库不落 `.dart_tool`） |
| provider | 6.1.5+1 | 状态管理（最小方案，不引入 riverpod/bloc） |
| intl | 0.20.3 | 日期时间格式化 |
| window_manager | 0.5.2 | 桌面窗口控制（M1 用） |
| flutter_local_notifications | 22.3.1 | 本地通知（F15） |
| csv | 8.0.0 | 课表 CSV 解析（M4） |
| excel | 4.0.6 | xlsx 读取（M4） |
| icalendar_parser | 2.1.0 | .ics 解析（M4） |
| flutter_secure_storage | 11.2.0 | 系统凭据库存 WebDAV 密码（M3；Windows 凭据管理器 / Android Keystore） |
| file_selector | 1.1.0 | 选文件（M4a；官方多端插件，Android 走 SAF，替代设计稿原定的 file_picker） |
| crypto | 3.0.7 | 课程 UID 的 sha1（M4a；原本只是传递依赖，现显式声明） |
| enough_convert | 1.7.1 | CSV 的 GBK 解码（M4a；`dart:convert` 无 GBK，纯 Dart 零依赖） |
| flutter_lints | 6.0.0 | dev 依赖，lint 基线 |

## 目录结构

```text
program1-qingdan/
├── AGENTS.md                     # 本文件
├── pubspec.yaml                  # 依赖锁定
├── lib/
│   ├── main.dart                 # 入口
│   ├── domain/                   # 纯数据与规则，无 IO
│   ├── application/              # 用例层，所有写操作的唯一入口
│   ├── data/                     # SQLite DAO、凭据库（database.dart / migrations.dart 已就位）
│   ├── sync/                     # 同步引擎、意图推导、三路合并、后端实现、配置/协调器（M2 引擎 + M3 接线与真机验收）
│   ├── import/                   # 导入管道：course/ 已就位（M4a S2），ics / csv 待做（M4b）
│   └── features/
│       ├── shell/                # 主窗口框架、侧栏、断点切换、窄屏 56dp 顶栏（§1.7/§2.6）
│       ├── tasks/                # 任务列表、任务行、快速添加、回收站面板
│       ├── detail/               # 任务详情面板
│       ├── calendar/             # 日历视图（月/周/日）
│       ├── course/               # 课表周视图、课程块、导入向导（M4a）
│       ├── settings/             # 设置界面（同步节 / 主题 / 凭据入口，M3）
│       └── trash/                # 回收站
├── test/                         # 测试
├── _probe/                       # 一次性平台能力探针工程（已结算，勿在其内开发；已被 analyze 排除）
├── _env_backup/                  # 环境变量备份，只读
├── 开发文档/                     # 项目过程文档（见 00-必读/开发文档管理.md）
├── 需求总结/                     # 需求输入，只读
└── 相关来源或素材/               # 外部素材，只读
```

## 常用命令

```bash
# 安装依赖
flutter pub get

# 本地运行（Windows）
flutter run -d windows

# 运行测试
flutter test

# 静态检查（当前基线：No issues found!）
flutter analyze
```

> Windows 本机 PATH 未必含 flutter：用你自己那份 `flutter.bat` 的绝对路径，或把 `flutter\bin` 加进 PATH。
> 本仓库不再记录任何人的本机安装路径。

## 代码风格

- 文件与目录小写蛇形（`sync_engine.dart`）；类名大驼峰；以 `flutter analyze` 无告警为准。
- **单一源码文件不超过 300 行**；超了按职责拆。
- **UI 层不得直接访问数据库 DAO**，只能调用用例层（`lib/application/`）；用例层内「写库 + 记待同步意图」必须在同一事务中。
- 同步子系统不得直接修改 UI 状态，只能写库并发出变更通知。
- **同步实体只有四类**：`lib/sync/sync_serializer.dart` 的 `kEntityTypes = list / task / subtask / tag`，且**必须按此顺序**（父实体先落库，外键才有可引用的行）。`task_tags` 关联表**不参与同步**——标签关联视为设备本地视图（2026-10-10 定案，见 `需求规格书` 第七节）。
- **数据库路径显式指定**（`lib/data/database.dart` 的 `resolveDatabasePath`），不得退回 sqflite_common_ffi 默认位置（`.dart_tool` 下，清构建即丢数据）。
- 迁移只增不改：`lib/data/migrations.dart` 的 `kMigrations` 版本号连续递增，历史条目不得修改。

## 工作方式（子代理与技能路由）

- **优先用子代理**：任何需要跨多文件探索、批量核对、或可并行拆分的任务，默认开子代理（`Agent` 工具）并行跑，不要自己串行翻仓库。只读探索类用 `Explore`，需要边查边改的用 `general-purpose`。已知路径/符号的单点查找除外（直接用 Read/Grep）。
- **量化结论交给子代理取证**：性能、体积、耗时、命中率这类需要测量的说法，用子代理去跑并回报真实数字；测不出来的就直说没测，不允许估。
- **每个新任务先过 skill-router**：调用 `skill-router` 技能做路由。冷技能库在 `~/.skill-library`（各人本机路径不同，不写死），目录索引 `catalog\categories.jsonl`，单次最多读 2 个分类、3 个技能正文。命中就在回复里用一行「使用 skills：xxx」标注，未命中就直接干，不要空转翻目录。
- **梳理新需求时用 `grilling` 技能**：路径 `skills\workflow-planning\grilling\SKILL.md`（catalog 关键词搜不到，须按路径读）。角色是需求设计师，一轮问完全部 frontier、每题给推荐答案，用户答完再算下一轮；frontier 清空前不写代码、不出文档。

## 禁止事项

- 不要提交任何密钥 / Token / 凭据 / 连接串 / 生产数据。
- **云盘凭据只进系统凭据库**（Windows 凭据管理器 / Android Keystore），不得写入代码或日志。
- **不要修改 `需求总结/` 与 `相关来源或素材/`**（只读）。
- **参考项目复用必须声明来源**：`F:\Code\APK-MCP\3-Wakeup`（课程表）与 `F:\Code\APK-MCP\9-Ticktick\Gradle`（TickTick）是逆向工程产物，允许移植/改写算法与数据结构（纯自用），但**每个移植的文件头必须写明来源（原路径 + 原类名 + 参考行号）**，并在变更日志登记。**不要批量拷贝整个包**。
- **不要拷贝参考项目里的第三方 SDK、资源文件与原生库**（`.so`、广告 SDK、厂商推送 SDK 等）。
- **不要自建任何服务端**——需求定死的约束，不是实现细节。
- 单份源码文件不超过 **300 行**；单份文档不超过 **500 行**。
- **不要一上来读整个仓库**；按「新会话加载顺序」加载。

## 文档约定与新会话加载顺序

规范正文只在 `开发文档/00-必读/开发文档管理.md` 维护；每次改动当场写 `开发文档/01-变更日志/变更日志-YYYY-MM-DD.md`。加载顺序：

1. `开发文档/00-必读/项目概览.md`
2. `开发文档/00-必读/开发文档管理.md`
3. `开发文档/00-必读/需求规格书.md`（需求契约与明确不做）
4. `开发文档/02-方案设计/方案设计.md`（+ 当前里程碑的设计文档）
5. 最近一份 `开发文档/01-变更日志/变更日志-*.md`
