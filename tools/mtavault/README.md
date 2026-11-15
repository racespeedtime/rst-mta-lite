# mtavault 地图元数据

从 `mtavault.com` 的公开 API 获取 DM / HDM 赛道元数据。**脚本只手动运行，不接进服务器启动流程，也不会自动抓取。** 只抓元数据，不下载地图本体。

## 全量 DM / HDM → SQLite

生成服务端使用的 `mapmeta-catalog.json`：

```bash
node tools/mtavault/fetch-mapmeta.mjs
```

它会分别抓 `DM` / `HDM`，按 map id 合并去重，写到：

```text
server/mods/deathmatch/resources/[rst]/rst_ui/mapmeta-catalog.json
```

服务端首次启动时把 catalog 导入 SQLite 的 `map_meta` 表；之后 `MapRegistry.get()` 按地图 resource 懒查询，不再读大 JSON。

仓库还带一份只读 seed DB：

```text
tools/mtavault/seed/rst_ui_mapmeta.db
```

安装到 MTA 运行目录：

```bash
node tools/mtavault/install-mapmeta-db.mjs
# 已存在时覆盖
node tools/mtavault/install-mapmeta-db.mjs --force
```

目标：

```text
server/mods/deathmatch/databases/global/rst_ui_mapmeta.db
```

这个 DB 只包含 mtavault 公开元数据，不包含账号/玩家记录。运行时数据库仍然被 `.gitignore` 忽略，仓库只保留 seed。

当前抓取结果：

```text
DM  = 4509
HDM =   15
合并 = 4509（HDM 同时带 DM 标签）
```

不下载封面、不下载地图。封面使用 mtavault/YouTube 的远程 `coverUrl`；本地 `covers/` 只作为已有资源保留。

## 为什么走 API

mtavault 是 Nuxt 前端，直接解析网页会很脆弱。站点前端配置里暴露了：

- API：`https://api.mtavault.com`
- 图片：`https://assets.mtavault.com`
- 下载：`https://dl.mtavault.com`

实际使用的接口是：

```text
GET https://api.mtavault.com/maps?page=1&size=100&sort=downloads&direction=-1
```

返回 `data.maps[]` 和 `data.totalItems`。列表接口已经带了作者、标签、上传时间、下载量、文件信息等字段，不需要对每张图再请求详情。

## 用法

在仓库根目录：

```bash
# 只抓元数据，输出 JSON
node tools/mtavault/fetch-dm-maps.mjs

# 指定输出
node tools/mtavault/fetch-dm-maps.mjs --out tools/mtavault/output/dm-maps.json

# 同时下载封面到本地
node tools/mtavault/fetch-dm-maps.mjs --cover-dir tools/mtavault/output/covers

# 调试：只抓两页
node tools/mtavault/fetch-dm-maps.mjs --max-pages 2 --page-size 20
```

可选参数：

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `--out` | `tools/mtavault/output/dm-maps.json` | 输出文件 |
| `--cover-dir` | 空 | 给了才下载封面 |
| `--cover-limit` | `0` | 最多下载多少张封面，0 不限 |
| `--page-size` | `100` | 分页大小 |
| `--max-pages` | `0` | 最多抓多少页，0 全量 |
| `--delay` | `150` | 请求间隔毫秒 |
| `--tag` | `DM` | 过滤标签 |
| `--api-base` | `https://api.mtavault.com` | API 地址 |
| `--retries` | `3` | 请求重试次数 |
| `--timeout` | `20000` | 单次请求超时毫秒 |
| `--proxy` | 读 `HTTPS_PROXY` | 封面下载代理，如 `http://127.0.0.1:7890` |

输出目录默认被 `.gitignore` 忽略，元数据和封面不会进源码仓库。

## 输出结构

```json
{
  "source": "mtavault",
  "apiBase": "https://api.mtavault.com",
  "fetchedAt": "2026-11-15T00:00:00.000Z",
  "filter": { "tag": "DM" },
  "sourceTotal": 4548,
  "count": 0,
  "maps": [
    {
      "id": "6af0fd1423c27a890aa5abee",
      "name": "The Reaping",
      "authors": ["YuRi"],
      "uploadedAt": "2026-11-08",
      "popularity": 400,
      "difficulty": "Intermediate",
      "fileSize": 9293667,
      "tags": ["DM", "No Deco", "Custom Models"],
      "fileName": "[DM]YuRi_The_Reaping",
      "sourceUrl": "https://mtavault.com/map/the-reaping",
      "coverUrl": "https://img.youtube.com/vi/dwk3Yo1KJvI/hqdefault.jpg",
      "coverLocal": null
    }
  ]
}
```

刻意没有抓：长描述、评论、版本历史、奖励、上传者资料、`meta` 里的物件统计等。

## DM 判定

API 列表没有精确的“模式”过滤参数，脚本会拉取全量后按以下任一条件判定：

- `tags` 里有 `DM`（大小写不敏感）
- `fileName` 或 `name` 里有 `[DM]`

`--tag` 可以改成别的标签复用。

## 封面

列表接口没有封面字段；脚本用 `videoURL`（YouTube 视频 ID）生成缩略图地址：

```text
https://img.youtube.com/vi/<videoId>/hqdefault.jpg
```

没有视频的地图 `coverUrl` 为 `null`。

**CEF 限制**：MTA 的 CEF 是 local 模式，不能直接加载外网图片。`--cover-dir` 会把封面下载为本地 JPEG，输出 `coverLocal` 相对路径；后续接入 UI 时需要：

1. 把封面文件放进资源目录
2. 在 `meta.xml` 里登记这些文件（或用构建脚本生成登记）
3. 前端用本地 `./covers/<id>.jpg` 路径

目前没有把封面接进 UI，先保留数据。

封面走 `img.youtube.com`。在需要代理的网络里，Node `fetch` 可能 `ECONNRESET`，脚本会回退到 `curl`；用 `--proxy http://127.0.0.1:7890` 或设置 `HTTPS_PROXY` 即可（本机已用这种方式验证单张封面下载）。

## 下载地图本体

元数据里的 `seoFriendlyURL` 也用于下载：

```text
https://dl.mtavault.com/map/<seoFriendlyURL>
```

返回的是 MTA 资源压缩包，解压后根目录直接是 `meta.xml` + `.map` + 资源文件。

已下载并安装的 3 张图（按下载量降序）：

| 资源名 | 源站地图 | 下载量 | 压缩包 |
| --- | --- | ---: | ---: |
| `mtavault_silent_hill` | Silent Hill | 400 | 9.1 MB |
| `mtavault_a_new_dawn` | A New Dawn | 364 | 17.2 MB |
| `mtavault_descendants_skills_v` | Descendant's Skills V | 341 | 10.2 MB |

安装位置：

- 原包缓存：`server/mods/deathmatch/map-cache/`（忽略）
- 解压后的资源：`server/mods/deathmatch/resources/mtavault_*/`（忽略）
- 扫描结果：`server/mods/deathmatch/map-cache/map-catalog.json`（忽略）；仅用于人工检查，不是运行时地图格式，`rst_ui` 不会读取它

这三张图当前只安装、不自动 `start`；`rst_ui` 自己还没有地图资源生命周期管理。

## 扫描已安装地图

```bash
node tools/mtavault/scan-maps.mjs \
  --root server/mods/deathmatch/resources \
  --out server/mods/deathmatch/map-cache/map-catalog.json   # 仅检查报告，不是运行时格式
```

扫描内容：

- `meta.xml` 的 `info`、`map`、`settings`
- `.map` 的 spawnpoint 坐标 / 车型、checkpoint 数量
- vehicle / racepickup / marker / object 数量
- `hasFinishData`：是否真的有 checkpoint

当前 3 张图的结果：

```text
3 maps, 0 with checkpoints, 3 with Hunter finish
spawnpoints: 1 / 1 / 2
markers: 31 ~ 41（arrow / corona / cylinder，视觉箭头，不是 checkpoint）
racepickup: 35 ~ 62（nitro / repair）
settings: ghostmode=true, vehicleweapons=true, duration=1800, respawn=none
```

Hunter 终点候选（`racepickup type="vehiclechange" vehicle="425"`）：

| 地图 | Hunter 数量 | 终点坐标（中心） |
| --- | ---: | --- |
| Silent Hill | 1 | `1524.6, 3812.6, 8.4` |
| A New Dawn | 3 | `6877.4, -828.0, 1.3` |
| Descendant's Skills V | 2 | `6940.9, 291.6, 332.9` |

结论：它们是车辆 DM / 技巧图，不是带 checkpoint 的竞速图；但终点通常用 Hunter `vehiclechange` pickup 标记，可以把它的坐标当成 `finish`。没有 Hunter 时只能退回“远离起点”的进度估算。

## 热点与服务器游玩次数

- 抓取时 `popularity = downloads`（源站热度）
- 服务端实际排序用「有效热度」：

```text
有效热度 = 配置里的基础热度（可写入抓取结果） + 服务器内游玩次数 × playPopularityWeight
```

- 游玩次数由 `server/mapstats.lua` 持久化到 SQLite（`rst_ui_mapstats.db`）
- 每次回合开始 `+1`，重启不丢
- 权重在 `shared/config.lua` 的 `playPopularityWeight` 调整

## 限制

- 这里只抓**元数据**，不下载地图资源；真正把赛道跑起来还需要出生点、检查点和圈数数据
- 源站字段和接口可能变化，脚本报错时先检查 `data.maps` 结构
- 全量抓取请控制频率，遵守源站条款；默认 150ms 间隔
