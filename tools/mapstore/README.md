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

# 不碰 zip：扫描 maps/ 下已有的目录，补 _files.txt 并重建索引（手动解压时用）
node tools/mapstore/build-library.mjs --reindex
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
| `--reindex` | 不碰 zip：扫描 `maps/<id>/` 已有目录，补 `_files.txt` 并重建索引 |

## 别人克隆仓库后：把自己的一堆 zip 变成可用地图库

仓库是源码仓库，`maplib/maps/` 和 `index.json` 都不入库。克隆后地图池默认是 0 张，需要用自己的 zip 跑一次本脚本。

前提（完整步骤见仓库根 `README.md`）：

1. 装好 MTA 服务端本体（仓库不含 `MTA Server.exe` 和 DLL）
2. 构建 CEF UI（`rst_ui/ui/` 不入库）：
   ```bash
   cd cef && pnpm install --frozen-lockfile && pnpm build && cd ..
   ```
3. 安装地图元数据（可选；不装也能玩，但下载量 / 上传日期为空）：
   ```bash
   node tools/mtavault/install-mapmeta-db.mjs
   ```

然后：

```bash
# 默认从 server/mods/deathmatch/map-cache/zips/*.zip 读取；
# 每个 zip = 一张 MTA 地图资源，文件名（去掉 .zip）就是地图 id
node tools/mapstore/build-library.mjs

# 自己的 zip 放在别处也行
node tools/mapstore/build-library.mjs --zips "D:\maps\zips"

# 老布局：zip 已经堆在 resources/ 里，边展开边搬走
node tools/mapstore/build-library.mjs --zips server/mods/deathmatch/resources --move-zips server/mods/deathmatch/map-cache/zips
```

展开完检查 `maplib/build-report.json`：

- `invalid`：`meta.xml` 引用了不存在的文件，不会进地图池；修好 zip 后
  `node tools/mapstore/build-library.mjs --only <id> --force` 重跑
- `failures`：解压失败（坏 zip / 权限），同样修好后重跑

ACL：仓库里的 `server/mods/deathmatch/acl.xml` 已经带 `createResource` /
`deleteResource` / `refreshResources` 权限；如果安装官方服务端时被覆盖，跑：

```bash
node tools/setup-map-acl.mjs --check  # 只检查
node tools/setup-map-acl.mjs          # 幂等补齐
```

最后**重启服务端**（索引只在启动时读一次），日志里应出现：

```text
[MAPSTORE] 地图库 N 张可玩，运行槽位 rst_map，按需复制
```

F2 地图池的数量应该和 `index.json` 里的可玩地图数一致。

注意：

- 一个 zip 只能是一张地图资源；「一个 zip 里装很多张图」的整合包要先拆开
- 地图 id 来自 zip 文件名，改 id 等于换图，旧 id 的游玩记录/成绩不会自动跟过去
- 自定义地图（不在 mtavault seed 里）照样能进池、能玩，但下载量是 0、上传日期为空；
  按上传日期过滤时这类图会被排除，热度仍会随服务器内游玩次数增长
- 全量地图库约 36 GB，不要提交到 git；zip 备份建议留在 `map-cache/zips/`（已忽略）
## 常见问题

### 这一步是必须的吗？

**索引是必须的，脚本不是。** 服务器只认两样东西：

- `maplib/maps/<id>/` 里的地图文件（根目录要有 `meta.xml`）
- `maplib/index.json`（地图池索引）
- 每张图还需要 `_files.txt`（换图时 `rst_ui` 按它复制文件）

`build-library.mjs` 是最省事的生成方式；手动解压见下一节，用 `--reindex` 补齐。

### 同一条命令跑两次会怎样？会覆盖吗？

不会覆盖，默认是幂等的：

- 已经展开过（`maps/<id>/meta.xml` + `_files.txt` 都在）的图会**跳过解压**，只重新校验 `meta.xml`
  引用、重算索引；日志里显示「重算」而不是「展开」
- 想强制重新解压（zip 更新了 / 目录坏了）：加 `--force`，会先删掉 `maps/<id>/` 再展开
- zip 已经不在了、但 `maps/<id>/` 还在：索引条目保留，不会因为 zip 没了就删图
- `maps/<id>/` 被手动删了：下次运行时对应索引条目会被清掉
- `index.json` / `build-report.json` 每次运行都会重写（报告是本次结果，不是追加）

### 别人想手动解压，放哪？

把每个 zip 解压到：

```text
server/mods/deathmatch/resources/[rst]/maplib/maps/<地图id>/
  meta.xml                ← 必须在这个目录根部
  xxx.map
  其它模型 / 贴图 / 脚本
```

然后跑一次：

```bash
node tools/mapstore/build-library.mjs --reindex
```

它会扫描 `maps/` 下所有带 `meta.xml` 的目录，自动生成 `_files.txt` 和 `index.json`，
不需要任何 zip。地图 id 就是目录名，之后想改 id 直接改目录名再 `--reindex` 即可。

如果连脚本都不想跑，手动维护也行，但要满足：

- `_files.txt`：每行一个相对 `maps/<id>/` 的文件路径（如 `meta.xml`、`xxx.map`、`textures/a.txd`）
- `index.json` 的 `maps` 数组里加一条：
  ```json
  {
    "id": "my-map",
    "name": "[DM] My Map",
    "author": "Me",
    "map": "my-map.map",
    "dimension": 0,
    "bytes": 12345678,
    "files": 42,
    "valid": true
  }
  ```
  `map` 必须是 `meta.xml` 里 `<map src="...">` 的文件名；`valid: false` 的条目会被跳过。

推荐还是用 `--reindex`，省得手写漏文件。

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
- `--zips` 指向的 zip 只是备份 / 源包，运行时不用；本机实测 zip 约 25.6 GB、展开库约 36 GB，
  两份都留约 61.6 GB。磁盘紧就用 `--delete-zips` 只留展开库，或 `--move-zips` 挪到外置盘
- zip 备份建议留在 `server/mods/deathmatch/map-cache/zips/` 或 `MAP_BACKUP_DIR`
- 运行槽位 `resources/rst_map` 由 `rst_ui` 自己创建和维护，不要手工编辑
- 客户端只会下载当前被选中的那张地图
- 玩过的地图会在 `resource-cache/http-client-files/` 留下客户端文件缓存，长期换图会慢慢变大；
  停服后删掉整个目录即可，MTA 会按需重建
- 2026-11-16 实测 4486 张 zip 里 4482 张可玩，4 张 `meta.xml` 引用了不存在的文件
  （`atlas`、`foggy-swamp`、`just-cant-map-x4`、`transformers`），已从地图池排除
