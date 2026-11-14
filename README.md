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
2. 选择主舞台。
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
| 左键 / 右键（观战） | 切换观战对象 |

竞技模式：全员准备后倒计时开始；每次 rewind 扣 1 命；命数耗尽转观战。

## 地图

地图使用原生 MTA 格式，不维护第二份地图清单：

- `server/mapregistry.lua` 自动发现 `type="map"` resource
- 直接读取 `meta.xml` 和 `.map`
- 从 `.map` 读取全部 spawnpoint、vehicle、Hunter 终点 / checkpoint
- 地图 ID 就是 resource 名
- 地图池就是发现到的地图列表

出生：

- 每名玩家从 spawnpoint 列表随机选一个
- 使用该 spawnpoint 对应的 vehicle
- 不默认安装氮气

切换地图：

- `server/mapmanager.lua` 负责 start / stop 地图资源
- 地图自带 vehicle 会移除，racepickup / object / marker 保留
- 当前只支持一个地图实例、一个舞台；双舞台需要地图资源复制或维度实例化

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
- 回放期间关闭氮气喷射，结束时恢复回放点的状态
- 客户端本地回放，服务端只扣命，没有反作弊校验

相机只在进入游戏、观战返回、重生时重置，不会因每秒 state 更新把视角拉回车后。

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
| `playPopularityWeight` | 服务器游玩次数热度权重 |
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
- 单地图实例、单舞台
- 地图没有 checkpoint / 圈速结算；排行按 Hunter 终点距离或远离起点估算
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
