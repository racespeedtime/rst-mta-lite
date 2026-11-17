# [rst] — 项目资源

方括号目录是 MTA 的归类约定：服务器不会把它当作资源加载，只会扫描它下面的子目录。每个资源仍然是「子目录 + 根级 `meta.xml`」。

- `rst_ui/`：CEF 界面 + DeathMatch 玩法（账号、房间、回合、投票、rewind）。
- `maplib/`：按需地图库。`meta.xml` 入库且不声明文件；`maps/`、`index.json`、`build-report.json` 由 `tools/mapstore/build-library.mjs` 生成，不入库。
- `rst_map_<mapId>/`：运行期地图槽位，由 `rst_ui` 创建和复用，不入库。
- `rst_ui/ui/`：Vue 构建产物，由 `pnpm build` 生成，不入库。

本目录是 `server/` 下放行的资源源码路径；`mtaserver.conf` / `acl.xml` 由 `.gitignore` 另行显式放行。其他官方或第三方资源请放在 `resources/` 的其他位置。
