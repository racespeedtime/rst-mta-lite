# rst-mta-lite

轻量 MTA:SA 竞速服务器。服务端使用 MTA Lua，客户端界面使用 CEF + Vue 3 + TypeScript + Vite。

## License 与地图版权

本项目代码和文档使用 **MIT License**，见 [LICENSE](LICENSE)。

地图展示元数据来自：

```text
https://mtavault.com
```

地图模型、贴图、脚本和地图本身的版权属于制作这些地图的作者。**本仓库不提供任何地图文件、完整地图包或网盘链接**；需要地图请自行向作者/社区获取，或在 mtavault 按需下载单张地图。使用、修改和再分发地图前请确认作者授权。

MTA:SA、GTA: San Andreas 及相关名称、资源归其各自权利人所有。

## 从零部署

这个仓库是**源码仓库**，不包含 MTA 服务端本体、地图 zip、运行时数据库、日志和 CEF 构建产物。克隆后需要手动补齐这些文件。

### 0. 环境依赖

| 依赖 | 要求 | 用途 |
| --- | --- | --- |
| Windows | Windows 10/11 x64 | MTA 服务端 / 客户端 |
| Git | 任意较新版本 | 克隆仓库 |
| Node.js | 22 LTS 或更新 | 构建 CEF UI |
| pnpm | 9+，实测 12.11.2 | 安装 / 构建前端 |
| MTA:SA Server | 1.6 | 服务端运行时 |
| MTA:SA Client | 1.6 | 玩家客户端 |
| GTA: San Andreas | 1.0 | MTA 客户端依赖 |

正常开服不需要 MySQL、Redis、Python。

### 1. 克隆仓库

```bash
git clone git@github.com:racespeedtime/rst-mta-lite.git
cd rst-mta-lite
```

没有 SSH key 时用 HTTPS：

```bash
git clone https://github.com/racespeedtime/rst-mta-lite.git
```

### 2. 手动安装 MTA 服务端

从 MTA 官网下载 **MTA:SA Server 1.6**：

```text
https://multitheftauto.com/
```

不要只复制 `MTA Server.exe`。MTA 服务端依赖根目录和 `mods/deathmatch` 下的一整套 DLL / 配置文件，必须完整保留同一版本的安装目录。

当前这套服务端实际包含：

```text
server/
  MTA Server.exe
  core.dll
  net.dll
  pthread.dll
  xmll.dll
  dumps/
  mods/
    deathmatch/
      deathmatch.dll
      dbconmy.dll
      libcrypto-3.dll
      libmysql.dll
      libssl-3.dll
      lua5.1.dll
      pcre3.dll
      mtaserver.conf
      acl.xml
      banlist.xml
      editor_acl.xml
      editor.conf
      internal.db
      registry.db
      settings.xml
      vehiclecolors.conf
      local.conf
      server-id.keys
      resources/
        [rst]/
          rst_ui/         ← 仓库自带
```

说明：

- 根目录 DLL：`core.dll`、`net.dll`、`pthread.dll`、`xmll.dll`
- `mods/deathmatch` DLL：`deathmatch.dll`、`dbconmy.dll`、`libcrypto-3.dll`、`libmysql.dll`、`libssl-3.dll`、`lua5.1.dll`、`pcre3.dll`
- `mtaserver.conf`、`acl.xml`、`banlist.xml`、`settings.xml` 等是服务端配置
- `internal.db`、`registry.db`、`server-id.keys` 是运行时文件
- 所有文件必须来自同一版本 MTA 服务端，不能混用不同版本 DLL

安装时最稳妥的做法：

1. 先把官方 MTA 服务端完整解压到临时目录
2. 把完整目录合并到仓库的 `server/`
3. 确认仓库里的 `[rst]/rst_ui` 没有被覆盖
4. 用仓库自带的 `mtaserver.conf` / `acl.xml` 覆盖官方默认文件

注意：

- `server/` 大部分文件在 `.gitignore` 中，只显式跟踪：
  - `server/mods/deathmatch/resources/[rst]/`
  - `server/mods/deathmatch/mtaserver.conf`
  - `server/mods/deathmatch/acl.xml`
- `MTA Server.exe`、DLL、`mods/deathmatch` 核心文件需要本地准备。
- `mtaserver.conf` 和 `acl.xml` 仓库已经提供默认配置，可以直接用，也可以按部署环境修改。
- 官方服务端安装包自带的配置会覆盖仓库版本，合并后要把仓库版本恢复回来。
- `libmysql.dll` 只是 MTA 服务端自带的客户端库，正常开服不需要安装 MySQL Server。

### 3. 自行准备地图文件

本仓库**不提供地图文件、地图资源包或网盘链接**。

仓库只包含 mtavault 的展示元数据，地图数据的来源是：

```text
https://mtavault.com
```

地图模型、贴图、脚本和地图本身的版权属于各自作者。使用、修改或再分发地图前，请自行确认作者授权和 mtavault 的使用条款。

地图可以按自己的需要获取：

- 向地图作者或社区寻找其他人打包的完整资源包
- 在 mtavault 上按需下载单张地图
- 使用自己的地图备份

拿到 zip 后直接放进：

```text
server/mods/deathmatch/resources/
```

MTA 支持 zip resource，**不需要解压**：

```text
resources/
  <map-name>.zip
```

要求：

- zip 根目录直接有 `meta.xml`
- 资源名就是 zip 文件名去掉 `.zip`
- 不要同时保留同名解压目录和 zip
- 不要把 `manifest.json` / `download.log` 放进 resources

截至 **2026-11-15**，mtavault DM/HDM 元数据共 **4509 张**，但这只是元数据，不代表仓库附带了 4509 张地图。

全新克隆时地图池是 **0 张**；没有放地图时服务器仍能启动，但无法开局。

### 4. 构建 CEF UI

仓库不包含 `ui/` 构建产物，必须本地构建：

```bash
# 第一次使用 pnpm 时
corepack enable
corepack prepare pnpm@12 --activate

cd cef
pnpm install --frozen-lockfile
pnpm build
```

`pnpm-lock.yaml` 是 lockfile v9；pnpm 9、10、11、12 均可，仓库当前实测 pnpm 12.11.2。不要使用过老的 pnpm 8。

输出：

```text
server/mods/deathmatch/resources/[rst]/rst_ui/ui/
```

没有这个目录时，进入服务器可能只看到空白 CEF 页面。

### 5. 配置服务端

仓库自带：

```text
server/mods/deathmatch/mtaserver.conf
```

默认配置已经包含：

```xml
<servername>rst-mta-lite</servername>
<serverport>22003</serverport>
<httpport>22005</httpport>
<maxplayers>32</maxplayers>
<fpslimit>60</fpslimit>

<!-- 启动核心资源 -->
<resource src="rst_ui" startup="1" protected="0"/>
```

可以按部署环境修改端口、服务器名和下载地址。`rst_ui` 必须保持 `startup="1"`，否则服务器启动后没有比赛逻辑。

脚本启动时也会统一设置：

```lua
setFPSLimit(60)
```

### 6. 配置地图 ACL

仓库自带：

```text
server/mods/deathmatch/acl.xml
```

其中的 `raceACLGroup` 已经包含：

```xml
<object name="resource.rst_ui"></object>
```

并授予：

- `function.startResource`
- `function.stopResource`
- `function.xmlLoadFile`

如果安装官方服务端时用官方 `acl.xml` 覆盖了仓库版本，需要恢复仓库的 `acl.xml`，或者在 MTA 管理面板批准 `rst_ui` 的地图资源权限。

也可以停止服务器后运行：

```bash
node tools/setup-map-acl.mjs
```

如果脚本提示找不到 `raceACLGroup`，需要手动把：

```xml
<object name="resource.rst_ui"></object>
```

加入拥有上述权限的 ACL group，然后重启服务器。

### 7. 安装 mtavault 元数据库

仓库**不包含运行时数据库**，只包含一份只读 seed DB：

```text
tools/mtavault/seed/rst_ui_mapmeta.db
```

安装到 MTA 运行目录：

```bash
node tools/mtavault/install-mapmeta-db.mjs
```

目标：

```text
server/mods/deathmatch/databases/global/rst_ui_mapmeta.db
```

已存在时覆盖：

```bash
node tools/mtavault/install-mapmeta-db.mjs --force
```

这个 DB 只包含地图展示元数据，不包含地图本体、账号或玩家记录。

### 8. 启动服务端

```powershell
cd server
.\MTA Server.exe
```

首次启动会自动创建：

```text
server/mods/deathmatch/databases/
server/mods/deathmatch/logs/
server-id.keys
```

日志：

```text
server/mods/deathmatch/logs/server.log
```

看到下面两行说明正常：

```text
Resources: N loaded, 0 failed
Server started and is ready to accept connections!
```

### 9. 客户端连接

安装：

- [MTA:SA Client 1.6](https://multitheftauto.com/)
- GTA: San Andreas 1.0（MTA 客户端依赖）

连接：

```text
mtasa://127.0.0.1:22003
```

远程服务器把 IP 换成公网地址，并放行：

- UDP `22003` 游戏端口
- TCP `22005` HTTP 端口

登录、注册或游客进入后会自动加入唯一比赛舞台。

### 仓库里有什么 / 需要手动补什么

| 内容 | 是否在 Git | 说明 |
| --- | --- | --- |
| `cef/` 前端源码 | 是 | 需要 `pnpm build` |
| `rst_ui/` Lua / CEF 页面 | 是 | UI 构建产物 `ui/` 除外 |
| `mapmeta` seed DB | 是 | 安装为运行时 `rst_ui_mapmeta.db` |
| `MTA Server.exe` + `core.dll` / `net.dll` / `pthread.dll` / `xmll.dll` | 否 | 官方 MTA 服务端完整安装 |
| `mods/deathmatch` 的 DLL | 否 | `deathmatch.dll`、`lua5.1.dll`、`libssl-3.dll` 等 |
| `mtaserver.conf` / `acl.xml` | 是 | 默认配置，含 `rst_ui` 启动项和地图 ACL |
| `banlist.xml` / `settings.xml` / `internal.db` | 否 | 本地配置或运行时文件 |
| `server-id.keys` | 否 | 运行时生成，不能共享 |
| 地图 zip | 否 | 本仓库不提供；自行向作者/社区获取 |
| `map-cache` / `databases` / `logs` | 否 | 运行时生成 |
| `rst_ui/ui/` | 否 | `pnpm build` 生成 |

## 玩法

1. 登录、注册或游客进入。
2. 一个服务器只有一个比赛舞台，登录后直接进入。
3. 竞技模式下，已有玩家进行中则先观战，下回合参赛；训练模式可以直接重生，也可以在观战和重生之间反复切换。
4. 训练模式默认无限倒带；竞技模式 10 条命。
5. 地图 30 分钟一轮，可发起换图投票。
6. 服务端统一限制最高 60 FPS。

### 操作

| 按键 | 功能 |
| --- | --- |
| `T` | 聊天输入 |
| `F1` | 帮助 |
| `F2` | 菜单 |
| `F3` | 临时显示 / 隐藏光标 |
| 长按 `Y` | 倒带最近 8 秒 |
| 观战 | 左上角显示正在跟随的玩家名 / 车辆；鼠标转向 · `WASD` 平移 · 左/右键切换玩家 · 空格 / Ctrl 升降；其他玩家保留头顶名字牌 |
| 菜单 | 训练模式可主动重生；观战时可直接返回训练赛道 |

训练模式的观战和重生可以反复切换；竞技模式进行中只能先观战，等下回合参赛。

竞技模式：全员准备后倒计时开始；每次倒带扣 1 命；命数耗尽转观战。

### 个人竞技 / 团队竞技

竞技模式分两种：

- **个人竞技**：按个人冲线名次计分
- **团队竞技**：红队 / 蓝队，按队伍总分结算

团队竞技规则：

- 开局前玩家在准备面板选择红队或蓝队
- 红蓝人数必须相等，且每名玩家都有队伍，才能开始倒计时
- 人数不相等时显示队伍人数警告，可以切队或改为观战
- 玩家头顶名字按队伍颜色显示，聊天、排行、结算也带队伍颜色
- 得分：第 1 名 10 分，第 2 名 8 分，第 3 名 6 分，之后依次 4 / 3 / 2 / 1 分
- 团队总分为队员得分之和；总分相同时比较最好名次

模式投票现在有三个选项：训练、个人竞技、团队竞技。

### 计时精度

- 地图剩余、本图计时、换图 / 模式投票剩余、结算倒计时统一显示 `mm:ss.mmm`
- 服务端提供毫秒基准，客户端在两次 state 之间本地插值，避免每秒跳一次
- 个人最佳也按毫秒存储和显示
- 冲线按 100ms 独立检测，避免 1 秒 tick 把成绩量化成整秒

### 竞技排行

- 已到达 Hunter / 终点完赛的玩家优先
- 完赛玩家按冲线名次排序
- 其余玩家按剩余命数降序排序

## 完赛与结算

- 车辆进入终点半径即算完赛
- 竞速模式第一名完赛后进入 **30 秒结算倒计时**
  - 其他玩家仍可继续冲线
  - 倒计时结束后显示前三，约 8 秒后自动进入换图投票
- 训练模式按玩家个人结算
  - 完赛显示个人成绩
  - **5 秒后回到随机出生点**，其他人不受影响
- 终点半径、倒计时、结算展示时间、训练返回延迟都在 `shared/config.lua` 调整
- 顶部计时和右下角赛道面板显示**当前地图个人最佳**
- 个人最佳按 serial + 地图 resource 存入 `rst_ui_records.db`，训练 / 竞速完赛都会更新

## 音效

- 出生倒计时：每下数字一声短提示音
- GO：独立发车音
- 冲线完赛：上行结算音
- 比赛结束但未完成 / 被淘汰：下行失败音
- 团队结算按红蓝胜负播放对应完赛 / 失败音
- 按钮和确认保留点击 / 确认音

音效文件在 `sounds/`，通过 `meta.xml` 下载。

## 地图

地图使用原生 MTA 格式，不维护第二份地图清单：

- `server/mapregistry.lua` 自动发现 `type="map"` resource
- 直接读取 `meta.xml` 和 `.map`
- 从 `.map` 读取全部 spawnpoint、vehicle、racepickup、Hunter 终点 / checkpoint
- `racepickup` 由客户端按官方 race 资源方式创建自定义模型 object + colshape
- 支持 nitro / repair / vehiclechange；respawn=0 为永久可重复拾取，respawn>=50 才隐藏并按毫秒重生
- 官方 race pickup 模型放在 `pickups/`
- 解析并应用 `<settings>`：时间、天气、重力、游戏速度、浪高、车辆武器、云层、地图时长
- 地图车辆模型替换由地图 resource 自己的 client 脚本完成（例如 Silent Hill 的 Sandking 495），加载地图时自动执行
- 地图 ID 就是 resource 名
- 地图池就是发现到的地图列表
- 启动只读 `meta.xml`，`.map` 的 spawn / pickup / finish 在选中地图时才解析

## mtavault 地图集

地图展示元数据来自：

```text
https://mtavault.com
```

截至 **2026-11-15**：

- 已抓取并写入 SQLite 的 mtavault **DM / HDM** 元数据：**4509 张**
- HDM 15 张同时带 DM 标签，按地图 ID 去重后为 4509
- 本仓库**不包含任何地图文件**
- 地图模型、贴图、脚本和地图本身的版权属于各自作者

地图 zip 需要自行获取，可以找其他人打包的完整包，也可以在 mtavault 按需下载单张地图。使用和再分发前请确认作者授权。

拿到地图后不需要解压，直接放到：

```text
server/mods/deathmatch/resources/
```

例如：

```text
resources/<map-name>.zip
```

MTA 支持 zip resource，资源名就是 zip 去掉 `.zip` 的名字。

然后：

```text
refresh
restart rst_ui
```

或者直接重启服务器，地图会进入地图池。

要求：

- zip 根目录直接有 `meta.xml`，不能多套一层文件夹
- 不要同时保留同名解压目录和 zip
- 客户端只会下载当前被选中的地图，不会因为装了 4509 张就全部下载

F2 →「地图池」可以分页浏览和搜索已安装地图。

启动只读取轻量 meta；只有地图被选中时才解析 `.map`。全量 4509 张会扫描 4509 个 resource/meta，但不会启动时解析全部地图细节。

元数据数据库的安装、seed DB 和抓取/下载脚本说明见：

```text
tools/mtavault/README.md
```

出生：

- 每名玩家优先分配一个未被占用的 spawnpoint
- 只有在 spawnpoint 全部分满后才允许重复
- 使用该 spawnpoint 对应的 vehicle
- 不默认安装氮气

切换地图：

- `server/mapmanager.lua` 负责 start / stop 地图资源
- 地图自带 vehicle 会移除，racepickup / object / marker 保留
- 单服务器只运行一个比赛舞台，同一时间一张地图；并行舞台需要地图实例化或双服务器

### 地图选择与热度

- 非投票时 `pickMap()` 从当前可用地图池里纯随机，排除当前地图
- 投票候选随机抽取，只区分“最近玩过 / 没玩过”
- 服务器内游玩次数记录在 `rst_ui_mapstats.db`
- mtavault 下载量来自 `rst_ui_mapmeta.db`
- 热度公式：

```text
popularity = mtavault 下载量 + 服务器内游玩次数 × playPopularityWeight
```

- F2「地图池」按这个热度降序分页，热度相同再按名称
- 投票票数相同时用这个热度做平票裁决
- 随机选图仍然是纯随机，不会因为下载量高就固定出某张图
- 投票候选抽取本身不做热度加权；热度只影响地图池显示排序和平票

地图详情：

- F2 →「地图详情」查看当前地图
- 显示封面、作者、上传日期、下载量、大小、难度、标签、spawn / vehicle / 终点
- YouTube、mtavault 链接支持复制，不内嵌视频
- 原生信息来自 `.map`；封面和链接来自 mtavault 元数据 SQLite（由 seed DB 安装），按需查询，不参与加载

排行榜：

- 比赛结算面板显示当局前 3 名
- 右侧竞技面板显示当前所有玩家，按完赛顺序 / 剩余命数排序
- F2 →「赛道排行榜」查看**当前地图历史最佳成绩**
- 按个人最佳完赛时间升序，每页 20 条
- 记录来自 `rst_ui_records.db`，按 serial + 地图保存个人最佳

地图本体、压缩包、地图缓存都不进 Git。

### 自定义载具模型（可选）

代码已经内置服务器默认载具 DFF/TXD 加载，但默认没有模型文件，所以不会生效。

推荐用**载具模型 ID**命名：

```text
server/mods/deathmatch/resources/[rst]/rst_ui/models/411.dff
server/mods/deathmatch/resources/[rst]/rst_ui/models/411.txd
```

`411` 是 Infernus。任何 GTA:SA 载具模型 ID 都可以：

```text
models/411.dff   Infernus
models/522.dff   NRG-500
models/470.dff   Patriot
...
```

也支持车名 slug 作为别名：

```text
models/infernus.dff
models/infernus.txd
models/nrg500.dff
models/nrg500.txd
```

规则：

- 数字 ID 优先：`models/411.dff` 存在时不会用 `models/infernus.dff`
- 车名 slug 是 `getVehicleNameFromModel` 转小写后只保留字母数字
- 例如 `Infernus` → `infernus`，`NRG-500` → `nrg500`
- 支持模型 ID `400` 到 `611`
- DFF 和 TXD 可以只放其中一个
- 文件必须是 GTA:SA 可用的 DFF / TXD
- 模型文件不入库，版权归模型作者

MTA 1.6 的 meta 已经用 glob 自动登记：

```xml
<file src="models/*.dff" />
<file src="models/*.txd" />
```

放入文件后执行：

```text
restart rst_ui
```

或者重启服务器。没有模型文件时不会替换，也不会报错。

载具 ID 查询：

```text
https://wiki.multitheftauto.com/wiki/Vehicle_IDs
```

优先级：

```text
服务器默认载具模型
        ↓ 地图 resource 启动，地图自己的模型脚本加载
地图自己的 DFF / TXD 覆盖对应模型 ID
```

地图 resource 有对应模型时始终使用地图的；换图时服务器默认模型会在地图启动前重新应用，再由新地图覆盖。地图只覆盖部分车型时，其余车型继续使用服务器默认模型。

如果想完全关闭这个功能，把：

```text
client/custommodels.lua
```

顶部的：

```lua
local ENABLED = true
```

改成 `false`。

## 账号

- 自定义 SQLite 账号，昵称即账号名
- 注册需要输入两遍密码
- 密码最少 8 位
- 使用 MTA `passwordHash` / `passwordVerify`（bcrypt）
- 游客不写数据库

当前不是 MTA 官方 Account：没有 ACL、账号数据、密码重置。

## 聊天

- 输入使用 MTA 原生 chatbox，支持中文输入法
- 原生聊天输出被拦截，由 CEF 显示聊天记录
- 保留最近 100 条；列表可滚动，超出后删除最早一条
- 往上翻历史时不会被新消息拉到底部，新消息有提示按钮
- 单条消息按 UTF-8 字符数限制 160 字
- 玩家普通消息由服务端 `onPlayerChat` 转发到 CEF
- `/` 开头的消息交给 MTA 原生指令处理
- 可用指令：`/help`、`/car [模型]`
- MTA 默认 `Y` 团队聊天已禁用，`Y` 只用于倒带

## UI

- CEF 全屏透明，只有 HUD 面板有背景
- 登录 / 菜单 / 投票 / 聊天等场景强制显示光标，游戏内默认隐藏
- 1080p 为 1.0×，720p / 1440p / 4K 自动缩放
- 原生血条、武器、金钱等 HUD 隐藏，保留雷达和准星
- F2 菜单分为「玩法 / 界面 / 系统」三个页签
- 界面页支持总开关和独立开关：HUD、聊天记录、小地图、准星、玩家名字牌
- 全部 GUI 开关会覆盖上面所有显示项；单项偏好保存在本机
- 玩家名字牌开关只影响当前客户端
- 右下角显示构建日期和 git hash

## 飞行高度

- 飞机 / 直升机默认高度上限已解除
- 喷气背包默认高度上限已解除
- 客户端统一设置为 `100000`
- 地图 resource 在启动时如果重新设置了更低的上限，客户端会在地图启动后再次应用
- 常量在 `client/main.lua` 的 `FLIGHT_MAX_HEIGHT`

## 倒带

- 客户端本地记录最近 8 秒
- 记录位置、朝向、速度、载具血量、氮气 level / count / 喷射状态
- 同时记录并倒带载具血量，结束时同步回服务端
- 倒带结束保留倒带点之前的历史并平移到当前时间，连续使用不会从 0 重新攒时间
- 倒带期间关闭氮气喷射，结束时恢复倒带点的状态
- 松开 Y 后先冻结在松开瞬间的倒带状态 500ms，再恢复操作和速度
- 客户端本地倒带；服务端负责扣命和结束时血量同步，没有反作弊校验

相机只在进入游戏、观战返回、重生时重置，不会因每秒 state 更新把视角拉回车后。观战使用自由飞行相机，不再跟随幸存玩家。

## 配置

主要配置在 `shared/config.lua`：

| 字段 | 说明 |
| --- | --- |
| `roundSeconds` | 每张地图时长 |
| `defaultMode` | 默认训练 / 竞技 |
| `competitiveLives` | 竞技命数 |
| `voteSeconds` / `modeVoteSeconds` | 投票时长 |
| `voteCooldown` / `modeVoteCooldown` | 手动投票冷却 |
| `spawnCountdown` / `competitiveCountdown` | 出生倒计时 |
| `finishRadius` | 终点判定半径 |
| `raceEndCountdown` | 第一名完赛后的结算倒计时 |
| `raceResultSeconds` | 结算排行展示时间 |
| `trainingReturnSeconds` | 训练模式完赛回出生点延迟 |
| `playPopularityWeight` | 服务器游玩次数权重（叠加 mtavault 下载量） |
| `scoreTable` | 冲线名次对应积分 |
| `teamColors` | 红 / 蓝队名字颜色 |
| `vehicle` | 没有 spawnpoint vehicle 时的默认车型 |

地图列表不写在配置里。

## 目录

```text
cef/                         Vue 3 + Vite 前端
server/                      MTA 服务端运行时
  mods/deathmatch/resources/[rst]/rst_ui/
    client/                  CEF、输入、倒带、ghost
    server/                  账号、地图、房间、投票
    shared/config.lua        玩法配置
    covers/                  地图封面
tools/mtavault/              mtavault 抓取 / 扫描
tools/mtavault/seed/         只读地图元数据 seed DB
tools/setup-map-acl.mjs      地图 ACL 设置
```

## 已知限制

- CEF 输入框中文输入不可用；聊天输入已改用 MTA 原生 chatbox
- 单服务器单舞台，同一时间一张地图；真正并行需要地图实例化或双服务器
- 地图没有 checkpoint / 圈速校验；完赛按终点半径判定，排行按冲线顺序和剩余命数
- 倒带在客户端本地执行，没有服务端校验
- 原生地图脚本可能输出自己的聊天提示或 deprecated 警告
- 登录错误会区分账号不存在 / 密码错误

## 验证

- `pnpm type-check`、`pnpm build`、Lua 5.1 语法检查通过
- 真实客户端验证注册、登录、游客、HUD、地图加载、地图详情、地图池分页
- 服务端启动：`Resources: 5 loaded, 0 failed`
- 地图发现：4 个原生 map resource
- mtavault 元数据：4509 张，SQLite 已导入
- 地图资源 ACL、随机 spawn、无默认氮气、地图详情已在客户端验证

## 约定

- 源码和文档使用 LF
- 地图、压缩包、数据库、日志、`ui/` 构建产物不入库
- 远程仓库：`git@github.com:racespeedtime/rst-mta-lite.git`
