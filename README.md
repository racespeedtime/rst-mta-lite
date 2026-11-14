# rst-mta-lite

轻量的 MTA:SA 服务器工程。服务端用 MTA 原生 Lua；客户端界面全部由 MTA 内嵌 CEF 承载，前端用 Vue 3 + TypeScript + Vite。

> **DeathMatch 在本项目里是竞速赛道（race），不是枪战 / DM。** 玩家出生直接获得赛车，不发放武器，也没有玩家血条。

## 当前进度

- [x] 仓库工程化：只提交源码，二进制 / 运行时 / 构建产物全部忽略
- [x] CEF + Vue 基础：全屏 local 浏览器、输入注入、Lua ↔ JS 桥
- [x] 注册 / 登录 / 游客模式（昵称即账号名，bcrypt + SQLite）
- [x] 双舞台（DeathMatch 竞速主舞台 / 副舞台）、30 分钟回合、观战 / 出生规则
- [x] 竞速出生：直接给赛车、带氮气，移除武器和玩家血条 / 护甲
- [x] 换图投票：随机图池、票数/热度/随机决胜、手动投票冷却
- [x] 地图投票面板：名称升 / 降序、模糊搜索、热度排序
- [x] 地图热度：源站基础热度 + 服务器游玩次数（SQLite 持久化）
- [x] mtavault DM 地图元数据抓取脚本（手动运行，默认不抓）
- [x] Ghost 模式：其他赛车半透明、客户端关闭车辆间碰撞
- [x] 模式投票：地图不变切换训练 / 竞技，默认训练
- [x] 竞技模式：10 条命、rewind 扣命、全员准备后倒计时、右侧按到终点距离实时排行
- [x] 游戏内 UI 透明：`html / body / #app / .app-root` 透明，只有 HUD 面板有底色
- [x] 场景化光标：界面操作强制显示，游戏内默认隐藏，F2 / F3 可控制
- [x] 分辨率 DPI 缩放：720p / 1080p / 1440p / 4K 自动缩放字体和 UI
- [x] mtavault 前 3 张 DM 地图本地安装 + 结构扫描（地图本体不入库）
- [x] 长按 Y 的 rewind 回放（位置 / 朝向 / 速度，最近 8 秒）
- [x] 按钮点击 / 确认音效（`playSound`）
- [x] 界面视觉升级：Iconify 本地图标、毛玻璃面板、赛道作者信息
- [x] CEF 聊天替代原生聊天：常驻聊天记录 + T 呼出输入 + Enter 发送 / Esc 取消
- [x] 载具仪表：速度、车辆血量、氮气余量 / 触发状态
- [x] 顶部地图计时：地图名、本图剩余倒计时、个人本图已玩时长
- [x] 观战模式：鼠标左键 / 右键切换下一位 / 上一位玩家
- [x] 操作帮助面板：F1 呼出，F2 菜单也可进入
- [x] 出生倒计时：每人独立的 3-2-1-GO 动画，结束后才可移动
- [x] 隐藏原生血条 / 武器等 HUD，保留雷达和准星
- [x] 右下角 Vite 构建信息：日期 + git 短提交号
- [ ] 圈数 / 检查点 / 名次结算、更多赛道
- [ ] 部署脚本 / 更多管理功能

## 玩法流程

1. 进入服务器，CEF 显示登录界面：输入密码后点「登录」或「注册」，也可以「Play as Guest」直接游客进入。
2. 登录后进入舞台选择：`DeathMatch · 主舞台` / `DeathMatch · 副舞台`，两个舞台互相独立（不同 dimension），各自跑地图。
3. 进入舞台：
   - 舞台里有正在玩的玩家 → 默认**观战**，相机跟随场内玩家；下一回合自动转为玩家出生。
   - 观战时鼠标左键 / 右键循环切换下一位 / 上一位存活玩家，顶部显示当前跟随对象。
   - 舞台空着 → 直接开始新回合，出生在赛车里，倒计时结束起跑。
4. 每张赛道最多 30 分钟。时间到自动发起换图投票（30 秒），也可以在 F2 菜单里提前发起。
5. 投票结束切换赛道，开始新回合；观战者一起转为玩家。
6. 默认是**训练模式**；F2 菜单可以发起模式投票，地图不变，在训练 / 竞技之间切换。
   - 竞技模式：每人 10 条命，每次 rewind 扣 1 条，扣完自动转观战
   - 竞技模式开局需要所有玩家点「准备」，全员准备后开始 5 秒倒计时
   - 玩家可以主动选择「纯观战」；纯 OB 不会在下一回合自动参赛，也可以随时回到比赛
   - 右侧中间实时显示所有参赛者到终点的距离、命数、排名和存活人数

## 操作

| 操作 | 说明 |
| --- | --- |
| 密码输入 + 登录 / 注册 / 游客 | 登录界面 |
| `T` | 打开 CEF 聊天输入框（再按 Enter 发送、Esc 取消） |
| `F1` | 打开 / 关闭操作帮助（F2 菜单里也有入口） |
| `F2` / F8 控制台 `ui` | 打开菜单：换图投票、模式投票、纯观战、DevTools、离开舞台 |
| 竞技模式准备 | 开局点击「准备」，全员准备后开始 5 秒倒计时 |
| F2 菜单「切换纯观战」 | 主动改为 OB，下回合继续观战；纯 OB 可再切回比赛 |
| F8 控制台 / 聊天 `/car` | 生成一辆带氮气的测试 Infernus（进入舞台后可用） |
| 观战模式左键 / 右键 | 切换下一位 / 上一位玩家 |
| 长按 `Y` | rewind 回放最近 8 秒，松开继续；竞技模式每次消耗 1 条命 |
| 鼠标 | 登录、选舞台、菜单、投票时自动显示并注入 CEF |

## 聊天

原生聊天已被完全隐藏并拦截：

- `showChat(false, true)` 隐藏原生聊天并阻止原生输入
- `onClientChatMessage` 里 `cancelEvent()` 拦下所有原生聊天输出（包括 MTA 内部消息和其他资源调用 `outputChatBox` 的内容），转发给 CEF 渲染
- 聊天记录在左上角常驻显示（最近 100 条），玩家消息带彩色昵称，系统消息使用金色
- 按 `T` 呼出输入框，`Enter` 发送并关闭，`Esc` 取消；打开时显示鼠标、禁用游戏控制，关闭后恢复之前的游戏状态
- 玩家消息走 `chat:send` action → 服务端校验长度 / 频率（1 秒）→ 广播给已登录玩家；同时写入服务端日志
- 加入 / 离开服务器的系统消息也会以聊天形式推送

## 地图计时

进入舞台后，屏幕顶部居中常驻一条计时栏：

- 地图名
- 本图剩余倒计时：剩余 ≤ 5 分钟变金色、≤ 1 分钟变红色；投票期间切换为投票倒计时
- 本图已玩：玩家个人在当前地图的累计时间

个人时长由服务端 `session.mapEnteredAt` 计算：加入房间 / 换图时重置，观战、菜单、聊天期间都会累计；随 1 秒一次的 state 推送更新。

## 载具仪表

上车后底部居中显示速度表（下车自动隐藏）：

- 速度：`getElementVelocity` 合成后 `* 180` 得到 km/h，数字 + 渐变速度条
- 车辆血量：`getElementHealth(vehicle) / 10` 百分比，颜色随血量变黄 / 变红
- 氮气：`getVehicleNitroLevel`（当前瓶充能）、`getVehicleNitroCount`（剩余次数，101 显示 `∞`）、`isVehicleNitroActivated` 触发时高亮
- 数据由客户端 10Hz 通过 `vehicle` 事件推给 CEF

每张赛道出生直接给一辆赛车（`config.maps.*.vehicle`，默认 Infernus），上车时客户端补满氮气；`/car` 仍可额外生成一辆测试车。

## 构建信息

右下角常驻 `BUILD 2026.11.15 · bf823d9` 小水印（所有界面可见，鼠标悬停显示 ISO 构建时间）：

- `__RST_BUILD_DATE__`：本地构建日期 `YYYY.MM.DD`
- `__RST_BUILD_TIME__`：ISO 构建时间，用于 tooltip
- `__RST_BUILD_HASH__`：构建时读取 `.git/HEAD` 的 7 位提交号，非 git 环境回退 `dev`
- 这些值由 [vite.config.ts](cef/vite.config.ts) 的 `define` 在构建时注入，运行时不需要读 git
- 改完 UI 重新 `pnpm build` 即可刷新版本号；hash 是**构建时**的 HEAD，不是运行时 HEAD

## 原生 HUD

玩家血量 / 护甲 / 武器 / 弹药 / 金钱等全部由 CEF 自绘，客户端启动时隐藏原生 HUD：

- 隐藏：`health`、`armour`、`weapon`、`ammo`、`money`、`wanted`、`area_name`、`clock`、`vehicle_name`、`breath`
- 保留：雷达、准星（瞄准仍然需要）
- 死亡重生后会重新隐藏一次；资源停止时恢复原生 HUD

## 出生倒计时

进入回合 / 换图后出生时：

- 服务端冻结玩家，并给该玩家单独推送 `countdown` 事件
- 客户端显示 3-2-1-GO 环形倒计时，每个数字有缩放淡入动画 + 提示音
- GO 后约 0.25 秒服务端解冻，玩家可以移动（相机在倒计时期间仍可转动）
- 倒计时期间禁用 rewind 录制；死亡重生不重复倒计时

倒计时长度在 [config.lua](<server/mods/deathmatch/resources/[rst]/rst_ui/shared/config.lua>) 调整：训练模式用 `spawnCountdown`，竞技模式全员准备后用 `competitiveCountdown`。

## 房间与回合

配置在 `shared/config.lua`：

- `roundSeconds = 30 * 60`：单张地图最长时长
- `defaultMode = 'training'`：新房间默认模式
- `competitiveLives = 10`：竞技模式每人命数
- `modeVoteSeconds = 20`：模式投票时长
- `modeVoteCooldown = 120`：手动模式投票冷却
- `voteSeconds = 30`：换图投票时长
- `votePoolSize = 5`：每次投票随机抽取的候选数（地图不够时自动减少）
- `voteCooldown = 180`：手动发起投票的冷却秒数
- `recentMapLimit = 2`：抽池时尽量避开最近玩过的地图
- `playPopularityWeight = 5`：服务器内每玩一场给热度加多少分
- `respawnDelay = 4000`：死亡重生间隔
- `spawnCountdown = 3`：训练模式出生倒计时
- `competitiveCountdown = 5`：竞技模式全员准备后的倒计时
- `maps`：地图名称、作者、流行度、赛车模型、出生点坐标 / 朝向、终点 `finish`（当前是占位坐标，接真实赛道后替换）
- `mapPool`：随机换图池
- `rooms`：两个舞台的 id / 名称 / dimension

规则实现见 `server/rooms.lua`：

- 两个舞台使用独立 dimension，玩家互相不可见
- 回合开始把所有观战者提升为玩家，直接出生在赛车里
- 每名玩家一辆赛车（`config.maps.*.vehicle`，默认 Infernus），带氮气升级
- 倒计时期间同时冻结玩家和赛车，GO 后解冻
- 不发放武器；玩家血条 / 护甲 / 武器 HUD 都隐藏
- 房间空掉时回合结束；下一次有人进入重新开回合
- 投票随机图池会尽量避免和另一舞台当前地图重复
- 换图后重置 30 分钟计时
- 进入舞台后，右下角显示「当前赛道」面板：地图名称 + 作者

## 投票规则

- 每次投票从地图池随机抽 `votePoolSize` 张，优先排除当前图和 `recentMapLimit` 张最近玩过的图
- 每名玩家一票，所有人投完可以提前结算
- 结算顺序：**票数最多 → 流行度更高 → 随机**
- 30 秒没人投票时同样按「票数 → 流行度 → 随机」结算，因此热度高的图更可能胜出
- 手动发起投票有 `voteCooldown` 冷却；回合时间到触发的自动投票不受冷却限制
- 投票面板支持：
  - 名称升序 / 降序
  - 地图名、作者模糊搜索
  - 按流行度排序
- `popularity` 目前是配置里的占位数据，后续可以从外部站点抓取后写入（UI / 排序 / 结算已按这个字段工作）

## 模式与竞技

### 训练 / 竞技

- 默认 **训练模式**：无限 rewind
- **竞技模式**：每人 `competitiveLives` 条命；每次 rewind 服务端扣 1 条；扣完移入观战（下一回合重新获得命数）
- 竞技模式开局所有玩家出生后先冻结，所有人点「准备」后才发送 5 秒倒计时
- 纯 OB：玩家可在 F2 菜单或准备面板主动切换纯观战；纯 OB 不会在下一回合被自动提升为玩家，需要手动「下回合参赛」
- 纯 OB 不占准备人数、不进竞技排行，也不消耗命数；命数耗尽是淘汰，不等于纯 OB
- 右侧中间排行：存活玩家优先；有终点按到终点直线距离升序，没有终点按远离起点距离降序，命数作为同距离时的次级排序；淘汰玩家沉底
- 每张图在 `config.maps.*.finish` 配终点坐标；当前 4 张图是示例坐标，接真实赛道后替换
- Hunter 约定：`racepickup type="vehiclechange" vehicle="425"` 的位置可作为终点候选；扫描器会提取 `hunterFinish`
- 没有终点时退回按远离起点距离排行；起点也没有时才退回按命数排序，面板底部会提示当前规则
- 模式投票：地图不变，只切换训练 / 竞技；平票或无人投票保持当前模式
- 手动模式投票有冷却，回合结束的自动换图不受影响

### UI 透明

- `html`、`body`、`#app`、`.app-root` 都是透明背景
- CEF 浏览器创建时开启 transparent；游戏内只有 HUD / 面板 / 弹层有底色
- 登录、选舞台、菜单等全屏界面会自己铺背景，不会透出游戏；游戏内 HUD 不会遮挡画面

### Ghost

- 其他玩家的赛车以半透明显示（本地玩家自己的车保持不透明）
- 客户端 `setElementCollidableWith` 关闭竞速车之间的碰撞，车辆可以互相穿过
- 世界碰撞、建筑碰撞保持正常

### 光标策略

- **强制显示**：登录 / 选舞台 / F2 菜单 / 聊天 / F1 帮助 / 换图投票 / 模式投票 / 竞技准备
  - 这些场景必须显示光标并禁用游戏控制，否则无法点击或输入
- **默认隐藏**：正常驾驶、倒计时、观光 HUD
- **F3**：游戏内临时显示 / 隐藏自由光标；显示时暂停驾驶控制，再按一次恢复
- **F2 菜单「光标显示」**：
  - `自动`：只在界面场景显示
  - `始终显示`：游戏内也显示（F3 可临时切回自动并隐藏）
- 强制场景下不提供“隐藏光标”，避免菜单无法操作；玩家选择只影响非强制场景

### 分辨率缩放

以 **1080p = 1.0x** 为基准，按屏幕高度缩放整个 CEF 布局：

| 分辨率 | 缩放 |
| --- | ---: |
| 1280×720 | 0.75x（下限） |
| 1920×1080 | 1.00x |
| 2560×1440 | 1.33x |
| 3840×2160 | 2.00x |

- 通过 CSS `zoom` 整体缩放，字体、面板、图标、间距一起变
- 逻辑视口保持约 1920×1080，避免 4K 下 UI 只占一小块
- 最小 0.75x、最大 2.5x，防止极端分辨率下不可读
- MTA 窗口尺寸变化时 `resizeBrowser` 后同步重新计算
- Lua 通过 `window.rst.setViewportSize(width, height)` 传入真实屏幕尺寸，页面自身再用 `window.innerHeight` 兜底
- 缩放的是布局，鼠标注入仍使用浏览器原生坐标

## 地图热度

有效热度在运行时计算：

```text
有效热度 = 基础热度（配置 / 爬虫写入） + 服务器内游玩次数 × playPopularityWeight
```

- 每次回合开始，`server/mapstats.lua` 给当前地图 `+1` 场
- 游玩次数写入 SQLite：`server/mods/deathmatch/databases/global/rst_ui_mapstats.db`（运行时生成，已忽略）
- 服务端启动时加载，重启后累计不丢
- 投票排序 / 平票判定 / 面板「热度」显示都使用有效热度
- `playPopularityWeight` 在 `shared/config.lua` 调整

## mtavault 抓取（预留）

抓取脚本：[tools/mtavault/fetch-dm-maps.mjs](tools/mtavault/fetch-dm-maps.mjs)，说明见 [tools/mtavault/README.md](tools/mtavault/README.md)。

- 走 `https://api.mtavault.com/maps`，不解析网页 HTML
- 默认按 `downloads` 降序，分页拉取后按 `DM` 标签 / `[DM]` 文件名过滤
- 精简字段：名称、作者、上传日期、热度（下载量）、难度、文件大小、标签、源站链接、YouTube 封面
- 默认只写 `tools/mtavault/output/`（已忽略），**不会自动执行**
- 封面可 `--cover-dir` 下载为本地 JPEG；CEF 不能直接加载外网图片，接入前需要放进资源并在 `meta.xml` 登记
- 受限网络可用 `--proxy http://127.0.0.1:7890` 或 `HTTPS_PROXY` 下载封面
- 这是元数据，不是可玩地图：真正跑赛道还需要出生点 / 检查点 / 圈数数据

## 本地地图安装验证

已下载 mtavault 流行度前 3 张 DM 图，并安装到服务端本地（全部被 `.gitignore` 忽略）：

| 资源 | 源站 | 下载量 | 大小 |
| --- | --- | ---: | ---: |
| `mtavault_silent_hill` | Silent Hill | 400 | 9.1 MB |
| `mtavault_a_new_dawn` | A New Dawn | 364 | 17.2 MB |
| `mtavault_descendants_skills_v` | Descendant's Skills V | 341 | 10.2 MB |

- 原包缓存：`server/mods/deathmatch/map-cache/`
- 解压资源：`server/mods/deathmatch/resources/mtavault_*/`
- 结构清单：`server/mods/deathmatch/map-cache/map-catalog.json`
- 扫描脚本：[tools/mtavault/scan-maps.mjs](tools/mtavault/scan-maps.mjs)

扫描结果：3 张图 **0 个 checkpoint**，但都有 **Hunter 终点 pickup**（`racepickup type="vehiclechange" vehicle="425"`）；只有 spawnpoint、vehicle、racepickup 和视觉 marker。

- `spawnpoint` 可用于取出生点和车型（1 / 1 / 2 个）
- marker 是 arrow / corona / cylinder，属于视觉引导，不是检查点
- Hunter 坐标可以作为 finish：
  - Silent Hill：`1524.6, 3812.6, 8.4`
  - A New Dawn：`6877.4, -828.0, 1.3`
  - Descendant's Skills V：`6940.9, 291.6, 332.9`
- settings 是 `vehicleweapons=true`、`ghostmode=true`、`duration=1800`、`respawn=none`
- 这些实际是车辆 DM / 技巧图，不是带 checkpoint 的竞速图

当前 `rst_ui` 还没有地图资源生命周期：不会 start / stop 这些 map resource，`config.maps` 仍是手写出生点，top 3 也还没进 `mapPool`。因此它们目前只是**已安装、可被扫描**，还不能直接走通现有竞速流程。要接入需要补：

1. 选图时 start 新 map resource、stop 旧图
2. 从 `map-catalog.json` 读取 spawnpoint / 车型
3. 为没有 checkpoint 的 DM 图提供终点/目标数据，或改用击杀/生存排名
4. 处理地图自带 vehicle、racepickup 和 client 脚本与 `rst_ui` 的重复逻辑

## 赛道排行

竞速排行榜需要赛道检查点 / 圈数数据才能按“完成赛道”结算：

- 计划每张图配置 `checkpoints` 和 `laps`，服务端按顺序校验检查点，记录完成时间与名次
- 当前还没有检查点数据，因此暂时没有圈速 / 名次结算
- 地图流行度以后可以按完成次数、投票数或外部抓取结果更新

## 账号与数据

- 账号名 = 玩家进入服务器时的昵称；密码用 `passwordHash(..., 'bcrypt')` 哈希后存入 SQLite
- 数据库：`server/mods/deathmatch/databases/global/rst_ui_accounts.db`（运行时生成，已被忽略）
- 游客不写数据库，重进服务器需要重新认证
- 登录 / 注册失败会通过 CEF toast 提示

## 目录结构

```
rst-mta-lite/
├─ tools/mtavault/                           # mtavault 元数据抓取（手动运行）
│  ├─ fetch-dm-maps.mjs                      # API 分页 / DM 过滤 / 封面下载
│  └─ output/                                # 抓取结果（不入库）
├─ cef/                                      # 客户端 UI 源码（Vue 3 + Vite + TS）
│  ├─ src/
│  │  ├─ mta/bridge.ts                       # window.rst / mta.triggerEvent 桥
│  │  ├─ mta/protocol.ts                     # state / vote / rewind 等类型
│  │  ├─ stores/ui.ts                        # 前端状态机
│  │  ├─ views/AuthView.vue                  # 登录 / 注册 / 游客
│  │  ├─ views/StageSelectView.vue           # 选择舞台
│  │  ├─ views/MenuView.vue                  # F2 菜单
│  │  ├─ views/VoteView.vue                  # 换图投票
│  │  ├─ views/ModeVoteView.vue              # 训练 / 竞技模式投票
│  │  ├─ components/GameHud.vue              # 游戏内 HUD
│  │  ├─ components/MapTimer.vue             # 顶部地图剩余 / 个人计时
│  │  ├─ components/ChatPanel.vue            # 左上角常驻 CEF 聊天
│  │  ├─ components/Speedometer.vue          # 载具速度 / 血量 / 氮气
│  │  ├─ components/SpawnCountdown.vue       # 3-2-1-GO 出生倒计时
│  │  ├─ components/ReadyOverlay.vue         # 竞技模式全员准备
│  │  ├─ components/CompetitionPanel.vue     # 右侧竞技命数 / 排行
│  │  ├─ components/HelpOverlay.vue          # F1 操作帮助
│  │  ├─ components/BuildTag.vue             # 右下角构建日期 / hash
│  │  └─ components/RewindOverlay.vue        # rewind 覆盖层
│  └─ vite.config.ts                         # 构建输出到 rst_ui/ui/
└─ server/mods/deathmatch/resources/
   └─ [rst]/rst_ui/                          # CEF UI + 玩法资源
      ├─ meta.xml
      ├─ shared/config.lua                   # 地图 / 房间 / 时长 / 热度权重
      ├─ server/accounts.lua                 # SQLite + bcrypt 账号
      ├─ server/mapstats.lua                 # 地图游玩次数 / 有效热度
      ├─ server/rooms.lua                    # 房间、回合、投票
      ├─ server/main.lua                     # 会话、action、状态推送
      ├─ client/main.lua                     # 浏览器、输入、登录/观战/HUD
      ├─ client/rewind.lua                   # 长按 Y 回放
      ├─ sounds/click.wav, confirm.wav       # UI 音效
      └─ ui/                                 # 构建产物（不入库）
```

## 本地运行

```powershell
cd cef
pnpm install
pnpm build

cd ..\server
.\"MTA Server.exe"
```

客户端打开 `mtasa://127.0.0.1:22003`。

> 仓库不带官方默认资源，启动日志里的 `Couldn't find resource admin/...` 可忽略，或在 `mtaserver.conf` 里注释掉对应行。`rst_ui` 需要在本机 `mtaserver.conf` 中加入 `<resource src="rst_ui" startup="1"/>`（该文件不入库）。

## 前端开发

```powershell
cd cef
pnpm dev          # http://127.0.0.1:5173
pnpm type-check   # vue-tsc
pnpm build        # 固定文件名输出到 rst_ui/ui/
```

浏览器里没有 `window.mta`，会走 mock 日志。控制台可以用 `__rstMockState({...})` 直接模拟服务端状态，例如：

```js
__rstMockState({
  phase: 'stage',
  serverName: 'dev',
  me: { name: 'DevPlayer', guest: false },
  rooms: [
    { id: 'main', name: 'DeathMatch · 主舞台', mapName: 'Grove Street', author: 'RST Team', players: 2, spectators: 1, active: true, timeLeft: 900 },
  ],
})
```

### 图标（离线）

图标使用 Iconify 的 `lucide` 图标集，通过 `unplugin-icons` 在构建时编译成**内联 SVG**：

- 依赖：`@iconify-json/lucide`（图标数据，随 `pnpm-lock.yaml` 固定版本）
- 构建后不请求 `api.iconify.design`，CEF 只加载本地 `ui/assets/app.js`
- 用法：`import IconMap from '~icons/lucide/map'`，模板里 `<IconMap class="icon" />`

> `meta.xml` 依赖固定产物名 `ui/assets/app.js`、`ui/assets/style.css`。改 `vite.config.ts` 的输出文件名时必须同步 `meta.xml`。

## CEF 通信

- **加载**：`createBrowser(w, h, true, true)` → `onClientBrowserCreated` → `loadBrowserURL(browser, "http://mta/local/ui/index.html")`
- **渲染**：`onClientRender` 里 `dxDrawImage(0, 0, w, h, browser)`
- **输入**：`showCursor` + `guiSetInputEnabled` + `toggleAllControls`；鼠标经 `onClientCursorMove` / `onClientClick` / `onClientMouseWheel` → `injectBrowserMouse*`，键盘用 `focusBrowser`
- **JS → Lua**：`emitAction(action, payload)` → `mta.triggerEvent('rst:ui:action', json)`
- **Lua → JS**：`executeBrowserJavascript(browser, 'window.rst.dispatch("state", json)')`
- **服务端 → 客户端**：`triggerClientEvent(player, 'rst:ui:state', ...)`，客户端缓存后转发给页面
- **聊天**：原生 `onClientChatMessage` 被拦截后转成 `chatMessage`；玩家发送走 `chat:send` action，服务端再广播 `rst:ui:chat`
- **调试**：菜单「打开 DevTools」或 `toggleBrowserDevTools(browser)`

## 调试

- 游戏内快捷键无响应时，在 F8 控制台执行 `uidiag`，会输出：
  `phase / mode / interactive / browserReady / CEF focus / menu / chat / help / vote / ready / rewindLives / F1/F2/T 绑定数量`
- 客户端收到状态时会 `pcall` 保护状态处理；即使 Lua 状态处理报错，也会先把状态送进 CEF
- 非交互状态每帧检查并释放 CEF 键盘焦点，避免浏览器抢焦点导致 `bindKey` 失效
- MTA 客户端不要用管理员权限启动；控制台出现 `Running as Administrator - browser features may be limited` 时，CEF 可能被限制
- 启动日志里缺失的 stock resources 已从本机 `mtaserver.conf` 移除，现在只加载 `rst_ui`

## 已验证 / 未验证

已验证（本机）：

- `pnpm type-check`、`pnpm build` 通过
- 全部 Lua 脚本用 luaparse（5.1 语法）解析通过
- 服务端启动：资源加载 0 失败；SQLite 建库成功
- 账号链路自检：bcrypt 创建 / 正确密码校验 / 错误密码拒绝
- Headless Chrome 渲染登录、选舞台、HUD（含赛道作者面板）、菜单、投票、rewind 覆盖层，以及点击事件与 `rst:ui:action` 参数
- 聊天：原生消息 / 玩家消息渲染、T 输入框、Enter 发送动作（`chat:send` + `chat:close`）在 Headless Chrome 中验证通过
- 载具仪表：速度 / 血量 / 氮气 / 档位在 Headless Chrome 中验证渲染
- 顶部计时：地图名 / 剩余倒计时 / 个人本图时长在 Headless Chrome 中验证渲染
- 观战切换：跟随对象与左右键提示在 Headless Chrome 中验证渲染
- 操作帮助：快捷键分组、F1/Esc 关闭在 Headless Chrome 中验证渲染
- 出生倒计时：3-2-1-GO 环形动画在 Headless Chrome 中验证渲染
- 地图投票：随机图池 / 名称排序 / 模糊搜索 / 热度排序在 Headless Chrome 中验证渲染
- 光标策略：强制场景 / 自动隐藏 / F3 自由光标 / F2 光标设置
- DPI 缩放：720p、1080p、1440p、4K 的缩放比例与布局在 Headless Chrome 中验证
- 竞技流程：准备面板、右侧命数 / 距离排行、存活人数、模式投票、纯 OB 切换在 Headless Chrome / 类型检查中验证
- mtavault 抓取脚本：单页小样本运行通过，输出作者 / 上传日期 / 下载量 / 标签 / YouTube 封面等字段
- 构建信息：构建日期 / git hash 注入与右下角水印在 Headless Chrome 中验证
- 图标全部内联到构建产物，构建后的 JS 中没有外部图标请求

未验证（需要真实 MTA 客户端）：

- 游戏内 CEF 的鼠标 / 键盘注入手感
- 观战相机、rewind 冻结与速度恢复效果

## 说明与限制

- 当前 rewind 是客户端本地记录 / 回放（50ms 采样，最近 8 秒），服务端没有反作弊校验
- 登录密码经 MTA 客户端事件发到服务端后再 bcrypt 存储；正式运营建议后续换用独立 Web 登录或额外加密
- 地图目前只是出生点配置，没有加载赛道资源和检查点
- 圈数 / 检查点 / 名次结算还没做，当前是出生给赛车 + 换图 / 投票的竞速基础框架
- Ghost 的透明与车辆间碰撞关闭都在客户端完成；服务端不额外校验
- 竞技命数由服务端在收到 rewind 事件时扣减；rewind 本身仍是客户端本地回放，没有独立反作弊
- 竞技排行按到终点距离（终点坐标目前是占位），不是按圈速 / 完成时间；终点数据接入真实赛道后替换
- 距离是直线距离，不是沿赛道距离；后续有检查点后可以改成沿赛道的剩余进度
- top 3 mtavault 地图没有 checkpoint，但可用 Hunter pickup 作为终点；没有 Hunter 时仅能按远离起点距离估算，绕圈/回转赛道会不准
- mtavault 脚本默认不抓、不自动更新配置；全量抓取需要手动运行并自行确认源站条款
- 服务器内游玩次数在资源重启后保留，但必须先重启 `rst_ui` 才会加载 `mapstats.lua`

## 约定

- 资源命名 `rst_` 前缀；归类目录 `[rst]`（方括号目录不会作为资源加载）。
- 换行统一 LF；`.editorconfig`：Lua / XML 4 空格，前端 2 空格。
- 新建资源后在本机 `mtaserver.conf` 里加 `<resource src="..." startup="1"/>`（该文件不入库）。
