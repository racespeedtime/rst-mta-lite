# rst-mta-lite

轻量的 MTA:SA 服务器工程。服务端用 MTA:SA 原生 Lua 资源；客户端界面统一走 MTA 内嵌 CEF，用 Vue 3 + Vite 编写。

## 仓库原则

**只提交源代码、文档、配置模板。** 二进制、运行时状态、构建产物、密钥一律不入库，规则见 [`.gitignore`](.gitignore)。

| 类型 | 典型文件 / 目录 | 处理 |
| --- | --- | --- |
| MTA 服务端本体 | `server/*.exe`、`server/*.dll`、`server/mods/deathmatch/*.dll` | 本地安装，忽略 |
| 服务端运行时状态 | `logs/`、`dumps/`、`databases/`、`resource-cache/`、`backups/`、`*.db`、`server-id.keys`、`acl.xml`、`mtaserver.conf` | 运行时生成 / 本机配置，忽略 |
| CEF / 第三方二进制 | `cef/` | 本地运行时与工具，忽略 |
| 前端依赖与产物 | `node_modules/`、`dist/`、`rst_ui/ui/` | `pnpm install` / 构建生成，忽略 |
| 密钥与环境变量 | `.env*`、`*.pem`、`*.key` | 只提交 `.env.example` |
| 日志与临时文件 | `*.log`、`*.tmp`、`.DS_Store` 等 | 忽略 |

`server/` 下唯一被显式放行的是项目资源源码：

```
server/mods/deathmatch/resources/[rst]/**
```

## 目录结构

当前：

```
rst-mta-lite/
├─ .editorconfig
├─ .gitattributes
├─ .gitignore
├─ README.md
├─ cef/                                  # 本地 CEF 运行时 / 工具（不入库）
└─ server/                               # 本地 MTA 服务端安装（只有 resources/[rst] 入库）
   └─ mods/deathmatch/resources/[rst]/   # 项目资源源码
```

规划：

```
[项目资源]  server/mods/deathmatch/resources/[rst]/
├─ rst_core/     # 服务端基础：账号登录、数据存档、事件总线、日志……
└─ rst_ui/       # CEF UI 宿主：加载 web 构建产物 + Lua ↔ JS 桥

web/             # Vue 3 + Vite 前端源码
tools/           # 构建、同步、启动脚本
docs/            # 设计文档（按需）
```

## 本地运行

1. MTA:SA 1.6 服务端已解压到 `server/`（当前即如此）。
2. 运行 `server\MTA Server.exe`。首次启动会生成日志、数据库、ACL 等运行时文件（均已被忽略）。
3. 客户端浏览器打开 `mtasa://127.0.0.1:22003` 进入服务器。

> `server/mods/deathmatch/resources/` 下目前只有自研资源。`mtaserver.conf` 默认列出的官方资源（admin、mapmanager 等）如果不存在，启动日志会报错，属预期状态；不需要的话直接删掉对应的 `<resource>` 行。

## 客户端 UI：CEF + Vue

思路：**local 模式浏览器 + 单页 Vue 应用**，用路由或图层切换 HUD、菜单、登录等界面。

- 创建浏览器：`createBrowser(w, h, true, true)`（第 3 个参数为 local 模式；只有 local 模式能执行 JS、加载资源内文件）。
- 等 `onClientBrowserCreated` 后再 `loadBrowserURL(browser, "http://mta/local/index.html")`；`http://mta/local/` 指向当前资源根目录。
- 资源内所有页面、JS、CSS、字体、图片都必须在 `meta.xml` 里用 `<file src="..."/>` 声明，否则不会下发到客户端。
- Lua → JS：`executeBrowserJavascript(browser, "window.rst.xxx(...)")`。
- JS → Lua：`mta.triggerEvent("rst:ui:event", payload)`；事件 source 即该浏览器元素，在 client Lua 里用 `addEventHandler` 接收，需要服务端处理时再 `triggerServerEvent`。
- 约定 JS 侧只挂一个命名空间（如 `window.rst`），Lua 侧只调用这个前缀，避免任意代码注入。
- 调试：`toggleBrowserDevTools(browser)` 打开 DevTools；开发期 `setDevelopmentMode(true, true)` 可在 F8 看 CEF 报错。
- 参考：[CEF Tutorial](https://wiki.multitheftauto.com/wiki/CEF_Tutorial)、[Local Scheme Handler](https://wiki.multitheftauto.com/wiki/Local_Scheme_Handler)。

前端待落地：`web/` 用 Vue 3 + Vite + TypeScript；构建产物通过 `tools/` 脚本同步到 `rst_ui/ui/`（构建生成，不入库）。

## 约定

- 资源命名：`rst_` 前缀；资源根目录放 `meta.xml`。
- 换行统一 LF（`.gitattributes` 固定），编辑配置见 `.editorconfig`（Lua / XML 4 空格，前端 2 空格）。
- 新建资源后，在本机 `mtaserver.conf` 里加 `<resource src="..." startup="1"/>` 才会启动；该文件不入库。
- 若要把服务端配置版本化，另建 `config/mtaserver.conf.example` 之类的模板，不要把带密码的本机配置提交。
