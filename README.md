# rst-mta-lite

基于 MTA:SA 1.6 的轻量服务器工程。服务端用 MTA 原生 Lua 资源；客户端界面统一由 MTA 内嵌 CEF 承载，前端用 Vue 3 + TypeScript + Vite。

## 当前进度

- [x] 仓库工程化：只提交源码，二进制 / 运行时 / 构建产物全部忽略
- [x] CEF + Vue 最小闭环：全屏 local 浏览器 → Vue HUD → CEF 菜单 → Lua ↔ JS 双向通信
- [ ] 业务资源 `rst_core`、更多页面、资源构建 / 部署脚本

## 仓库原则

**只提交源代码、文档、配置模板。** 规则见 [`.gitignore`](.gitignore)。

| 类型 | 路径 | 处理 |
| --- | --- | --- |
| 客户端 UI 源码 | `cef/` | 入库（Vue + Vite） |
| Vue 构建产物 | `server/.../rst_ui/ui/` | `pnpm build` 生成，忽略 |
| MTA 服务端本体 | `server/` 除 `resources/[rst]/` 外 | 本地安装，忽略 |
| 服务端运行时状态 | `logs/`、`dumps/`、`databases/`、`resource-cache/`、`backups/`、`*.db`、`server-id.keys`、`acl.xml`、`mtaserver.conf` | 生成 / 本机配置，忽略 |
| 前端依赖 | `node_modules/`、`dist/` | 依赖安装 / 构建生成，忽略 |
| 密钥与环境变量 | `.env*`、`*.pem`、`*.key` | 只提交 `.env.example` |
| 日志与临时文件 | `*.log`、`*.tmp`、`.DS_Store` 等 | 忽略 |

`server/` 下唯一被显式放行的是项目资源源码：

```
server/mods/deathmatch/resources/[rst]/**
```

## 目录结构

```
rst-mta-lite/
├─ cef/                                    # 客户端 UI 源码（Vue 3 + Vite + TS）
│  ├─ src/
│  │  ├─ mta/bridge.ts                     # window.rst / mta.triggerEvent 双向桥
│  │  ├─ mta/protocol.ts                   # 事件与数据类型
│  │  ├─ components/HudBar.vue             # 常驻 HUD
│  │  ├─ views/MenuView.vue                # F2 菜单
│  │  ├─ router/index.ts                   # hash 路由
│  │  └─ stores/session.ts
│  └─ vite.config.ts                       # 构建输出到 rst_ui/ui/
└─ server/mods/deathmatch/resources/
   └─ [rst]/rst_ui/                        # CEF UI 宿主资源
      ├─ meta.xml                          # 声明 ui/index.html + app.js + style.css
      ├─ client/main.lua                   # 浏览器、渲染、输入、桥
      ├─ server/main.lua                   # 服务器信息推送
      └─ ui/                               # 构建产物（不入库）
```

## 快速开始

```powershell
# 1. 构建 UI（产物直接写进资源目录）
cd cef
pnpm install
pnpm build

# 2. 启动服务器
cd ..\server
.\"MTA Server.exe"
```

客户端浏览器打开 `mtasa://127.0.0.1:22003`。

进服后：

- 左上角 / 左下角 HUD（服务器名、玩家名、在线数、HP、AR）由 Vue 渲染，数据来自 Lua
- 按 **F2** 打开 CEF 菜单；菜单打开时显示鼠标、接管键盘并禁用游戏控制
- 也可以按 F8 打开控制台输入 `ui` 切换菜单
- 菜单里的「测试 Lua 回调」走完整链路 JS → Lua → JS；「打开 DevTools」调 `toggleBrowserDevTools`

## 前端开发

```powershell
cd cef
pnpm dev          # http://127.0.0.1:5173，直接在浏览器里调 UI
pnpm type-check   # vue-tsc
pnpm build        # 固定文件名输出到 rst_ui/ui/
```

纯浏览器模式下没有 `window.mta`，bridge 会打印 `[rst-ui:mock]` 并模拟 bootstrap 数据；也可以直接访问 `http://127.0.0.1:5173/#/menu` 预览菜单。

> `meta.xml` 依赖固定产物名 `ui/assets/app.js`、`ui/assets/style.css`。改 `vite.config.ts` 的输出文件名时，必须同步 `meta.xml` 的 `<file>` 列表，否则客户端下载不到页面资源。

## CEF 通信机制

- **加载**：`createBrowser(w, h, true, true)`（local 模式）→ `onClientBrowserCreated` → `loadBrowserURL(browser, "http://mta/local/ui/index.html")`
- **渲染**：`onClientRender` 里 `dxDrawImage(0, 0, w, h, browser)`
- **输入**：`showCursor` + `guiSetInputEnabled` + `toggleAllControls`；鼠标经 `onClientCursorMove` / `onClientClick` / `onClientMouseWheel` 转发给 `injectBrowserMouse*`，键盘焦点用 `focusBrowser`
- **JS → Lua**：`mta.triggerEvent("rst:ui:*", jsonString)`，Lua 侧 `addEvent` + `addEventHandler` 接收
- **Lua → JS**：`executeBrowserJavascript(browser, 'window.rst.dispatch("event", jsonString)')`
- **类型定义**：`cef/src/mta/protocol.ts`；页面侧统一用 `onBridge` / `emitToLua`
- **调试**：`toggleBrowserDevTools(browser)`，开发期可配合 `setDevelopmentMode(true, true)` 在 F8 查看 CEF 报错

## 约定

- 资源命名 `rst_` 前缀；归类目录 `[rst]`（方括号目录不会作为资源加载）。
- 换行统一 LF；`.editorconfig`：Lua / XML 4 空格，前端 2 空格。
- 新建资源后在本机 `mtaserver.conf` 里加 `<resource src="..." startup="1"/>`（该文件不入库）。
- 仓库不带官方默认资源，启动日志里的 `Couldn't find resource admin/...` 可忽略，或在 `mtaserver.conf` 里注释掉对应行。
