# [rst] — 项目资源源码目录

方括号目录是 MTA 的归类约定：服务器不会把它当作资源加载，只会扫描它下面的子目录。

- 每个资源 = 一个子目录 + 根级 `meta.xml`，目前只有 `rst_ui/`。
- `rst_ui/` 同时承载 CEF 界面和 DeathMatch 玩法（账号、房间、回合、投票、rewind）。
- 本目录已被 `.gitignore` 白名单放行，是 `server/` 下**唯一**会进入 Git 的路径。
- `rst_ui/ui/` 是 `cef/` 的 Vue 构建产物，由 `pnpm build` 生成、不入库。
- 官方或第三方资源请放在 `resources/` 的其他位置，不要放进 `[rst]`，避免混入版本库。
