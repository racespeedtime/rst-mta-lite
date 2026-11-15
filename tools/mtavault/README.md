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

地图 zip 放到：

```text
server/mods/deathmatch/resources/
```

MTA 支持 zip resource，不需要解压。资源名就是 zip 文件名去掉 `.zip`。

客户端只下载当前被选中的地图。

## 脚本

### 安装运行时 DB

```bash
node tools/mtavault/install-mapmeta-db.mjs
node tools/mtavault/install-mapmeta-db.mjs --force
```

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

- 并发下载，默认 4 个 worker
- 默认代理 `http://127.0.0.1:7890`
- 先写 `.part`
- 失败的 `.part` 会保留，下一次运行继续尝试
- 支持 HTTP Range 时用 `curl -C -` 续传；源站不支持 Range 会自动从头下载
- Python `zipfile` 校验完整性和 `meta.xml` / `.map`
- 校验通过后才改名为正式 `.zip`
- 记录 SHA-256 到 `manifest.json`
- 已存在的有效 zip 自动跳过

环境变量：

```bash
set MAP_BACKUP_DIR=D:\maps\mtavault-dm-hdm
set MAP_PROXY=http://127.0.0.1:7890
set MAP_CONCURRENCY=4
set PYTHON=C:\Python312\python.exe
node tools/mtavault/download-all-maps.mjs
```

并发数范围 `1-16`。代理或源站不稳定时建议先用 3-4，确认速度后再提高。

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
- 封面是远程 URL；MTA CEF local 模式对外网图片支持有限，不保证所有封面都能显示
- 地图 zip 的可用性取决于源站；下载脚本只保证 zip 结构完整
- 4509 条元数据不等于 4509 张地图已经安装
