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
- [ ] 计分板、击杀统计、更多地图（当前是出生点地图）
- [ ] 部署脚本 / 更多管理功能

## 玩法流程

1. 进入服务器，CEF 显示登录界面：输入密码后点「登录」或「注册」，也可以「Play as Guest」直接游客进入。
2. 登录后进入舞台选择：`DeathMatch · 主舞台` / `DeathMatch · 副舞台`，两个舞台互相独立（不同 dimension），各自跑地图。
3. 进入舞台：
   - 舞台里有正在玩的玩家 → 默认**观战**，相机跟随场内玩家；下一回合自动转为玩家出生。
   - 舞台空着 → 直接开始新回合并出生。
4. 每张地图最多 30 分钟。时间到自动发起换图投票（30 秒），也可以在 F2 菜单里提前发起。
5. 投票结束切换地图，开始新回合；观战者一起转为玩家。

## 操作

| 操作 | 说明 |
| --- | --- |
| 密码输入 + 登录 / 注册 / 游客 | 登录界面 |
| `F2` / F8 控制台 `ui` | 打开菜单：发起换图投票、打开 DevTools、离开舞台 |
| 长按 `Y` | rewind 回放最近 8 秒，松开继续（菜单 / 聊天 / 投票 / 死亡时不可用） |
| 鼠标 | 登录、选舞台、菜单、投票时自动显示并注入 CEF |

## 房间与回合

配置在 `shared/config.lua`：

- `roundSeconds = 30 * 60`：单张地图最长时长
- `voteSeconds = 30`：投票时长
- `respawnDelay = 4000`：死亡重生间隔
- `maps`：地图名、出生点坐标 / 朝向（当前是 GTA 世界里的出生点，不依赖地图资源）
- `mapPool`：随机换图池
- `rooms`：两个舞台的 id / 名称 / dimension

规则实现见 `server/rooms.lua`：

- 两个舞台使用独立 dimension，玩家互相不可见
- 回合开始把所有观战者提升为玩家并出生
- 房间空掉时回合结束；下一次有人进入重新开回合
- 投票选项最多 3 张图，避免和另一舞台当前地图重复
- 换图后重置 30 分钟计时

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
    { id: 'main', name: 'DeathMatch · 主舞台', mapName: 'Grove Street', players: 2, spectators: 1, active: true, timeLeft: 900 },
  ],
})
```

> `meta.xml` 依赖固定产物名 `ui/assets/app.js`、`ui/assets/style.css`。改 `vite.config.ts` 的输出文件名时必须同步 `meta.xml`。

## CEF 通信

- **加载**：`createBrowser(w, h, true, true)` → `onClientBrowserCreated` → `loadBrowserURL(browser, "http://mta/local/ui/index.html")`
- **渲染**：`onClientRender` 里 `dxDrawImage(0, 0, w, h, browser)`
- **输入**：`showCursor` + `guiSetInputEnabled` + `toggleAllControls`；鼠标经 `onClientCursorMove` / `onClientClick` / `onClientMouseWheel` → `injectBrowserMouse*`，键盘用 `focusBrowser`
- **JS → Lua**：`emitAction(action, payload)` → `mta.triggerEvent('rst:ui:action', json)`
- **Lua → JS**：`executeBrowserJavascript(browser, 'window.rst.dispatch("state", json)')`
- **服务端 → 客户端**：`triggerClientEvent(player, 'rst:ui:state', ...)`，客户端缓存后转发给页面
- **调试**：菜单「打开 DevTools」或 `toggleBrowserDevTools(browser)`

## 已验证 / 未验证

已验证（本机）：

- `pnpm type-check`、`pnpm build` 通过
- 全部 Lua 脚本用 luaparse（5.1 语法）解析通过
- 服务端启动：资源加载 0 失败；SQLite 建库成功
- 账号链路自检：bcrypt 创建 / 正确密码校验 / 错误密码拒绝
- Headless Chrome 渲染登录、选舞台、HUD、菜单、投票、rewind 覆盖层，以及点击事件与 `rst:ui:action` 参数

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
