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
  me?: boolean
}

export interface RaceResultState {
  active: boolean
  mode: 'training' | 'competitive'
  format?: CompetitiveFormat
  final: boolean
  countdown: number
  returnIn?: number
  resultsIn?: number
  top: RaceResultEntry[]
  teams?: TeamScore[]
  me?: {
    rank: number
    elapsed: number
  } | null
}

export interface MapDetails {
  name: string
  author: string
  resource: string
  spawns: number
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
}

export interface RoomSummary {
  id: string
  name: string
  mapName: string
  author: string
  mapDetails?: MapDetails | null
  players: number
  spectators: number
  active: boolean
  timeLeft: number
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
}

export interface VoteState {
  active: boolean
  timeLeft: number
  options: VoteOption[]
  mine?: string
}

export interface ModeVoteOption {
  id: ModeVoteId
  name: string
  description: string
  votes: number
}

export interface ModeVoteState {
  active: boolean
  timeLeft: number
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
  distance?: number
  progress?: number
  finished?: boolean
  points?: number
}

export interface CompetitionState {
  mode: 'competitive'
  format?: CompetitiveFormat
  alive: number
  total: number
  waiting: boolean
  finish?: boolean
  ranking?: 'finish' | 'progress' | 'lives'
  teams?: TeamScore[]
  players: CompetitionPlayer[]
}

export interface ProgressState {
  percent: number
  distance: number
  finished: boolean
}

export interface StatePayload {
  phase: Phase
  serverName: string
  mapPoolSize?: number
  mapPoolEmpty?: boolean
  me: {
    name: string
    guest: boolean
    mode?: PlayMode
    team?: TeamId | null
  }
  rooms?: RoomSummary[]
  room?: RoomSummary
  mode?: GameMode
  competitiveMode?: CompetitiveFormat
  progress?: ProgressState | null
  lives?: number
  ob?: boolean
  ready?: ReadyState
  competition?: CompetitionState | null
  raceResult?: RaceResultState | null
  personalBest?: number | null
  vote?: VoteState
  modeVote?: ModeVoteState
  canStartVote?: boolean
  voteCooldown?: number
  canStartModeVote?: boolean
  modeVoteCooldown?: number
  mapTime?: number
}

export interface RewindPayload {
  active: boolean
  progress: number
  seconds: number
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
}
