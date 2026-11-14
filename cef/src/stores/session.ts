import { reactive } from 'vue'

export const session = reactive({
  playerName: 'player',
  serverName: 'rst-mta-lite',
  online: 0,
  revision: 'dev',
  health: 100,
  armor: 0,
})
