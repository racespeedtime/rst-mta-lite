import { reactive } from 'vue'

import type { ChatEntry, Phase, PlayMode, RewindPayload, RoomSummary, VoteState } from '@/mta/protocol'

export const ui = reactive({
  phase: 'auth' as Phase,
  serverName: 'rst-mta-lite',
  playerName: 'player',
  guest: false,
  mode: 'playing' as PlayMode,
  rooms: [] as RoomSummary[],
  room: null as RoomSummary | null,
  vote: null as VoteState | null,
  canStartVote: false,
  menuOpen: false,
  chatOpen: false,
  messages: [] as ChatEntry[],
  busy: false,
  authError: '',
  health: 100,
  armor: 0,
  rewind: { active: false, progress: 0, seconds: 0 } as RewindPayload,
})
