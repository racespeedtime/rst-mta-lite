/**
 * Lua ↔ JS 通信协议。
 *
 * JS → Lua：emitAction() → mta.triggerEvent('rst:ui:action', jsonString)
 * Lua → JS：executeBrowserJavascript(browser, 'window.rst.dispatch("state", jsonString)')
 */

export type Phase = 'auth' | 'stage' | 'playing'
export type PlayMode = 'playing' | 'spectating'

export interface RoomSummary {
  id: string
  name: string
  mapName: string
  players: number
  spectators: number
  active: boolean
  timeLeft: number
  voteActive?: boolean
  mode?: PlayMode
}

export interface VoteOption {
  id: string
  name: string
  votes: number
}

export interface VoteState {
  active: boolean
  timeLeft: number
  options: VoteOption[]
  mine?: string
}

export interface StatePayload {
  phase: Phase
  serverName: string
  me: {
    name: string
    guest: boolean
    mode?: PlayMode
  }
  rooms?: RoomSummary[]
  room?: RoomSummary
  vote?: VoteState
  canStartVote?: boolean
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

export interface StatsPayload {
  health: number
  armor: number
}

export type BridgeEventMap = {
  state: StatePayload
  rewind: RewindPayload
  menu: MenuPayload
  toast: ToastPayload
  stats: StatsPayload
}
