# rst-mta-lite

轻量的 MTA:SA 服务器工程。服务端用 MTA 原生 Lua；客户端界面全部由 MTA 内嵌 CEF 承载，前端用 Vue 3 + TypeScript + Vite。

## 当前进度

- [x] 仓库工程化：只提交源码，二进制 / 运行时 / 构建产物全部忽略
- [x] CEF + Vue 基础：全屏 local 浏览器、输入注入、Lua ↔ JS 桥
- [x] 注册 / 登录 / 游客模式（昵称即账号名，bcrypt + SQLite）
- [x] 双舞台（DeathMatch 主舞台 / 副舞台）、30 分钟回合、观战 / 出生规则
- [x] 换图投票：时间到自动发起，也可从 F2 菜单提前发起
- [x] 长按 Y 的 rewind 回放（位置 / 朝向 / 速度，最近 8 秒）
- [x] 按钮点击 / 确认音效（`playSound`）
- [x] 界面视觉升级：Iconify 本地图标、毛玻璃面板、赛道作者信息
- [x] CEF 聊天替代原生聊天：常驻聊天记录 + T 呼出输入 + Enter 发送 / Esc 取消
- [x] 载具仪表：速度、车辆血量、氮气余量 / 触发状态
- [x] 顶部地图计时：地图名、本图剩余倒计时、个人本图已玩时长
- [x] 观战模式：鼠标左键 / 右键切换下一位 / 上一位玩家
- [x] 操作帮助面板：F1 呼出，F2 菜单也可进入
- [x] 出生倒计时：每人独立的 3-2-1-GO 动画，结束后才可移动
- [ ] 计分板、击杀统计、更多地图（当前是出生点地图）
- [ ] 部署脚本 / 更多管理功能

## 玩法流程

1. 进入服务器，CEF 显示登录界面：输入密码后点「登录」或「注册」，也可以「Play as Guest」直接游客进入。
2. 登录后进入舞台选择：`DeathMatch · 主舞台` / `DeathMatch · 副舞台`，两个舞台互相独立（不同 dimension），各自跑地图。
3. 进入舞台：
   - 舞台里有正在玩的玩家 → 默认**观战**，相机跟随场内玩家；下一回合自动转为玩家出生。
   - 观战时鼠标左键 / 右键循环切换下一位 / 上一位存活玩家，顶部显示当前跟随对象。
   - 舞台空着 → 直接开始新回合并出生。
4. 每张地图最多 30 分钟。时间到自动发起换图投票（30 秒），也可以在 F2 菜单里提前发起。
5. 投票结束切换地图，开始新回合；观战者一起转为玩家。

## 操作

| 操作 | 说明 |
| --- | --- |
| 密码输入 + 登录 / 注册 / 游客 | 登录界面 |
| `T` | 打开 CEF 聊天输入框（再按 Enter 发送、Esc 取消） |
| `F1` | 打开 / 关闭操作帮助（F2 菜单里也有入口） |
| `F2` / F8 控制台 `ui` | 打开菜单：发起换图投票、打开 DevTools、离开舞台 |
| F8 控制台 / 聊天 `/car` | 生成一辆带氮气的测试 Infernus（进入舞台后可用） |
| 观战模式左键 / 右键 | 切换下一位 / 上一位玩家 |
| 长按 `Y` | rewind 回放最近 8 秒，松开继续（菜单 / 聊天 / 投票 / 死亡时不可用） |
| 鼠标 | 登录、选舞台、菜单、投票时自动显示并注入 CEF |

## 聊天

原生聊天已被完全隐藏并拦截：

- `showChat(false, true)` 隐藏原生聊天并阻止原生输入
- `onClientChatMessage` 里 `cancelEvent()` 拦下所有原生聊天输出（包括 MTA 内部消息和其他资源调用 `outputChatBox` 的内容），转发给 CEF 渲染
- 聊天记录在左上角常驻显示（最近 100 条），玩家消息带彩色昵称，系统消息使用金色
- 按 `T` 呼出输入框，`Enter` 发送并关闭，`Esc` 取消；打开时显示鼠标、禁用游戏控制，关闭后恢复之前的游戏状态
- 玩家消息走 `chat:send` action → 服务端校验长度 / 频率（1 秒）→ 广播给已登录玩家；同时写入服务端日志
- 加入 / 离开服务器的系统消息也会以聊天形式推送

## 地图计时

进入舞台后，屏幕顶部居中常驻一条计时栏：

- 地图名
- 本图剩余倒计时：剩余 ≤ 5 分钟变金色、≤ 1 分钟变红色；投票期间切换为投票倒计时
- 本图已玩：玩家个人在当前地图的累计时间

个人时长由服务端 `session.mapEnteredAt` 计算：加入房间 / 换图时重置，观战、菜单、聊天期间都会累计；随 1 秒一次的 state 推送更新。

## 载具仪表

上车后底部居中显示速度表（下车自动隐藏）：

- 速度：`getElementVelocity` 合成后 `* 180` 得到 km/h，数字 + 渐变速度条
- 车辆血量：`getElementHealth(vehicle) / 10` 百分比，颜色随血量变黄 / 变红
- 氮气：`getVehicleNitroLevel`（当前瓶充能）、`getVehicleNitroCount`（剩余次数，101 显示 `∞`）、`isVehicleNitroActivated` 触发时高亮
- 数据由客户端 10Hz 通过 `vehicle` 事件推给 CEF

目前地图还没有载具，调试用 `/car` 生成一辆带氮气的 Infernus；上车后会补满并设为无限氮气。

## 出生倒计时

进入回合 / 换图后出生时：

- 服务端冻结玩家，并给该玩家单独推送 `countdown` 事件
- 客户端显示 3-2-1-GO 环形倒计时，每个数字有缩放淡入动画 + 提示音
- GO 后约 0.25 秒服务端解冻，玩家可以移动（相机在倒计时期间仍可转动）
- 倒计时期间禁用 rewind 录制；死亡重生不重复倒计时

倒计时长度在 [config.lua](<server/mods/deathmatch/resources/[rst]/rst_ui/shared/config.lua>) 的 `spawnCountdown` 调整。

## 房间与回合

配置在 `shared/config.lua`：

- `roundSeconds = 30 * 60`：单张地图最长时长
- `voteSeconds = 30`：投票时长
- `respawnDelay = 4000`：死亡重生间隔
- `maps`：地图名称、作者、出生点坐标 / 朝向（当前是 GTA 世界里的出生点，不依赖地图资源）
- `mapPool`：随机换图池
- `rooms`：两个舞台的 id / 名称 / dimension

规则实现见 `server/rooms.lua`：

- 两个舞台使用独立 dimension，玩家互相不可见
- 回合开始把所有观战者提升为玩家并出生
- 房间空掉时回合结束；下一次有人进入重新开回合
- 投票选项最多 3 张图，避免和另一舞台当前地图重复
- 换图后重置 30 分钟计时
- 进入舞台后，右下角显示「当前赛道」面板：地图名称 + 作者

## 账号与数据

- 账号名 = 玩家进入服务器时的昵称；密码用 `passwordHash(..., 'bcrypt')` 哈希后存入 SQLite
- 数据库：`server/mods/deathmatch/databases/global/rst_ui_accounts.db`（运行时生成，已被忽略）
- 游客不写数据库，重进服务器需要重新认证
- 登录 / 注册失败会通过 CEF toast 提示

## 目录结构

```
rst-mta-lite/
├─ cef/                                      # 客户端 UI 源码（Vue 3 + Vite + TS）
│  ├─ src/
│  │  ├─ mta/bridge.ts                       # window.rst / mta.triggerEvent 桥
│  │  ├─ mta/protocol.ts                     # state / vote / rewind 等类型
│  │  ├─ stores/ui.ts                        # 前端状态机
│  │  ├─ views/AuthView.vue                  # 登录 / 注册 / 游客
│  │  ├─ views/StageSelectView.vue           # 选择舞台
│  │  ├─ views/MenuView.vue                  # F2 菜单
│  │  ├─ views/VoteView.vue                  # 换图投票
│  │  ├─ components/GameHud.vue              # 游戏内 HUD
│  │  ├─ components/MapTimer.vue             # 顶部地图剩余 / 个人计时
│  │  ├─ components/ChatPanel.vue            # 左上角常驻 CEF 聊天
│  │  ├─ components/Speedometer.vue          # 载具速度 / 血量 / 氮气
│  │  ├─ components/SpawnCountdown.vue       # 3-2-1-GO 出生倒计时
│  │  ├─ components/HelpOverlay.vue          # F1 操作帮助
│  │  └─ components/RewindOverlay.vue        # rewind 覆盖层
│  └─ vite.config.ts                         # 构建输出到 rst_ui/ui/
└─ server/mods/deathmatch/resources/
   └─ [rst]/rst_ui/                          # CEF UI + 玩法资源
      ├─ meta.xml
      ├─ shared/config.lua                   # 地图 / 房间 / 时长
      ├─ server/accounts.lua                 # SQLite + bcrypt 账号
      ├─ server/rooms.lua                    # 房间、回合、投票
      ├─ server/main.lua                     # 会话、action、状态推送
      ├─ client/main.lua                     # 浏览器、输入、登录/观战/HUD
      ├─ client/rewind.lua                   # 长按 Y 回放
      ├─ sounds/click.wav, confirm.wav       # UI 音效
      └─ ui/                                 # 构建产物（不入库）
```

## 本地运行

```powershell
cd cef
pnpm install
pnpm build

cd ..\server
.\"MTA Server.exe"
```

客户端打开 `mtasa://127.0.0.1:22003`。

> 仓库不带官方默认资源，启动日志里的 `Couldn't find resource admin/...` 可忽略，或在 `mtaserver.conf` 里注释掉对应行。`rst_ui` 需要在本机 `mtaserver.conf` 中加入 `<resource src="rst_ui" startup="1"/>`（该文件不入库）。

## 前端开发

```powershell
cd cef
pnpm dev          # http://127.0.0.1:5173
pnpm type-check   # vue-tsc
pnpm build        # 固定文件名输出到 rst_ui/ui/
```

浏览器里没有 `window.mta`，会走 mock 日志。控制台可以用 `__rstMockState({...})` 直接模拟服务端状态，例如：

```js
__rstMockState({
  phase: 'stage',
  serverName: 'dev',
  me: { name: 'DevPlayer', guest: false },
  rooms: [
    { id: 'main', name: 'DeathMatch · 主舞台', mapName: 'Grove Street', author: 'RST Team', players: 2, spectators: 1, active: true, timeLeft: 900 },
  ],
})
```

### 图标（离线）

图标使用 Iconify 的 `lucide` 图标集，通过 `unplugin-icons` 在构建时编译成**内联 SVG**：

- 依赖：`@iconify-json/lucide`（图标数据，随 `pnpm-lock.yaml` 固定版本）
- 构建后不请求 `api.iconify.design`，CEF 只加载本地 `ui/assets/app.js`
- 用法：`import IconMap from '~icons/lucide/map'`，模板里 `<IconMap class="icon" />`

> `meta.xml` 依赖固定产物名 `ui/assets/app.js`、`ui/assets/style.css`。改 `vite.config.ts` 的输出文件名时必须同步 `meta.xml`。

## CEF 通信

- **加载**：`createBrowser(w, h, true, true)` → `onClientBrowserCreated` → `loadBrowserURL(browser, "http://mta/local/ui/index.html")`
- **渲染**：`onClientRender` 里 `dxDrawImage(0, 0, w, h, browser)`
- **输入**：`showCursor` + `guiSetInputEnabled` + `toggleAllControls`；鼠标经 `onClientCursorMove` / `onClientClick` / `onClientMouseWheel` → `injectBrowserMouse*`，键盘用 `focusBrowser`
- **JS → Lua**：`emitAction(action, payload)` → `mta.triggerEvent('rst:ui:action', json)`
- **Lua → JS**：`executeBrowserJavascript(browser, 'window.rst.dispatch("state", json)')`
- **服务端 → 客户端**：`triggerClientEvent(player, 'rst:ui:state', ...)`，客户端缓存后转发给页面
- **聊天**：原生 `onClientChatMessage` 被拦截后转成 `chatMessage`；玩家发送走 `chat:send` action，服务端再广播 `rst:ui:chat`
- **调试**：菜单「打开 DevTools」或 `toggleBrowserDevTools(browser)`

## 已验证 / 未验证

已验证（本机）：

- `pnpm type-check`、`pnpm build` 通过
- 全部 Lua 脚本用 luaparse（5.1 语法）解析通过
- 服务端启动：资源加载 0 失败；SQLite 建库成功
- 账号链路自检：bcrypt 创建 / 正确密码校验 / 错误密码拒绝
- Headless Chrome 渲染登录、选舞台、HUD（含赛道作者面板）、菜单、投票、rewind 覆盖层，以及点击事件与 `rst:ui:action` 参数
- 聊天：原生消息 / 玩家消息渲染、T 输入框、Enter 发送动作（`chat:send` + `chat:close`）在 Headless Chrome 中验证通过
- 载具仪表：速度 / 血量 / 氮气 / 档位在 Headless Chrome 中验证渲染
- 顶部计时：地图名 / 剩余倒计时 / 个人本图时长在 Headless Chrome 中验证渲染
- 观战切换：跟随对象与左右键提示在 Headless Chrome 中验证渲染
- 操作帮助：快捷键分组、F1/Esc 关闭在 Headless Chrome 中验证渲染
- 出生倒计时：3-2-1-GO 环形动画在 Headless Chrome 中验证渲染
- 图标全部内联到构建产物，构建后的 JS 中没有外部图标请求

未验证（需要真实 MTA 客户端）：

- 游戏内 CEF 的鼠标 / 键盘注入手感
- 观战相机、rewind 冻结与速度恢复效果

## 说明与限制

- 当前 rewind 是客户端本地记录 / 回放（50ms 采样，最近 8 秒），服务端没有反作弊校验
- 登录密码经 MTA 客户端事件发到服务端后再 bcrypt 存储；正式运营建议后续换用独立 Web 登录或额外加密
- 地图目前只是出生点配置，没有加载地图资源
- 击杀 / 计分还没做，当前是纯出生 + 换图 / 投票的 DeathMatch 基础框架

## 约定

- 资源命名 `rst_` 前缀；归类目录 `[rst]`（方括号目录不会作为资源加载）。
- 换行统一 LF；`.editorconfig`：Lua / XML 4 空格，前端 2 空格。
- 新建资源后在本机 `mtaserver.conf` 里加 `<resource src="..." startup="1"/>`（该文件不入库）。
