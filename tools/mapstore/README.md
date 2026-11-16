# tools/mapstore

把 mtavault 地图 zip 展开成「按需地图库」，让 MTA 开服不必加载 4486 个地图 resource。

## 为什么需要

MTA 服务端启动时会加载 `server/mods/deathmatch/resources/` 下的每个 resource，并在
`CResource::Load()` 里对 `meta.xml` 声明的每个文件算 MD5（`GenerateChecksums`）；
zip resource 还会先把整包解压到 `resource-cache/unzipped`，并且每次启动都按 CRC 复查。

4486 张地图约 26 GB。把它们当作 4486 个 resource 摆着，每次开服都要读 26 GB：

- 2026-11-16 实测：启动 145 秒只处理到字母 E（约 1168 张），全量预计 8 分钟以上
- `resource-cache/unzipped` 会额外占 18 GB

所以地图文件平时放在 `[rst]/maplib` 这个「数据 resource」里（它的 `meta.xml` 不声明
任何文件，MTA 启动只读一个 meta），换图时由 `rst_ui` 把选中的那张图复制进运行槽位
`resources/rst_map`，再 `refreshResources` + `startResource`。

改成按需装载后实测（2026-11-16，本机 NVMe）：

| 项目 | 耗时 |
| --- | --- |
| 开服到 `Server started` | 0.65 秒（3 个 resource） |
| 装载一张 24 MB / 56 文件的地图 | 1.9–2.8 秒（复制 + refresh 校验 + 启动） |
| 换一张 12 MB / 49 文件的地图 | 2.1 秒 |

## 用法

```bash
# 默认：从 server/mods/deathmatch/map-cache/zips/*.zip 展开
node tools/mapstore/build-library.mjs

# 迁移：把 resources/ 里已堆着的 zip 边展开边搬走（同盘改名，很快）
node tools/mapstore/build-library.mjs \
  --zips server/mods/deathmatch/resources \
  --move-zips server/mods/deathmatch/map-cache/zips

# 只补几张 / 重做几张
node tools/mapstore/build-library.mjs --only a-new-dawn,silent-hill --force

# 只重建索引（zip 已搬走、目录还在；会重新校验 meta 引用）
node tools/mapstore/build-library.mjs --zips server/mods/deathmatch/map-cache/zips
```

参数：

| 参数 | 说明 |
| --- | --- |
| `--zips <dir>` | zip 目录，默认 `server/mods/deathmatch/map-cache/zips` |
| `--out <dir>` | 地图库目录，默认 `server/mods/deathmatch/resources/[rst]/maplib` |
| `--only <a,b>` | 只处理指定地图 id |
| `--limit <n>` | 只处理前 n 张 |
| `--force` | 已展开的目录也重新解压 |
| `--move-zips <dir>` | 展开成功后把 zip 移到该目录（迁移用） |
| `--delete-zips` | 展开成功后删除源 zip（危险） |

## 输出

```text
server/mods/deathmatch/resources/[rst]/maplib/
  meta.xml                 ← 入库，不声明任何文件
  index.json               ← 地图池索引（不入库）
  build-report.json        ← 无效 / 失败清单（不入库）
  maps/<map-id>/           ← 展开后的地图文件（不入库）
    meta.xml
    _files.txt             ← 文件清单，rst_ui 换图时按它复制
    ...
```

`index.json` 每条：

```json
{
  "id": "a-new-dawn",
  "name": "[DM] Nice v10 - A New Dawn",
  "author": "*Nice^^",
  "map": "----Dawn3Original.map",
  "dimension": 0,
  "bytes": 24305355,
  "files": 56,
  "valid": true
}
```

`valid: false` 的地图（`meta.xml` 引用了不存在的 `<map>` / `<file>` / `<script>` 等）
不会进地图池，原因写进 `build-report.json`。修好 zip 后重跑一次即可，已展开的图会跳过。

## 注意

- 地图库很大（全量约 36 GB），不要提交到 git；`.gitignore` 已忽略 `maps/`、`index.json`
- zip 备份建议留在 `server/mods/deathmatch/map-cache/zips/` 或 `MAP_BACKUP_DIR`
- 运行槽位 `resources/rst_map` 由 `rst_ui` 自己创建和维护，不要手工编辑
- 客户端只会下载当前被选中的那张地图
- 玩过的地图会在 `resource-cache/http-client-files/` 留下客户端文件缓存，长期换图会慢慢变大；
  停服后删掉整个目录即可，MTA 会按需重建
- 2026-11-16 实测 4486 张 zip 里 4482 张可玩，4 张 `meta.xml` 引用了不存在的文件
  （`atlas`、`foggy-swamp`、`just-cant-map-x4`、`transformers`），已从地图池排除
