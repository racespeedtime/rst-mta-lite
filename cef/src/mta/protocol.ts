/**
 * Lua ↔ JS 通信协议。
 *
 * JS → Lua：emitAction() → mta.triggerEvent('rst:ui:action', jsonString)
 * Lua → JS：executeBrowserJavascript(browser, 'window.rst.dispatch("state", jsonString)')
 */

export type Phase = 'auth' | 'stage' | 'playing'
export type PlayMode = 'playing' | 'spectating'
export type GameMode = 'training' | 'competitive'
export type CompetitiveFormat = 'solo' | 'team'
export type TeamId = 'red' | 'blue'
export type ModeVoteId = 'training' | 'competitive' | 'team'

export interface TeamScore {
  id: TeamId
  name: string
  score: number
  finished: number
  rank: number
  bestRank?: number
}

export interface RaceResultEntry {
  rank: number
  name: string
  team?: TeamId | null
  points?: number
  elapsed: number
  elapsedMs?: number
  me?: boolean
}

export interface RaceResultState {
  active: boolean
  mode: 'training' | 'competitive'
  format?: CompetitiveFormat
  final: boolean
  countdown: number
  countdownMs?: number
  returnIn?: number
  returnInMs?: number
  resultsIn?: number
  resultsInMs?: number
  top: RaceResultEntry[]
  teams?: TeamScore[]
  me?: {
    rank: number
    elapsed: number
    elapsedMs?: number
  } | null
}

export interface MapDetails {
  id?: string
  name: string
  author: string
  resource: string
  mapSrc?: string
  spawns: number
  pickups?: number
  vehicles: number[]
  dimension: number
  finish: boolean
  cover?: string | null
  youtube?: string | null
  sourceUrl?: string | null
  uploadedAt?: string | null
  downloads?: number
  difficulty?: string | null
  fileSize?: number
  tags?: string[]
  plays?: number
  popularity?: number
  current?: boolean
}

export interface RoomSummary {
  id: string
  name: string
  mapId?: string | null
  mapName: string
  author: string
  mapDetails?: MapDetails | null
  players: number
  spectators: number
  active: boolean
  timeLeft: number
  timeLeftMs?: number
  voteActive?: boolean
  mode?: PlayMode
  gameMode?: GameMode
  competitiveMode?: CompetitiveFormat
  waiting?: boolean
}

export interface VoteOption {
  id: string
  name: string
  author: string
  popularity: number
  plays?: number
  votes: number
  nominee?: boolean
}

export interface VoteState {
  active: boolean
  /** 强制投票（回合到点/完赛）自动弹全屏；false 表示玩家自发投票，按 F4 打开 */
  forced?: boolean
  timeLeft: number
  timeLeftMs?: number
  options: VoteOption[]
  nominee?: string | null
  nomineeBy?: string | null
  abstain?: number
  started?: boolean
  mine?: string
}

export interface ModeVoteOption {
  id: ModeVoteId
  name: string
  description: string
  votes: number
}

export interface ModeVoteState {
  started?: boolean
  forced?: boolean
  active: boolean
  timeLeft: number
  timeLeftMs?: number
  currentMode: ModeVoteId
  options: ModeVoteOption[]
  mine?: ModeVoteId
}

export interface ReadyState {
  waiting: boolean
  ready?: number
  total?: number
  me?: boolean
  canReady?: boolean
  teamMode?: boolean
  team?: TeamId | null
  teams?: {
    red: number
    blue: number
  }
  balanced?: boolean
}

export interface CompetitionPlayer {
  rank: number
  name: string
  team?: TeamId | null
  lives: number
  alive: boolean
  me: boolean
  finished?: boolean
  points?: number
}

export interface CompetitionState {
  mode: 'competitive'
  format?: CompetitiveFormat
  alive: number
  total: number
  waiting: boolean
  teams?: TeamScore[]
  players: CompetitionPlayer[]
}

export interface MapPoolItem {
  id: string
  resource: string
  name: string
  author: string
  dimension: number
  downloads?: number
  popularity?: number
  plays?: number
  uploadedAt?: string | null
  current?: boolean
}

export interface MapPoolDetailPayload {
  requestId?: number
  mapId?: string
  detail?: MapDetails | null
}

export type MapPoolSortField = 'popularity' | 'downloads' | 'plays' | 'name' | 'uploaded'
export type MapPoolSortOrder = 'asc' | 'desc'

export interface MapPoolPage {
  page: number
  pageSize: number
  total: number
  pages: number
  search: string
  sort?: MapPoolSortField
  order?: MapPoolSortOrder
  requestId?: number
  items: MapPoolItem[]
}

export interface MapRecordItem {
  rank: number
  name: string
  bestMs: number
  updatedAt?: number
}

export interface MapRecordsPage {
  page: number
  pageSize: number
  total: number
  pages: number
  mapId: string
  mapName: string
  mapAuthor: string
  requestId?: number
  items: MapRecordItem[]
}

export interface ScoreboardPlayer {
  id: number
  name: string
  status: string
  statusKey: string
  fps: number
  ping: number
  me: boolean
}

export interface ScoreboardPayload {
  open?: boolean
  players?: ScoreboardPlayer[]
  count?: number
  serverName?: string
}

export interface ScoreboardScrollPayload {
  delta: number
}

export interface WarpPoint {
  id: number
  index: number
  x: number
  y: number
  z: number
  rx: number
  ry: number
  rz: number
  at: number
  vehicle: number
}

export interface WarpsPayload {
  items: WarpPoint[]
}

export interface StatePayload {
  phase: Phase
  serverName: string
  mapPoolSize?: number
  mapPoolEmpty?: boolean
  me: {
    name: string
    guest: boolean
    registered?: boolean | null
    mode?: PlayMode
    team?: TeamId | null
  }
  rooms?: RoomSummary[]
  room?: RoomSummary
  mode?: GameMode
  competitiveMode?: CompetitiveFormat
  lives?: number
  ob?: boolean
  ready?: ReadyState
  competition?: CompetitionState | null
  raceResult?: RaceResultState | null
  personalBest?: number | null
  personalBestMs?: number | null
  vote?: VoteState
  modeVote?: ModeVoteState
  canStartVote?: boolean
  voteCooldown?: number
  canStartModeVote?: boolean
  modeVoteCooldown?: number
  mapTime?: number
  mapTimeMs?: number
}

export interface RewindPayload {
  active: boolean
  progress: number
  seconds: number
  speed?: number
}


export interface MenuPayload {
  open: boolean
}

export interface ToastPayload {
  text: string
}

export type ChatKind = 'player' | 'system' | 'native'

export interface ChatMessagePayload {
  kind: ChatKind
  name?: string
  team?: TeamId | null
  text: string
  time?: number
  color?: { r: number; g: number; b: number }
  nativeType?: number
}

export interface ChatEntry extends ChatMessagePayload {
  id: number
  time: number
}

export interface ChatOpenPayload {
  open: boolean
}

export interface VehiclePayload {
  active: boolean
  name?: string
  speed?: number
  gear?: number
  healthPercent?: number
  nitroPercent?: number
  nitroCount?: number
  nitroInfinite?: boolean
  nitroActive?: boolean
  nitroRecharging?: boolean
  hasNitro?: boolean
}

export interface SpectatePayload {
  name?: string
}

export interface HelpPayload {
  open: boolean
}

export interface CountdownPayload {
  active?: boolean
  duration?: number
}

export interface CursorPayload {
  mode: 'auto' | 'always'
  visible: boolean
  forced: boolean
  free: boolean
}

export interface VoteUiPayload {
  open?: boolean
}

export interface ModalPayload {
  open?: boolean
}

export type BridgeEventMap = {
  state: StatePayload
  rewind: RewindPayload

  menu: MenuPayload
  toast: ToastPayload
  chat: ChatOpenPayload
  chatMessage: ChatMessagePayload
  vehicle: VehiclePayload
  spectate: SpectatePayload
  help: HelpPayload
  countdown: CountdownPayload
  cursor: CursorPayload
  mapsPage: MapPoolPage
  voteui: VoteUiPayload
  modevoteui: ModalPayload
  mappool: ModalPayload
  mapdetails: ModalPayload
  recordsmodal: ModalPayload
  mapDetail: MapPoolDetailPayload
  recordsPage: MapRecordsPage
  scoreboard: ScoreboardPayload
  scoreboardScroll: ScoreboardScrollPayload
  warps: WarpsPayload
}
