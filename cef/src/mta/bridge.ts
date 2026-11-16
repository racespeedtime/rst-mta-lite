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
      setViewportSize?: (width: number, height: number) => void
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
  for (const handler of set) {
    try {
      handler(payload)
    } catch (error) {
      console.error(`[rst-ui] 处理事件 ${event} 失败`, error)
    }
  }
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

      // MTA 的 toJSON 会把顶层对象包成单元素数组：[ { ... } ]
      if (Array.isArray(payload) && payload.length === 1) {
        payload = payload[0]
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

type MockActionHandler = (action: string, payload: Record<string, unknown>) => void
let mockActionHandler: MockActionHandler | null = null

/** 业务动作，统一走 rst:ui:action */
export function emitAction(action: string, payload?: Record<string, unknown>): void {
  emitToLua('action', { ...payload, action })
  if (!isMtaClient() && import.meta.env.DEV) {
    mockActionHandler?.(action, payload ?? {})
  }
}

/** 纯浏览器开发时模拟服务端：状态、地图池分页、详情、投票都能点 */
export function installMockServer(): void {
  if (isMtaClient() || !import.meta.env.DEV) return

  const AUTHORS = ['Nice', 'Chipy', 'Viko', 'BaSzTy', 'Gerc', 'BreAkeR', 'Nebla', 'Conquer', 'Straim']
  const NAMES = [
    'A New Dawn', 'Silent Hill', 'Atlas', 'Descendant', 'Ember', 'Drift', 'Canyon', 'Neon',
    'Sunset', 'Vortex', 'Plateau', 'Blackout', 'Bloody Imaginary', 'Celebration', 'Decayed Districts',
  ]

  const maps = Array.from({ length: 4482 }, (_, index) => {
    const name = `[DM] ${NAMES[index % NAMES.length]} ${Math.floor(index / NAMES.length) + 1}`
    const author = AUTHORS[index % AUTHORS.length]
    const downloads = (index * 37) % 9000
    const year = 2015 + (index % 12)
    const month = String(1 + (index % 12)).padStart(2, '0')
    const day = String(1 + (index % 28)).padStart(2, '0')
    return {
      id: `mock-map-${index + 1}`,
      resource: `mock-map-${index + 1}`,
      name,
      author,
      dimension: 0,
      downloads,
      plays: (index * 13) % 500,
      popularity: downloads + ((index * 13) % 500) * 5,
      uploadedAt: `${year}-${month}-${day}`,
    }
  }).sort((a, b) => b.popularity - a.popularity || a.name.localeCompare(b.name, 'zh-CN'))

  function detailOf(map: (typeof maps)[number]) {
    return {
      id: map.id,
      name: map.name,
      author: map.author,
      resource: map.resource,
      mapSrc: `${map.id}.map`,
      spawns: 8 + (map.popularity % 40),
      pickups: map.popularity % 60,
      vehicles: [411, 522, 425],
      dimension: 0,
      finish: true,
      cover: null,
      youtube: null,
      sourceUrl: `https://mtavault.com/map/${map.id}`,
      uploadedAt: '2026-01-02T03:04:05.000Z',
      downloads: map.downloads,
      difficulty: '中等',
      fileSize: 12_345_678,
      tags: ['DM', '城市', '夜间'],
      plays: map.plays,
      popularity: map.popularity,
      current: false,
    }
  }

  let currentVote: Record<string, unknown> | null = null

  function voteOf(map: (typeof maps)[number]) {
    const others = maps.filter((item) => item.id !== map.id).slice(0, 4)
    return {
      active: true,
      forced: false,
      timeLeft: 30,
      timeLeftMs: 30_000,
      started: true,
      nominee: map.id,
      nomineeBy: 'DevPlayer',
      abstain: 1,
      options: [map, ...others].map((item) => ({
        id: item.id,
        name: item.name,
        author: item.author,
        popularity: item.popularity,
        plays: item.plays,
        votes: item.id === map.id ? 1 : 0,
        nominee: item.id === map.id,
      })),
      // 提名自动算发起人的 1 票
      mine: map.id as string | undefined,
    }
  }

  function stateOf(overrides: Record<string, unknown> = {}) {
    const roomMap = maps[7]
    return {
      phase: 'playing',
      serverName: 'rst-mta-lite · browser mock',
      mapPoolSize: maps.length,
      mapPoolEmpty: false,
      me: { name: 'DevPlayer', guest: false, registered: true, mode: 'playing', team: null },
      mode: 'training',
      competitiveMode: 'solo',
      lives: null,
      ob: false,
      ready: { waiting: false, ready: 0, total: 1, me: false, canReady: false },
      competition: null,
      raceResult: null,
      personalBest: 83.42,
      personalBestMs: 83420,
      mapTime: 125,
      mapTimeMs: 125000,
      room: {
        id: 'main',
        name: 'DeathMatch · 服务器',
        mapId: roomMap.id,
        mapName: roomMap.name,
        author: roomMap.author,
        players: 1,
        spectators: 0,
        active: true,
        timeLeft: 2400,
        timeLeftMs: 2_400_000,
        gameMode: 'training',
        competitiveMode: 'solo',
        waiting: false,
        mapDetails: detailOf(roomMap),
      },
      canStartVote: true,
      voteCooldown: 0,
      canStartModeVote: true,
      modeVoteCooldown: 0,
      vote: currentVote,
      modeVote: null,
      ...overrides,
    }
  }

  mockActionHandler = (action, payload) => {
    if (action === 'maps:page') {
      const page = Number(payload.page) || 1
      const pageSize = Number(payload.pageSize) || 30
      const keyword = String(payload.search || '').trim().toLowerCase()
      const sortFieldRaw = String(payload.sort || 'popularity')
      const sortField = ['popularity', 'downloads', 'plays', 'name', 'uploaded'].includes(sortFieldRaw)
        ? sortFieldRaw
        : 'popularity'
      const ascending = String(payload.order || 'desc') === 'asc'

      const dateFrom = String(payload.dateFrom || '').trim()
      const dateTo = String(payload.dateTo || '').trim()

      const hits = (
        keyword
          ? maps.filter((map) => `${map.name}\n${map.author}\n${map.id}`.toLowerCase().includes(keyword))
          : [...maps]
      )
        .filter((map) => {
          if (/^\d{4}-\d{2}-\d{2}$/.test(dateFrom) && map.uploadedAt < dateFrom) return false
          if (/^\d{4}-\d{2}-\d{2}$/.test(dateTo) && map.uploadedAt > dateTo) return false
          return true
        })
        .sort((a, b) => {
          let diff = 0
          if (sortField === 'name') diff = a.name.localeCompare(b.name, 'zh-CN')
          else if (sortField === 'downloads') diff = a.downloads - b.downloads
          else if (sortField === 'plays') diff = a.plays - b.plays
          else if (sortField === 'uploaded') diff = a.uploadedAt.localeCompare(b.uploadedAt)
          else diff = a.popularity - b.popularity
          if (diff === 0) return b.popularity - a.popularity || a.name.localeCompare(b.name, 'zh-CN')
          return ascending ? diff : -diff
        })

      const pages = Math.max(1, Math.ceil(hits.length / pageSize))
      const current = Math.min(Math.max(1, page), pages)
      const start = (current - 1) * pageSize
      window.rst?.dispatch(
        'mapsPage',
        JSON.stringify({
          page: current,
          pageSize,
          total: hits.length,
          pages,
          search: keyword,
          sort: sortField,
          order: ascending ? 'asc' : 'desc',
          dateFrom,
          dateTo,
          requestId: payload.requestId,
          items: hits.slice(start, start + pageSize),
        }),
      )
      return
    }

    if (action === 'maps:detail') {
      const id = String(payload.mapId || '')
      const map = maps.find((item) => item.id === id)
      window.rst?.dispatch(
        'mapDetail',
        JSON.stringify({ requestId: payload.requestId, mapId: id, detail: map ? detailOf(map) : null }),
      )
      return
    }

    if (action === 'maps:vote' || action === 'vote:start') {
      const id = String(payload.mapId || maps[0].id)
      const map = maps.find((item) => item.id === id) || maps[0]
      currentVote = voteOf(map)
      window.rst?.dispatch('state', JSON.stringify(stateOf({ vote: currentVote })))
      window.rst?.dispatch('toast', JSON.stringify({ text: `模拟：已发起换图投票（${map.name}）` }))
      return
    }

    if (action === 'vote:cast' || action === 'vote:abstain') {
      if (!currentVote) return
      currentVote.mine = action === 'vote:abstain' ? '__abstain' : String(payload.map || '')
      window.rst?.dispatch('state', JSON.stringify(stateOf({ vote: currentVote })))
      return
    }

    if (action === 'voteui') {
      window.rst?.dispatch('voteui', JSON.stringify({ open: payload.open === true }))
      return
    }
  }

  if (window.location.search.includes('vote')) {
    currentVote = voteOf(maps[0])
  }

  window.setTimeout(() => {
    window.rst?.dispatch('state', JSON.stringify(stateOf()))
  }, 300)
}