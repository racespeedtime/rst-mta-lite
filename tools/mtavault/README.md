# mtavault 地图元数据与工具

这个目录负责 mtavault 地图元数据的抓取、数据库安装和可选的本地地图下载。

元数据来源：

```text
https://mtavault.com
```

地图模型、贴图、脚本和地图本身的版权属于各自作者。**本仓库不提供任何地图文件、完整地图包或网盘链接。**

服务器运行时**只读 SQLite**，不再读取 JSON catalog。

## 数据库只有两份

| 文件 | 是否在 Git | 作用 |
| --- | --- | --- |
| `tools/mtavault/seed/rst_ui_mapmeta.db` | 是 | 只读 seed DB，4509 张 DM/HDM 元数据 |
| `server/mods/deathmatch/databases/global/rst_ui_mapmeta.db` | 否 | 运行时 DB，从 seed 安装出来 |

关系：

```text
tools/mtavault/seed/rst_ui_mapmeta.db
        │ install-mapmeta-db.mjs
        ▼
server/mods/deathmatch/databases/global/rst_ui_mapmeta.db
        │ MapMeta.get()
        ▼
地图详情：封面 / 作者 / 来源 / 下载量 / 难度 / 标签
```

运行时 DB 只包含地图展示元数据，不包含：

- 地图本体
- 账号
- 玩家记录
- 服务器游玩次数

## 克隆仓库后要做什么

安装一次元数据库：

```bash
node tools/mtavault/install-mapmeta-db.mjs
```

目标：

```text
server/mods/deathmatch/databases/global/rst_ui_mapmeta.db
```

如果目标已存在：

```bash
node tools/mtavault/install-mapmeta-db.mjs --force
```

然后正常启动服务端即可。

服务端不会自动从 JSON 导入。没有安装 DB 时：

- 服务器仍能启动
- 地图仍能玩
- 地图详情里的封面、作者、下载量等元数据为空
- 日志会提示：

```text
[MAPMETA] metadata DB is empty; run: node tools/mtavault/install-mapmeta-db.mjs
```

## 地图本体和元数据是两回事

元数据库有 4509 条记录，只代表 UI 能显示这些地图的信息。

本仓库不附带任何地图文件。真正可玩的地图 zip 需要自行获取：

- 找其他人打包的完整包
- 在 mtavault 按需下载单张地图
- 使用自己的地图备份

使用或再分发地图前请确认作者授权。

地图 zip **不要**直接堆进 `resources/`：MTA 启动时会加载每个 resource 并对其
`meta.xml` 声明的文件算 MD5，4486 张地图约 26 GB，会让开服从几秒变成十几分钟。

放到备份目录，再展开成按需地图库：

```text
server/mods/deathmatch/map-cache/zips/    ← zip（download-all-maps.mjs 默认输出在外面，可搬进来）
server/mods/deathmatch/resources/[rst]/maplib/   ← 展开后的地图库 + index.json
```

```bash
node tools/mapstore/build-library.mjs
```

说明见 `tools/mapstore/README.md`。

客户端只下载当前被选中的地图。

## 脚本

### 安装运行时 DB

```bash
node tools/mtavault/install-mapmeta-db.mjs
node tools/mtavault/install-mapmeta-db.mjs --force
```

### 从最新 catalog 增量更新运行时 DB

`install-mapmeta-db.mjs` 只复制仓库里的 seed，不会把 `fetch-mapmeta.mjs` 的新结果写进去。同步新增地图后用：

```bash
node tools/mtavault/build-mapmeta-db.mjs
# 或指定文件
node tools/mtavault/build-mapmeta-db.mjs \
  --catalog tools/mtavault/output/mapmeta.json \
  --db server/mods/deathmatch/databases/global/rst_ui_mapmeta.db
```

行为：

- 按 `mtavault_id` upsert，不删除任何行
- 保留已有的 `resource` 映射，手工维护的第三方地图行不会被覆盖
- 数据库不存在时先复制 seed，再写入 catalog
- 建议停服后运行，避免 SQLite 写入竞争

### 抓取最新元数据（开发用）

```bash
node tools/mtavault/fetch-mapmeta.mjs
```

输出：

```text
tools/mtavault/output/mapmeta.json
```

这个 JSON 只用于人工检查或给下载脚本读取，**不参与服务器启动**，也不会被 `rst_ui` 读取。运行时数据库直接使用仓库里的 seed DB。

底层脚本：

```bash
node tools/mtavault/fetch-dm-maps.mjs
node tools/mtavault/fetch-dm-maps.mjs --tag HDM
```

截至 **2026-11-15**：

```text
DM  = 4509
HDM =   15
合并 = 4509（HDM 同时带 DM 标签）
```

这里说的是**元数据条数**，不是能下载到的数量：2026-11-16 实测 4509 条里 **4486 张**源站有文件，另 **23 张**只有元数据（`versions: 0`，下载端点返回 HTTP 500），清单见下面「已知：23 张源站缺文件」。

### 按需下载地图 zip（可选）

```bash
node tools/mtavault/download-all-maps.mjs
```

下载列表来自：

```text
tools/mtavault/output/mapmeta.json
```

所以第一次使用前先运行一次 `fetch-mapmeta.mjs`。

行为：

- 并发下载，默认 8 个 worker（范围 1-24）
- 默认代理 `http://127.0.0.1:7890`，`--proxy off` 可直连
- 先写 `.part`，校验通过后才原子改名为正式 `.zip`
- 失败保留的 `.part` 下次会续传；源站不支持 Range 时自动关闭续传，不再每个文件白吃一次 `curl (33)`
- 只依赖 Node 内置模块（`node:zlib` 解析 zip），**不需要 Python**
- 校验 zip 结构和 `meta.xml` / `.map`；下载完成后逐条解压做 CRC 校验
- 记录 SHA-256 到 `manifest.json`（临时文件 + rename 原子写，写入中断不会留下坏 JSON）
- 已有 zip 默认只读中央目录快速校验；确实损坏时重命名为 `*.zip.bad-<时间戳>` 隔离，**不删除**
- 失败按类型重试：网络抖动重试 3 次，404/410 与持续 5xx 记为 `unavailable`，不阻塞其它地图

常用参数：

| 参数 | 说明 |
| --- | --- |
| `--out <dir>` | 备份目录，等价于 `MAP_BACKUP_DIR` |
| `--catalog <file>` | 指定 `mapmeta.json` |
| `--concurrency <n>` | 并发数 1-24 |
| `--proxy <url\|off>` | 代理，`off` 直连 |
| `--max-time <秒>` | 单文件下载上限，默认 1800 |
| `--only-missing` | 只补缺失文件，已有 zip 不校验、不改动、不重下 |
| `--verify` | 只校验已有 zip |
| `--verify --full` | 逐条解压做 CRC 全量校验 |
| `--deep` | 已有 zip 额外核对 manifest 里的 sha256 |

环境变量：

```bash
set MAP_BACKUP_DIR=D:\maps\mtavault-dm-hdm
set MAP_PROXY=http://127.0.0.1:7890
set MAP_CONCURRENCY=8
node tools/mtavault/download-all-maps.mjs
```

并发数范围 `1-24`。实测 16 左右吞吐最好，再往上反而下降；代理或源站不稳定时先用 4-8。

日常补漏和体检：

```bash
node tools/mtavault/download-all-maps.mjs --only-missing
node tools/mtavault/download-all-maps.mjs --verify
```

`manifest.json` 结构：`downloaded`（含 `bytes` / `sha256`）、`skipped`、`failed`（可重试）、`unavailable`（源站缺失，含 HTTP 状态和时间）。

#### 已知：23 张源站缺文件

2026-11-16 实测，下列地图在 mtavault 有元数据，但下载端点返回 HTTP 500（对应 `versions: 0`，即没有可下载的文件版本），不是本地漏下，也不是网络问题。源站补档后跑一次 `--only-missing` 就能自动补进来；新脚本会把它们记进 `manifest.json` 的 `unavailable`，不再混进 `failed` 反复重试。

| slug | 地图 | 作者 | 元数据记录大小 |
| --- | --- | --- | --- |
| `acheron` | Acheron | Gabcho | 4.4 MB |
| `accelera` | Accelera | YigithaN, Shahriar | 4.9 MB |
| `breaking-outta-heights` | Breaking Outta Heights | Moamen, Bunta | 5 MB |
| `coast-away` | Coast Away | iRaven | 5.1 MB |
| `coliseum-of-teleport` | Coliseum Of Teleport | Sasuke | 51 KB |
| `collective-of-plenty` | Collective Of Plenty | Nebla | 13.4 MB |
| `existential-dread` | Existential Dread | Conquer | 7.2 MB |
| `frostopia-2088` | Frostopia 2088 | Nebla | 13.6 MB |
| `in-the-rain` | In The Rain | Straim | 8.9 MB |
| `kls-cinnamon` | Cinnamon | KLS | 8 MB |
| `lacrimosa` | Lacrimosa | Kanzy | 6.3 MB |
| `mindblow` | Mindblow | beatZ, UnDeR | 11.1 MB |
| `mona-lisa-overdrive` | Mona Lisa Overdrive | hUGAOXD, nX_ | — |
| `98-octane` | 98 Octane | Canky | 3.8 MB |
| `natlan` | Natlan | Nebla | 10.6 MB |
| `no-escape` | No Escape | Sasuke | 45 KB |
| `rain-ii` | Rain II | Straim | 5 MB |
| `ronova` | Ronova | Nebla | 6.2 MB |
| `skirk` | Skirk | Nebla | 7.2 MB |
| `skilled-stuntplane-iii` | Skilled Stuntplane III | Gerc, Pablow | 9.8 MB |
| `the-lost-kingdom` | The Lost Kingdom | Kalkbrenner | 22 MB |
| `unstable-forwards` | Unstable Forwards | NaGaFo | 9.2 MB |
| `wff-mowin-this-shit` | WFF Mowin This Shit (4/500) | Conquer | 37.3 MB |

这些 zip 只下载到本机，**不随仓库提供，也不放进 Git**。下载和再分发前请确认作者授权与 mtavault 使用条款。

### 扫描已安装地图

```bash
node tools/mtavault/scan-maps.mjs \
  --root server/mods/deathmatch/resources \
  --out server/mods/deathmatch/map-cache/map-catalog.json
```

这是人工检查报告，不是运行时地图格式，`rst_ui` 不读取。

## 数据库结构

`map_meta` 主要字段：

- `mtavault_id`
- `resource`
- `name` / `name_norm`
- `authors` / `author_norm`
- `file_name` / `file_name_norm`
- `cover`
- `youtube`
- `source_url`
- `uploaded_at`
- `downloads`
- `difficulty`
- `file_size`
- `tags`
- `map_type`（DM / HDM）

`MapRegistry` 启动时只读地图 `meta.xml`；`.map` 的 spawn / pickup / finish 在选中地图时才解析。SQLite 只负责展示元数据，不参与地图元素创建。

## 限制

- API 或字段结构可能变化
- 全量抓取请控制频率
- 封面源是远程 URL；运行时由服务端 `CoverCache` 缓存并转 data URI 下发给 CEF，客户端不直接访问外网图片
- 地图 zip 的可用性取决于源站；下载脚本只保证 zip 结构完整
- 4509 条元数据不等于 4509 张地图已经安装
