/**
 * Lua ↔ JS 通信协议。
 *
 * JS → Lua：mta.triggerEvent('rst:ui:xxx', jsonString)（bridge.emitToLua 会自动补前缀）
 * Lua → JS：executeBrowserJavascript(browser, 'window.rst.dispatch("xxx", jsonString)')
 */

export interface BootstrapPayload {
  playerName: string
  serverName: string
  online: number
  revision: string
}

export interface StatsPayload {
  health: number
  armor: number
}

export interface MenuPayload {
  open: boolean
}

export interface ToastPayload {
  text: string
}

export type BridgeEventMap = {
  bootstrap: BootstrapPayload
  stats: StatsPayload
  menu: MenuPayload
  toast: ToastPayload
}
