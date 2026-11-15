# rst-mta-lite

轻量 MTA:SA 竞速服务器。服务端使用 MTA Lua，客户端界面使用 CEF + Vue 3 + TypeScript + Vite。

DeathMatch 是竞速模式：随机出生点、对应车辆、无默认氮气。

## 运行

```bash
# UI
cd cef
pnpm install
pnpm build

# 服务端
server/MTA Server.exe
```

- 服务端端口：`22003`
- 只启动 `rst_ui`
- UI 构建产物在 `server/mods/deathmatch/resources/[rst]/rst_ui/ui/`，不入库
- 地图资源放在 `server/mods/deathmatch/resources/`，不入库

### 地图 ACL

`rst_ui` 需要启动地图资源和读取原生地图 XML：

```bash
# 停止服务器后运行
node tools/setup-map-acl.mjs
```

也可以在 MTA 管理面板批准 `rst_ui/meta.xml` 里的 `aclrequest`。

## 玩法

1. 登录、注册或游客进入。
2. 一个服务器只有一个比赛舞台，登录后直接进入。
3. 空房直接开始；有玩家进行中则先观战，下回合参赛。
4. 训练模式默认无限 rewind；竞技模式 10 条命。
5. 地图 30 分钟一轮，可发起换图投票。
6. 服务端统一限制最高 60 FPS。

### 操作

| 按键 | 功能 |
| --- | --- |
| `T` | 聊天输入 |
| `F1` | 帮助 |
| `F2` | 菜单 |
| `F3` | 临时显示 / 隐藏光标 |
| 长按 `Y` | rewind 最近 8 秒 |
| 观战 | 鼠标转向 · `WASD` 平移 · 鼠标左/右键切换跟踪玩家 · 空格 / Ctrl 升降 |
| 菜单 | 训练模式可主动重生 |

竞技模式：全员准备后倒计时开始；每次 rewind 扣 1 命；命数耗尽转观战。

### 个人竞技 / 团队竞技

竞技模式分两种：

- **个人竞技**：按个人冲线名次计分
- **团队竞技**：红队 / 蓝队，按队伍总分结算

团队竞技规则：

- 开局前玩家在准备面板选择红队或蓝队
- 红蓝人数必须相等，且每名玩家都有队伍，才能开始倒计时
- 人数不相等时显示队伍人数警告，可以切队或改为观战
- 玩家头顶名字按队伍颜色显示，聊天、排行、结算也带队伍颜色
- 得分：第 1 名 10 分，第 2 名 8 分，第 3 名 6 分，之后依次 4 / 3 / 2 / 1 分
- 团队总分为队员得分之和；总分相同时比较最好名次

模式投票现在有三个选项：训练、个人竞技、团队竞技。

### 计时精度

- 地图剩余、本图计时、换图 / 模式投票剩余、结算倒计时统一显示 `mm:ss.mmm`
- 服务端提供毫秒基准，客户端在两次 state 之间本地插值，避免每秒跳一次
- 个人最佳也按毫秒存储和显示
- 冲线按 100ms 独立检测，避免 1 秒 tick 把成绩量化成整秒

### 竞技排行

- 已到达 Hunter / 终点完赛的玩家优先
- 完赛玩家按冲线名次排序
- 其余玩家按剩余命数降序排序

## 完赛与结算

- 车辆进入终点半径即算完赛
- 竞速模式第一名完赛后进入 **30 秒结算倒计时**
  - 其他玩家仍可继续冲线
  - 倒计时结束后显示前三，约 8 秒后自动进入换图投票
- 训练模式按玩家个人结算
  - 完赛显示个人成绩
  - **5 秒后回到随机出生点**，其他人不受影响
- 终点半径、倒计时、结算展示时间、训练返回延迟都在 `shared/config.lua` 调整
- 顶部计时和右下角赛道面板显示**当前地图个人最佳**
- 个人最佳按 serial + 地图 resource 存入 `rst_ui_records.db`，训练 / 竞速完赛都会更新

## 音效

- 出生倒计时：每下数字一声短提示音
- GO：独立发车音
- 冲线完赛：上行结算音
- 比赛结束但未完成 / 被淘汰：下行失败音
- 团队结算按红蓝胜负播放对应完赛 / 失败音
- 按钮和确认保留点击 / 确认音

音效文件在 `sounds/`，通过 `meta.xml` 下载。

## 地图

地图使用原生 MTA 格式，不维护第二份地图清单：

- `server/mapregistry.lua` 自动发现 `type="map"` resource
- 直接读取 `meta.xml` 和 `.map`
- 从 `.map` 读取全部 spawnpoint、vehicle、racepickup、Hunter 终点 / checkpoint
- `racepickup` 由客户端按官方 race 资源方式创建自定义模型 object + colshape
- 支持 nitro / repair / vehiclechange；respawn=0 为永久可重复拾取，respawn>=50 才隐藏并按毫秒重生
- 官方 race pickup 模型放在 `pickups/`
- 解析并应用 `<settings>`：时间、天气、重力、游戏速度、浪高、车辆武器、云层、地图时长
- 地图车辆模型替换由地图 resource 自己的 client 脚本完成（例如 Silent Hill 的 Sandking 495），加载地图时自动执行
- 地图 ID 就是 resource 名
- 地图池就是发现到的地图列表
- 启动只读 `meta.xml`，`.map` 的 spawn / pickup / finish 在选中地图时才解析

## mtavault 地图集

截至 **2026-11-15**：

- 已抓取并写入 SQLite 的 mtavault **DM / HDM** 元数据：**4509 张**
- HDM 15 张同时带 DM 标签，按地图 ID 去重后为 4509
- 当前服务器实际安装并用于验证的地图：4 张
- 地图本体 zip 作为可选备份包，不进入 Git

完整地图 zip 由维护者上传网盘；下载后不需要解压，直接放到：

```text
server/mods/deathmatch/resources/
```

例如：

```text
resources/silent-hill.zip
resources/atlas.zip
resources/superieur.zip
```

MTA 支持 zip resource，资源名就是 zip 去掉 `.zip` 的名字。

然后：

```text
refresh
restart rst_ui
```

或者直接重启服务器，地图会进入地图池。

要求：

- zip 根目录直接有 `meta.xml`，不能多套一层文件夹
- 不要同时保留同名解压目录和 zip
- 不要把已经安装过的 4 张重复复制
- 客户端只会下载当前被选中的地图，不会因为装了 4509 张就全部下载

F2 →「地图池」可以分页浏览和搜索已安装地图。

启动只读取轻量 meta；只有地图被选中时才解析 `.map`。全量 4509 张会扫描 4509 个 resource/meta，但不会启动时解析全部地图细节。

出生：

- 每名玩家从 spawnpoint 列表随机选一个
- 使用该 spawnpoint 对应的 vehicle
- 不默认安装氮气

切换地图：

- `server/mapmanager.lua` 负责 start / stop 地图资源
- 地图自带 vehicle 会移除，racepickup / object / marker 保留
- 单服务器只运行一个比赛舞台，同一时间一张地图；并行舞台需要地图实例化或双服务器

地图详情：

- F2 →「地图详情」查看当前地图
- 显示封面、作者、上传日期、下载量、大小、难度、标签、spawn / vehicle / 终点
- YouTube、mtavault 链接支持复制，不内嵌视频
- 原生信息来自 `.map`；封面和链接来自 mtavault 元数据 SQLite（首次从 `mapmeta-catalog.json` 导入），按需查询，不参与加载

地图本体、压缩包、地图缓存都不进 Git。

## 账号

- 自定义 SQLite 账号，昵称即账号名
- 注册需要输入两遍密码
- 密码最少 8 位
- 使用 MTA `passwordHash` / `passwordVerify`（bcrypt）
- 游客不写数据库

当前不是 MTA 官方 Account：没有 ACL、账号数据、密码重置。

## 聊天

- 原生聊天被拦截，由 CEF 显示
- 保留最近 100 条；列表可滚动，超出后删除最早一条
- 往上翻历史时不会被新消息拉到底部，新消息有提示按钮
- 单条消息按 UTF-8 字符数限制 160 字
- 玩家消息走 `chat:send`，服务端限制 1 秒频率
- `/` 开头的消息按指令执行，不再作为聊天广播
- 可用指令：`/help`、`/car [模型]`

中文输入当前受 CEF IME 限制：只能输入英文、数字、符号。显示和发送支持 UTF-8；要支持中文输入需要改用 MTA 原生 chatbox 或内嵌 IME。

## UI

- CEF 全屏透明，只有 HUD 面板有背景
- 登录 / 菜单 / 投票 / 聊天等场景强制显示光标，游戏内默认隐藏
- 1080p 为 1.0×，720p / 1440p / 4K 自动缩放
- 原生血条、武器、金钱等 HUD 隐藏，保留雷达和准星
- 右下角显示构建日期和 git hash

## Rewind

- 客户端本地记录最近 8 秒
- 记录位置、朝向、速度、载具血量、氮气 level / count / 喷射状态
- 同时记录并回放载具血量，结束时同步回服务端
- 回放结束保留回放点之前的历史并平移到当前时间，连续使用不会从 0 重新攒时间
- 回放期间关闭氮气喷射，结束时恢复回放点的状态
- 客户端本地回放；服务端负责扣命和结束时血量同步，没有反作弊校验

相机只在进入游戏、观战返回、重生时重置，不会因每秒 state 更新把视角拉回车后。观战使用自由飞行相机，不再跟随幸存玩家。

## 配置

主要配置在 `shared/config.lua`：

| 字段 | 说明 |
| --- | --- |
| `roundSeconds` | 每张地图时长 |
| `defaultMode` | 默认训练 / 竞技 |
| `competitiveLives` | 竞技命数 |
| `voteSeconds` / `modeVoteSeconds` | 投票时长 |
| `voteCooldown` / `modeVoteCooldown` | 手动投票冷却 |
| `spawnCountdown` / `competitiveCountdown` | 出生倒计时 |
| `finishRadius` | 终点判定半径 |
| `raceEndCountdown` | 第一名完赛后的结算倒计时 |
| `raceResultSeconds` | 结算排行展示时间 |
| `trainingReturnSeconds` | 训练模式完赛回出生点延迟 |
| `playPopularityWeight` | 服务器游玩次数热度权重 |
| `scoreTable` | 冲线名次对应积分 |
| `teamColors` | 红 / 蓝队名字颜色 |
| `vehicle` | 没有 spawnpoint vehicle 时的默认车型 |

地图列表不写在配置里。

## 目录

```text
cef/                         Vue 3 + Vite 前端
server/                      MTA 服务端运行时
  mods/deathmatch/resources/[rst]/rst_ui/
    client/                  CEF、输入、rewind、ghost
    server/                  账号、地图、房间、投票
    shared/config.lua        玩法配置
    mapmeta-catalog.json     mtavault DM/HDM 元数据快照（首次导入 SQLite）
    covers/                  地图封面
tools/mtavault/              mtavault 抓取 / 扫描
tools/mtavault/seed/         只读地图元数据 seed DB
tools/setup-map-acl.mjs      地图 ACL 设置
```

## 已知限制

- CEF 输入框中文输入不可用；聊天输入已改用 MTA 原生 chatbox
- 单服务器单舞台，同一时间一张地图；真正并行需要地图实例化或双服务器
- 地图没有 checkpoint / 圈速校验；完赛按终点半径判定，排行按冲线顺序和剩余命数
- rewind 是客户端本地回放，无服务端校验
- 原生地图脚本可能输出自己的聊天提示或 deprecated 警告
- 登录错误会区分账号不存在 / 密码错误

## 验证

- `pnpm type-check`、`pnpm build`、Lua 5.1 语法检查通过
- 真实客户端验证注册、登录、游客、HUD、地图加载、地图详情、地图池分页
- 服务端启动：`Resources: 5 loaded, 0 failed`
- 地图发现：4 个原生 map resource
- mtavault 元数据：4509 张，SQLite 已导入
- 地图资源 ACL、随机 spawn、无默认氮气、地图详情已在客户端验证

## 约定

- 源码和文档使用 LF
- 地图、压缩包、数据库、日志、`ui/` 构建产物不入库
- 远程仓库：`git@github.com:racespeedtime/rst-mta-lite.git`
