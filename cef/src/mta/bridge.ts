import type { BridgeEventMap } from './protocol'

type Handler = (payload: unknown) => void

interface MtaBridgeGlobal {
  triggerEvent: (event: string, ...args: unknown[]) => void
}

declare global {
  interface Window {
    mta?: MtaBridgeGlobal
    rst?: {
      dispatch: (event: string, payloadJson?: string) => void
    }
    __rstMockState?: (state: unknown) => void
  }
}

const handlers = new Map<string, Set<Handler>>()

export function isMtaClient(): boolean {
  return typeof window !== 'undefined' && typeof window.mta?.triggerEvent === 'function'
}

function dispatchLocal(event: string, payload: unknown): void {
  const set = handlers.get(event)
  if (!set) return
  for (const handler of set) handler(payload)
}

/** 挂载 window.rst，供 Lua 通过 executeBrowserJavascript 调用 */
export function installBridge(): void {
  window.rst = {
    dispatch(event, payloadJson) {
      let payload: unknown
      if (payloadJson) {
        try {
          payload = JSON.parse(payloadJson)
        } catch (error) {
          console.error(`[rst-ui] 事件 ${event} 的数据不是合法 JSON`, error, payloadJson)
          return
        }
      }
      dispatchLocal(event, payload)
    },
  }

  if (import.meta.env.DEV) {
    window.__rstMockState = (state) => {
      window.rst?.dispatch('state', JSON.stringify(state))
    }
  }
}

export function onBridge<K extends keyof BridgeEventMap>(
  event: K,
  handler: (payload: BridgeEventMap[K]) => void,
): () => void {
  let set = handlers.get(event)
  if (!set) {
    set = new Set()
    handlers.set(event, set)
  }
  set.add(handler as Handler)
  return () => {
    set.delete(handler as Handler)
  }
}

/** 触发 MTA 客户端事件（统一加 rst:ui: 前缀，参数序列化为 JSON 字符串） */
export function emitToLua(event: string, payload?: unknown): void {
  const eventName = event.startsWith('rst:ui:') ? event : `rst:ui:${event}`
  const data = payload === undefined ? '{}' : JSON.stringify(payload)
  if (isMtaClient()) {
    window.mta!.triggerEvent(eventName, data)
    return
  }
  if (import.meta.env.DEV) {
    console.info('[rst-ui:mock] JS → Lua', eventName, data)
  }
}

/** 业务动作，统一走 rst:ui:action */
export function emitAction(action: string, payload?: Record<string, unknown>): void {
  emitToLua('action', { ...payload, action })
}

/** 纯浏览器开发时模拟服务端状态 */
export function installMockServer(): void {
  if (isMtaClient() || !import.meta.env.DEV) return

  const mockState = {
    phase: 'auth',
    serverName: 'rst-mta-lite · browser mock',
    me: { name: 'DevPlayer', guest: false },
  }

  window.setTimeout(() => {
    window.rst?.dispatch('state', JSON.stringify(mockState))
    window.rst?.dispatch('stats', JSON.stringify({ health: 87, armor: 42 }))
  }, 300)
}
