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
  messages: [] as ChatEntry[],
  busy: false,
  authError: '',
  health: 100,
  armor: 0,
  vehicle: null as VehiclePayload | null,
  rewind: { active: false, progress: 0, seconds: 0 } as RewindPayload,
})
