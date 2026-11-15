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
2. 选择主舞台或副舞台。两个舞台共用同一张地图，同一时间只允许一个舞台开局。
3. 空房直接开始；有玩家进行中则先观战，下回合参赛。
4. 训练模式默认无限 rewind；竞技模式 10 条命。
5. 地图 30 分钟一轮，可发起换图投票。

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

### 完赛进度

所有模式都会根据玩家到终点的距离计算完赛百分比：

- 顶部地图计时下方显示进度条
- 显示百分比、距终点距离
- 冲线后固定为 100%
- 竞技排行里的玩家也会显示百分比

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
- 支持 nitro / repair / vehiclechange，命中后服务端同步、隐藏和重生
- 官方 race pickup 模型放在 `pickups/`
- 地图 ID 就是 resource 名
- 地图池就是发现到的地图列表

出生：

- 每名玩家从 spawnpoint 列表随机选一个
- 使用该 spawnpoint 对应的 vehicle
- 不默认安装氮气

切换地图：

- `server/mapmanager.lua` 负责 start / stop 地图资源
- 地图自带 vehicle 会移除，racepickup / object / marker 保留
- 当前两个舞台共用同一个地图实例，同一时间只允许一个舞台开局；真正并行需要地图资源复制或维度实例化

地图详情：

- F2 →「地图详情」查看当前地图
- 显示封面、作者、上传日期、下载量、大小、难度、标签、spawn / vehicle / 终点
- YouTube、mtavault 链接支持复制，不内嵌视频
- 原生信息来自 `.map`；封面和链接来自 `mapmeta.json` + `covers/`，仅用于展示，不参与加载

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
- 记录位置、朝向、速度、氮气 level / count / 喷射状态
- 同时记录并回放载具血量，结束时同步回服务端
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
    mapmeta.json             地图展示元数据
    covers/                  地图封面
tools/mtavault/              mtavault 抓取 / 扫描
tools/setup-map-acl.mjs      地图 ACL 设置
```

## 已知限制

- CEF 中文输入不可用
- 两个舞台共用地图实例，同一时间只能开一个；真正并行需要地图资源复制或维度实例化
- 地图没有 checkpoint / 圈速校验；完赛按终点半径判定，排行按冲线顺序
- rewind 是客户端本地回放，无服务端校验
- 原生地图脚本可能输出自己的聊天提示或 deprecated 警告
- 登录错误会区分账号不存在 / 密码错误

## 验证

- `pnpm type-check`、`pnpm build`、Lua 5.1 语法检查通过
- 真实客户端验证注册、登录、游客、舞台、HUD、地图加载、地图详情
- 服务端启动：`Resources: 4 loaded, 0 failed`
- 地图发现：3 个原生 map resource
- 地图资源 ACL、随机 spawn、无默认氮气、地图详情已在客户端验证

## 约定

- 源码和文档使用 LF
- 地图、压缩包、数据库、日志、`ui/` 构建产物不入库
- 远程仓库：`git@github.com:racespeedtime/rst-mta-lite.git`
