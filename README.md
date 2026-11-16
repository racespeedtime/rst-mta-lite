# rst-mta-lite

轻量 MTA:SA 竞速服务器：服务端用 Lua，客户端界面用 CEF + Vue 3 + TypeScript + Vite + Element Plus。

它主要解决一个问题：**几千张地图不能当作几千个 resource 常驻**。地图平时放在“地图库”里，换图时只把选中那张复制进运行槽位，所以开服从 8 分钟降到 1 秒内，客户端也只下载当前地图。

功能一眼看：

- 训练 / 个人竞技 / 团队竞技
- 按需地图库；F2 地图池支持分页、实时搜索、表头排序、上传日期范围过滤、详情、点名投票
- 换图投票分“强制”和“玩家自发”：自发投票不弹全屏，F4 打开，提名自动 1 票，可弃权 / 改投
- CEF HUD、聊天、计分板、投票面板、地图详情、赛道排行榜
- 倒带（按住 Shift 3 倍速）、训练传送点、落水后按住 R 重生
- SQLite 账号、地图热度、个人最佳
- 登录 / 换图时随机贝塞尔运镜（不显示出生点）
- 比赛进行中摩托 / 自行车不会被撞墙甩飞（客户端锁车 + 服务端兜底）
- 默认深色主题

---

## 快速开始

这个仓库**只有源码**。MTA 服务端本体、地图 zip、运行时数据库、日志、CEF 构建产物都不在仓库里，克隆后需要补齐。

### 0. 你需要什么

| 依赖 | 要求 |
| --- | --- |
| Windows | 10 / 11 x64 |
| Git | 任意较新版本 |
| Node.js | 22 LTS 或更新 |
| pnpm | 9+（实测 12.11.2） |
| MTA:SA Server | 1.6 |
| MTA:SA Client + GTA: San Andreas | 客户端 1.6 + GTA SA 1.0 |

正常开服不需要 MySQL、Redis、Python。

### 1. 克隆

```bash
git clone git@github.com:racespeedtime/rst-mta-lite.git
cd rst-mta-lite
```

没有 SSH key 就用 `https://github.com/racespeedtime/rst-mta-lite.git`。

### 2. 放入 MTA 服务端

从 <https://multitheftauto.com/> 下载 **MTA:SA Server 1.6**，把完整安装目录合并进仓库的 `server/`。

- 不能只复制 `MTA Server.exe`：根目录和 `mods/deathmatch` 下的 DLL、配置必须来自同一版本
- 合并后确认仓库的 `server/mods/deathmatch/resources/[rst]/` 没有被覆盖
- 用仓库自带的 `mtaserver.conf`、`acl.xml` 覆盖官方默认文件

### 3. 准备地图库

服务器必须有一个地图库，否则地图池是 0 张、无法开局。按 [地图库](#地图库) 一章里的「从 zip 生成」执行一次即可。

### 4. 构建界面

仓库不含 `rst_ui/ui/` 构建产物：

```bash
cd cef
pnpm install --frozen-lockfile
pnpm build
```

输出到 `server/mods/deathmatch/resources/[rst]/rst_ui/ui/`。没有它，进服只能看到空白 CEF。

### 5. 地图元数据 + ACL

```bash
# 安装 mtavault 地图元数据（下载量、上传日期、封面等）
node tools/mtavault/install-mapmeta-db.mjs

# 如果官方 acl.xml 覆盖了仓库版本，补齐地图资源权限
node tools/setup-map-acl.mjs
```

### 6. 启动并连接

```powershell
cd server
.\MTA Server.exe
```

首次启动会自动创建 `databases/`、`logs/`、`server-id.keys`。日志在 `server/mods/deathmatch/logs/server.log`，看到这两行即正常：

```text
Resources: 3 loaded, 0 failed
Server started and is ready to accept connections!
```

客户端连接：

```text
mtasa://127.0.0.1:22003
```

远程服需要放行 UDP `22003`（游戏）和 TCP `22005`（HTTP）。

### 仓库里有什么

| 内容 | 在 Git 里 | 说明 |
| --- | --- | --- |
| `cef/` 前端源码 | 是 | 需要 `pnpm build` |
| `rst_ui/` Lua / 页面 | 是 | 构建产物 `ui/` 除外 |
| `mapmeta` seed 数据库 | 是 | 安装成运行时 DB |
| MTA 服务端本体、DLL | 否 | 官方服务端完整安装 |
| `mtaserver.conf` / `acl.xml` | 是 | 默认配置 |
| 地图 zip、`maplib/maps`、`index.json` | 否 | 自行准备 / 脚本生成 |
| `databases/`、`logs/`、`server-id.keys` | 否 | 运行时生成 |

---

## 玩法

### 进入服务器

登录、注册或游客进入后，会自动加入唯一比赛舞台。训练模式可以反复重生 / 观战；竞技模式如果比赛进行中，先观战，等下一回合参赛。

### 操作

| 按键 | 功能 |
| --- | --- |
| `T` | 聊天输入 |
| `F1` | 帮助；有弹窗时先关闭弹窗 |
| `F2` | 菜单；有弹窗时先关闭弹窗 |
| `F3` | 临时显示 / 隐藏光标 |
| `F4` | 打开 / 关闭投票面板（换图 / 模式投票） |
| `Tab` | 按住查看全服玩家列表 |
| 短按左 `Alt` | 训练模式保存当前位置为传送点 |
| 长按左 `Alt` | 训练模式回到最近传送点 |
| 长按 `Y` | 倒带最近 8 秒；倒带时按住 `Shift` 3 倍速 |
| 按住 `R` | 落水且速度不快时，按住 0.8 秒重生；竞技模式消耗 1 条命 |
| 观战 | 鼠标转向 · `WASD` 平移 · 左/右键切人 · 空格 / Ctrl 升降 |

`Esc` 关闭最上层弹窗。

### 模式

- **训练**：默认模式，无限倒带，完赛后 6 秒回随机出生点，可主动重生 / 观战
- **个人竞技**：按个人冲线名次计分，每人 10 条命
- **团队竞技**：红 / 蓝队，人数必须相等才能开始；按队伍总分结算，总分相同比最好名次

冲线积分：第 1 名 10 分，第 2 名 8 分，第 3 名 6 分，之后 4 / 3 / 2 / 1 分。

命数消耗：每完成一次倒带扣 1 条；竞技模式里**死亡也扣 1 条**（自动重生，命数归零转观战）；竞技模式**落水按 R 重生也扣 1 条**（训练模式不扣）。

模式投票只切模式、不换图：投票期间照常跑图，按 `F4` 打开面板；切换成功后保留当前地图，从出生点重新开局并重置计时。如果投票结果还是当前模式，本回合继续；如果投票期间回合已经先结束，则投票结束后重新开局。
- 比赛进行中（训练 / 竞技）**不能主动下车**；防止弃车跑图 / 被人拉下车，`blockVehicleExit = false` 可关闭

### 完赛与结算

- **只认 Hunter 终点 pickup**：玩家实际拿到 `racepickup`（`vehiclechange`、`vehicle=425`）才算完赛，不再用坐标半径或 checkpoint 提前判定；没有这个 pickup 的图会在装载时被判为坏图并自动换图
- 完赛瞬间先给一条 toast（本次成绩 / 名次），几秒后再弹结算面板
- 竞技模式第一个完赛后进入 30 秒结算倒计时，其他人还能继续冲线；横幅实时显示剩余时间，并在 30 / 20 / 10 秒和最后 5 秒各发一条 toast 提醒；倒计时结束显示前 3 名，约 8 秒后进入换图投票
- 训练模式按个人结算，3 秒后弹面板，6 秒后回到随机出生点；**训练成绩不写入个人最佳**
- 地图剩余时间、本图计时、投票倒计时、结算倒计时统一显示 `mm:ss.mmm`，客户端在两次状态之间本地插值
- 个人最佳按“玩家 + 地图”保存在 `rst_ui_records.db`

### 倒带

- 客户端本地记录最近 8 秒：位置、朝向、速度、血量、车身损坏、氮气状态
- 车辆模型变化（Hunter / `vehiclechange` pickup）会清空倒带历史，不能倒带回换车之前，避免把当前车型带回旧时间点
- 松开 `Y` 后先冻结 0.5 秒，再从倒带点继续
- 倒带期间按住 `Shift` 可以 3 倍速快退，浮层会显示 `×3`
- 相机也按录制矩阵回放：位置、距离、朝向、FOV、roll 跟着倒带，不是默认追车相机重新跟一遍；结束后交还追车相机
- 竞技模式每次倒带扣 1 条命；客户端本地执行，没有服务端反作弊校验

### 训练传送点

- 短按左 `Alt` 保存当前位置，长按回到最近一次保存点；F2 → 训练里可以管理多个点
- 传送点会恢复位置/朝向/血量/损坏/氮气，并把车换回保存时的车型；训练模式由服务端同步模型
- 传送只恢复位置/朝向/血量/损坏/氮气，不会改变当前车辆模型

### 落水重生

- 训练和竞技模式都可用：人 / 车在水里，且速度低于阈值并持续 0.8 秒
- 屏幕上出现 toast「落水了 · 按住 R 重生」，每 6 秒提醒一次（竞技模式会标注消耗 1 条命）
- 按住 `R` 0.8 秒后回到随机出生点；训练模式不扣命，竞技模式扣 1 条命；服务端会再校验一次是否真的在水里、速度是否够低
- 客户端阈值在 `client/waterhint.lua` 顶部；竞技服务端速度阈值是 `waterRespawnSpeed`

### 聊天

- 输入用 MTA 原生 chatbox，中文输入法可用；消息由 CEF 显示
- 面板只显示最新 15 条，不提供历史滚动
- 单条最多 160 字
- 限速：两条至少间隔 900ms，10 秒内最多 6 条，超出丢弃并提示
- `/` 开头交给 MTA 原生指令，内置 `/help`、`/car [模型]`
- `Y` 只用于倒带，不打开团队聊天

### 换图投票

| 类型 | 触发 | 表现 |
| --- | --- | --- |
| 强制投票 | 回合时间到 / 竞技结算完 | 自动弹全屏投票，停掉当前回合，出结果直接换图 |
| 玩家自发投票 | F2 菜单 / 地图池「投票」 | 不弹全屏、不打断跑图；屏幕提示按 `F4` 参与；出结果立即换图 |

自发投票的细节：

- 发起人的提名**自动算 1 票**；提名图固定在最上面，用「系统随机推荐」分界线隔开其余随机候选
- 可以改投（以最后一次为准），也可以改成弃权；弃权算已表态，但不给任何地图加票
- 如果票选结果就是当前地图，保留本回合继续
- 投票结束后冷却 180 秒才能再发起；回合到点的**自动投票不受这个冷却限制**
- 竞技结算倒计时（30 秒）和最终排行期间不能发起投票；如果自发投票在这期间先出结果，会挂起到本轮结算结束后再切图
- 发起人的面板会自动打开，其他人按 `F4` 开关
- 票数相同时按热度、再随机决定

想改回“回合结束后再换图”，把 `shared/config.lua` 的 `manualVoteImmediate = false`。

### 地图池

F2 →「地图池」：

- 分页，每页 10 / 20 / 30 / 50 / 100
- 输入即搜，不用点搜索按钮
- 表头点名称 / 上传日期 / 下载量 / 热度排序，点三次恢复默认（热度降序）
- 上传日期范围过滤，格式 `YYYY-MM-DD`，留空不限
- 点任意行看详情；行尾「投票」可以点名一张图发起投票

热度公式：

```text
热度 = mtavault 下载量 + 服务器内游玩次数 × playPopularityWeight
```

随机选图仍是纯随机；热度只影响地图池排序和平票裁决。

### 排行榜

F2 →「赛道排行榜」查看当前地图历史最佳，按时间升序、每页 20 条。个人最佳只记录竞技（个人 / 团队）成绩，训练模式不写入。

---

## 地图库

### 为什么不能直接把 zip 堆进 `resources/`

MTA 启动会加载 `resources/` 下的每个 resource，并对 `meta.xml` 声明的每个文件算 MD5；zip resource 还会整包解压。4486 张地图约 26 GB，实测启动 145 秒才处理到字母 E，全量 8 分钟以上，还会额外占 18 GB 缓存。

地图库的做法：地图文件放在 `[rst]/maplib/` 这个**数据 resource** 里，它的 `meta.xml` 不声明任何文件，所以开服只读一个 meta；换图时再复制选中那张到运行槽位 `rst_map`。

### 目录结构

```text
server/mods/deathmatch/
  map-cache/zips/*.zip          ← 你的 zip 备份（不入库）
  resources/[rst]/maplib/
    meta.xml                    ← 入库，不声明文件
    index.json                  ← 地图池索引（脚本生成，不入库）
    build-report.json           ← 无效 / 失败清单（脚本生成，不入库）
    maps/<地图id>/              ← 展开后的地图（脚本生成，不入库）
      meta.xml
      _files.txt                ← 换图时按它复制文件
```

地图 id 就是 zip 文件名去掉 `.zip`，也是 `maps/` 下的目录名。

### zip 备份要不要留？

`map-cache/zips/` 只是**备份 / 源包**，服务端运行时完全不读它。服务器只读：

- `maplib/maps/<id>/`（换图时从这里复制文件）
- `maplib/index.json`（地图池索引）

所以 `map-cache/zips/` 和 `maplib/maps/` 是同一批地图的两份拷贝，会占双份空间。本机实测：

| 内容 | 大小 | 文件数 |
| --- | --- | --- |
| `map-cache/zips/` | 25.6 GB | 4486 个 zip |
| `maplib/maps/` | 36.0 GB | 展开后的地图文件 |
| 两份都留 | **61.6 GB** | |

展开后比 zip 大是正常的：zip 是压缩过的，展开后是原始文件。

磁盘紧的话有三种做法：

- **只留展开后的库**：生成时加 `--delete-zips`，或确认无误后手动删 `map-cache/`
- **把 zip 挪到外置盘**：`--move-zips D:\backup\zips`，以后重建时用 `--zips D:\backup\zips`
- **只留 zip、不留展开库**（不推荐）：每次换图都要临时解压，装载会慢，而且没法提前校验

不保留 zip 的代价：以后想 `--force` 重建、或地图库损坏时，需要重新下载 / 找 zip。

### 从 zip 生成

```bash
# 默认读 server/mods/deathmatch/map-cache/zips/*.zip
node tools/mapstore/build-library.mjs

# 用别的目录
node tools/mapstore/build-library.mjs --zips "D:\maps\zips"
```

| 参数 | 作用 |
| --- | --- |
| `--zips <目录>` | zip 目录 |
| `--out <目录>` | 地图库目录（一般不用改） |
| `--only a,b` | 只处理指定地图 id |
| `--limit n` | 只处理前 n 张 |
| `--force` | 已展开的也重新解压 |
| `--move-zips <目录>` | 展开成功后把 zip 移走（迁移用） |
| `--delete-zips` | 展开成功后删除 zip（危险） |
| `--reindex` | 不碰 zip，只扫描 `maps/` 重建索引 |

zip 要求：

- 一个 zip = 一张 MTA 地图 resource
- 根目录（或只套一层目录）要有 `meta.xml`
- `meta.xml` 引用的 `.map` / 文件缺失时，这张图会被标成无效，不进地图池

### 跑两次会怎样？

默认幂等，不会覆盖：

- 已经展开的图跳过解压，只重新校验和重算索引
- 加 `--force` 才会删掉目录重新解压
- zip 没了但目录还在，地图保留；目录删了，索引条目会被清掉
- `index.json` 和 `build-report.json` 每次重写

### 手动解压

把每个 zip 解压到 `.../maplib/maps/<地图id>/`（`meta.xml` 在目录根部），然后：

```bash
node tools/mapstore/build-library.mjs --reindex
```

它会自动补 `_files.txt` 和 `index.json`，不需要 zip。更细的格式说明见 `tools/mapstore/README.md`。

### 无效地图

校验不通过的地图会写进 `build-report.json`，不进地图池。开服日志会逐张列出被跳过的地图和缺失文件数。当前实测 4486 张 zip 中 4482 张可玩，4 张缺文件：`atlas`、`foggy-swamp`、`just-cant-map-x4`、`transformers`。

### 换图流程

1. 选出目标地图
2. `MapStore` 把 `maplib/maps/<id>/` 的文件复制进运行槽位 `resources/rst_map`
3. `refreshResources` + `startResource` 启动槽位
4. 解析 `.map`，生成出生点、载具、pickup、终点

换图是异步的，装载失败的地图会自动从地图池移除并换一张重试。客户端只会下载当前这张地图。

### 出生与拾取物

- 每人优先分配未占用的 spawnpoint，全占满后才允许重复
- 使用 spawnpoint 对应载具；不默认装氮气
- 支持 nitro / repair / vehiclechange 三种 pickup
- `respawn = 0` 是永久可重复拾取；`respawn >= 50` 才会隐藏并按毫秒重生
- 换车 pickup 正上方显示白色车型名，120 米内可见，越远越淡
- 地图 `<settings>` 里的时间、天气、重力、游戏速度、浪高、车辆武器、云层会被应用
- 地图自带的 vehicle 会被移除，racepickup / object / marker 保留

### 自定义载具模型（可选）

模型文件不入库，按模型 ID 命名放进 `rst_ui/models/`：

```text
models/411.dff   411.txd     ← Infernus
models/522.dff   522.txd     ← NRG-500
```

也支持车名 slug，例如 `infernus.dff`、`nrg500.txd`。数字 ID 优先。放好后 `restart rst_ui` 或重启服务器；地图自带的模型覆盖优先于服务器默认模型。

---

## 界面

- CEF 全屏透明，只有 HUD 面板有背景；1080p 为 1.0×，其他分辨率自动缩放
- 原生血条、武器、金钱隐藏，保留雷达和准星
- F2 菜单分「玩法 / 训练 / 界面 / 系统」四个页签
- 界面页可以总开关或单独开关 HUD、聊天、小地图、准星、玩家名字牌
- 按住 `Tab` 显示全服玩家：ID / 昵称 / 状态 / FPS / Ping，不弹鼠标、不暂停操作
- 右下角显示构建日期和 git hash

### 主题

- 默认**深色**；浅色可选，但标了“实验”，目前效果一般
- 预设主题色或自定义颜色；点「还原默认主题」恢复深色 + 默认青色
- 设置保存在本机 CEF 的 localStorage，不跟账号走

### 加载运镜

- 登录 / 选图、服务端换图装载、资源下载时，相机会沿随机三次贝塞尔曲线在 GTA:SA 世界范围内缓慢飞行
- 不再盯着出生点或冻结的车辆；装载完成自动把相机交还给玩家
- 首次下载 `rst_ui` 本身时脚本还没加载，这一段仍然是 MTA 默认画面

```text
client/loadingcam.lua
```

### 清除缓存

F2 →「系统」→「清除浏览器缓存」：关闭界面、强制重新加载 CEF 资源（忽略缓存），本地主题和键位设置保留。界面异常、样式不更新时用。

客户端换图多了以后，MTA 安装目录下的资源缓存会变大，停服后清掉 `mods/deathmatch/resources` 缓存即可，MTA 会按需重建。

---

## 配置与运维

### 服务端配置

`server/mods/deathmatch/mtaserver.conf` 默认值：

```xml
<servername>rst-mta-lite</servername>
<serverport>22003</serverport>
<httpport>22005</httpport>
<maxplayers>32</maxplayers>
<fpslimit>60</fpslimit>
<resource src="rst_ui" startup="1" protected="0"/>
```

`rst_ui` 必须保持 `startup="1"`。服务器浏览器里的名字、描述、语言、标签、官网就在这个文件顶部的 `<rule>` 里；上公网前记得填 `owner_email_address`（MTA 主列表可见性需要）。玩法参数在 `rst_ui/shared/config.lua`：

| 字段 | 说明 |
| --- | --- |
| `roundSeconds` | 每张地图时长 |
| `defaultMode` | 默认训练 / 竞技 |
| `competitiveLives` | 竞技命数 |
| `voteSeconds` / `modeVoteSeconds` | 投票时长 |
| `voteCooldown` / `modeVoteCooldown` | 手动投票冷却 |
| `manualVoteImmediate` | 自发投票是否立即换图 |
| `spawnCountdown` / `competitiveCountdown` | 出生 / 开赛倒计时 |
| `raceEndCountdown` / `raceResultSeconds` | 竞技结算倒计时 / 排行展示时长 |
| `trainingReturnSeconds` / `finishResultDelay` | 训练完赛回出生点延迟 / 完赛结算面板延迟 |
| `waterRespawnSpeed` | 竞技落水重生的最大速度 |
| `blockVehicleExit` | 比赛进行中（训练/竞技）禁止主动下车（默认 `true`） |
| `playPopularityWeight` | 游玩次数热度权重 |
| `scoreTable` / `teamColors` / `vehicle` | 冲线积分 / 队伍颜色 / 默认车型 |
| `chatMinIntervalMs` / `chatBurstWindowMs` / `chatBurstLimit` | 聊天限速 |

地图列表不写在配置里，只认地图库索引。

### ACL

`acl.xml` 里的 `raceACLGroup` 已包含 `resource.rst_ui`，并授予 `startResource`、`stopResource`、`restartResource`、`createResource`、`deleteResource`、`refreshResources`、`xmlLoadFile`。

如果安装官方服务端时覆盖了这个文件，用快速开始第 5 步的 `setup-map-acl.mjs` 补齐，然后重启服务器。

### 地图元数据

`tools/mtavault/seed/rst_ui_mapmeta.db` 是只读 seed，包含 4509 张 DM/HDM 的展示元数据（下载量、上传日期、封面等），不含地图本体、账号或玩家记录。

安装命令见快速开始第 5 步，目标：`server/mods/deathmatch/databases/global/rst_ui_mapmeta.db`。没有它服务器也能跑，只是下载量 / 上传日期为空（按日期过滤会排除这些图）。

### 数据库与日志

运行时 SQLite 都在 `server/mods/deathmatch/databases/global/`：

- `rst_ui_accounts.db`：账号
- `rst_ui_records.db`：个人最佳
- `rst_ui_mapstats.db`：地图游玩次数
- `rst_ui_mapmeta.db`：地图元数据

日志：`server/mods/deathmatch/logs/server.log`。

### 性能

2026-11-16 本机 NVMe 实测：

| 项目 | 数值 |
| --- | --- |
| 开服到 `Server started` | 0.38–0.65 秒（3 个 resource） |
| 装载一张 24 MB / 56 文件地图 | 1.9–2.8 秒 |
| 换一张 12 MB / 49 文件地图 | 约 2.1 秒 |
| 地图池默认分页 | 约 0.25 ms |
| 地图池按下载 / 热度 / 名称排序 | 14–36 ms（只在你点表头时） |
| 全量地图库 | 约 36 GB |

---

## 账号

- 自定义 SQLite 账号，昵称即账号名
- 注册需要两次密码，最少 8 位；使用 MTA `passwordHash` / `passwordVerify`（bcrypt）
- 游客不写数据库
- 不是 MTA 官方账号，没有 ACL、账号数据、密码重置

---

## 开发

### 目录

```text
cef/                              Vue 3 + Vite 前端源码
server/mods/deathmatch/
  resources/[rst]/
    rst_ui/                       CEF、输入、倒带、服务端逻辑
      client/  server/  shared/config.lua
    maplib/meta.xml               地图库数据 resource
  mtaserver.conf / acl.xml
tools/
  mapstore/build-library.mjs      zip → 地图库 + 索引
  mtavault/                       元数据抓取 / 扫描 / seed
  setup-map-acl.mjs               地图 ACL 设置
```

### 构建

见 [快速开始](#4-构建界面)。前端技术栈：Vue 3.5 + Element Plus 按需引入；当前产物约 `app.js` 562 KB / `style.css` 195 KB（gzip 约 182 + 29 KB）。

### 约定

- 源码和文档用 LF
- 地图、zip、数据库、日志、`ui/` 构建产物不入库
- 远程仓库：`git@github.com:racespeedtime/rst-mta-lite.git`

---

## 已知限制

- CEF 输入框中文输入不可用，聊天输入改用 MTA 原生 chatbox
- 单服务器单舞台，同一时间一张地图
- 完赛按终点半径判定，没有 checkpoint / 圈速校验
- 倒带在客户端本地执行，没有服务端校验
- 原生地图脚本可能输出自己的聊天提示或 deprecated 警告

## 验证

```bash
cd cef && pnpm type-check && pnpm build
```

服务端启动日志与快速开始第 6 步一致；进入游戏后检查注册 / 登录 / 游客、HUD、地图加载、地图池分页与搜索、换图投票。

## 版权

代码和文档使用 MIT License，见 [LICENSE](LICENSE)。

地图展示元数据来自 <https://mtavault.com>。地图模型、贴图、脚本和地图本身的版权属于各自作者；本仓库不提供地图文件或下载链接，获取和再分发前请确认作者授权。

MTA:SA、GTA: San Andreas 及相关名称归其各自权利人所有。
