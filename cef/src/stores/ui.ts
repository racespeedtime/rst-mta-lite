import { reactive } from 'vue'

import type {
  ChatEntry,
  Phase,
  PlayMode,
  RewindPayload,
  RoomSummary,
  VehiclePayload,
  VoteState,
} from '@/mta/protocol'

export const ui = reactive({
  phase: 'auth' as Phase,
  serverName: 'rst-mta-lite',
  playerName: 'player',
  guest: false,
  mode: 'playing' as PlayMode,
  spectateName: '',
  rooms: [] as RoomSummary[],
  room: null as RoomSummary | null,
  vote: null as VoteState | null,
  canStartVote: false,
  mapTime: 0,
  menuOpen: false,
  chatOpen: false,
  helpOpen: false,
  messages: [] as ChatEntry[],
  countdown: { active: false, startedAt: 0, duration: 3 },
  busy: false,
  authError: '',
  vehicle: null as VehiclePayload | null,
  rewind: { active: false, progress: 0, seconds: 0 } as RewindPayload,
})
