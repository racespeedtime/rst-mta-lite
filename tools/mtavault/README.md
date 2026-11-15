# mtavault 地图元数据与地图备份

这个目录只做三件事：

1. 抓取 mtavault 的公开地图元数据
2. 生成/维护地图元数据 SQLite
3. 可选地下载地图 zip 到仓库外做备份

它不参与服务器启动，也不会自动抓取或自动下载。

## 三份数据的区别

| 文件 | 是否在 Git | 作用 |
| --- | --- | --- |
| `rst_ui/mapmeta-catalog.json` | 是 | 4509 张 DM/HDM 元数据快照，服务端首次启动自动导入 SQLite |
| `tools/mtavault/seed/rst_ui_mapmeta.db` | 是 | 只读 seed 数据库，可选快捷安装 |
| `server/mods/deathmatch/databases/global/rst_ui_mapmeta.db` | 否 | 运行时 SQLite，由服务端自动生成 |

关系：

```text
mapmeta-catalog.json
        │ 首次启动自动导入
        ▼
rst_ui_mapmeta.db  ← 可选：seed DB 直接复制过来
        │ MapMeta.get() 查询
        ▼
地图详情：封面 / YouTube / 来源 / 下载量 / 难度 / 标签
```

数据库只存 **mtavault 公开元数据**，不存地图本体，也不存账号/玩家记录。

## 克隆仓库后要做什么

普通开服**不需要手动处理这个数据库**。

服务端第一次启动时：

```lua
MapMeta.init()
→ 打开 server/mods/deathmatch/databases/global/rst_ui_mapmeta.db
→ 不存在就创建
→ 检测 map_meta 表是否为空
→ 从 mapmeta-catalog.json 导入 4509 条数据
```

之后 `MapRegistry` 查询地图详情时直接读 SQLite。

所以新克隆的仓库：

```text
git clone
安装 MTA 服务端
安装 Node/pnpm 并构建 UI
放入地图 zip
启动服务器
```

元数据会自动就绪，不需要跑任何 mtavault 脚本。

### 可选：直接用 seed DB

如果不想等首次导入：

```bash
node tools/mtavault/install-mapmeta-db.mjs
```

目标：

```text
server/mods/deathmatch/databases/global/rst_ui_mapmeta.db
```

已存在时：

```bash
node tools/mtavault/install-mapmeta-db.mjs --force
```

seed DB 和 catalog 内容相同，二者选一即可。

### 想重建数据库

停止服务器，删除：

```text
server/mods/deathmatch/databases/global/rst_ui_mapmeta.db
```

下次启动会重新从 catalog 导入。

## 地图本体和元数据是两回事

装了 4509 条元数据，不代表 4509 张地图已经可玩。

- 元数据：告诉 UI 这张图叫什么、作者是谁、封面是什么
- 地图 zip：真正包含 `meta.xml`、`.map`、模型和脚本

地图 zip 需要单独放到：

```text
server/mods/deathmatch/resources/
```

MTA 支持 zip resource，不需要解压。资源名就是 zip 文件名去掉 `.zip`。

客户端只会下载当前被选中的地图，不会因为元数据有 4509 条就全部下载。

## 脚本

### 全量 DM / HDM 元数据 → catalog

```bash
node tools/mtavault/fetch-mapmeta.mjs
```

分别抓 DM / HDM，按 map id 合并去重，写入：

```text
server/mods/deathmatch/resources/[rst]/rst_ui/mapmeta-catalog.json
```

截至 **2026-11-15**：

```text
DM  = 4509
HDM =   15
合并 = 4509（HDM 同时带 DM 标签）
```

这个脚本只抓元数据，不下载地图。

### 底层抓取脚本

```bash
# 只抓 DM 元数据到 output/
node tools/mtavault/fetch-dm-maps.mjs

# 抓 HDM
node tools/mtavault/fetch-dm-maps.mjs --tag HDM

# 指定输出
node tools/mtavault/fetch-dm-maps.mjs --out tools/mtavault/output/dm-maps.json
```

输出目录默认被 `.gitignore` 忽略。

`fetch-mapmeta.mjs` 是它的封装：自动跑 DM + HDM 并合并成 catalog。

### 顺序下载地图 zip 备份

```bash
# 默认代理 http://127.0.0.1:7890
node tools/mtavault/download-all-maps.mjs
```

行为：

- 读取 `mapmeta-catalog.json`
- 顺序下载，不并行
- 走代理
- 先写 `.part`
- Python `zipfile` 校验完整性和 `meta.xml` / `.map`
- 校验通过才改名为正式 `.zip`
- 记录 SHA-256 到 `manifest.json`
- 已存在的有效 zip 自动跳过，可断点续传

需要 Python 3；Windows 下确保 `python` 命令可用，或者设置 `PYTHON` 环境变量指向 `python.exe`。

输出目录默认在仓库外，用环境变量指定：

```bash
set MAP_BACKUP_DIR=D:\maps\mtavault-dm-hdm
set MAP_PROXY=http://127.0.0.1:7890
node tools/mtavault/download-all-maps.mjs
```

这些 zip 是给网盘备份用的，**不放进 Git**，也不等于已经安装到服务器。

### 安装 seed DB

```bash
node tools/mtavault/install-mapmeta-db.mjs
node tools/mtavault/install-mapmeta-db.mjs --force
```

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
