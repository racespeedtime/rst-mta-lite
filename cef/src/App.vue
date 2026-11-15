<script setup lang="ts">
import { onMounted, onUnmounted, ref, watch } from 'vue'

import GameHud from '@/components/GameHud.vue'
import ChatPanel from '@/components/ChatPanel.vue'
import MapTimer from '@/components/MapTimer.vue'
import Speedometer from '@/components/Speedometer.vue'
import SpawnCountdown from '@/components/SpawnCountdown.vue'
import CompetitionPanel from '@/components/CompetitionPanel.vue'
import ReadyOverlay from '@/components/ReadyOverlay.vue'
import HelpOverlay from '@/components/HelpOverlay.vue'
import MapDetailsModal from '@/components/MapDetailsModal.vue'
import RaceResultOverlay from '@/components/RaceResultOverlay.vue'
import TrackProgress from '@/components/TrackProgress.vue'
import BuildTag from '@/components/BuildTag.vue'
import RewindOverlay from '@/components/RewindOverlay.vue'
import ToastMessage from '@/components/ToastMessage.vue'
import AuthView from '@/views/AuthView.vue'
import MenuView from '@/views/MenuView.vue'
import VoteView from '@/views/VoteView.vue'
import ModeVoteView from '@/views/ModeVoteView.vue'
import { emitAction, emitToLua, onBridge } from '@/mta/bridge'
import type { StatePayload } from '@/mta/protocol'
import { ui } from '@/stores/ui'

const toast = ref('')
let toastTimer: number | undefined
let nextMessageId = 1
const offs: Array<() => void> = []

function showToast(text: string): void {
  toast.value = text
  window.clearTimeout(toastTimer)
  toastTimer = window.setTimeout(() => {
    toast.value = ''
  }, 3200)
}

function playSound(name: string): void {
  emitToLua('sound', { name })
}

function handleRaceAudio(
  previousRace: typeof ui.raceResult,
  previousPhase: typeof ui.phase,
): void {
  const current = ui.raceResult
  if (!current || previousPhase !== 'playing') return

  const justFinished = current.me != null && previousRace?.me == null
  if (justFinished) {
    playSound('finish')
  }

  const becameFinal = current.final && previousRace?.final !== true
  if (!becameFinal || ui.mode === 'spectating') return

  if (current.format === 'team') {
    if (!ui.team) return
    const winner = current.teams?.[0]?.id
    playSound(winner === ui.team ? 'finish' : 'fail')
    return
  }

  // 个人竞技：没冲线 = 未完赛；第一名已经在对局中有冲线音效，不再重复
  if (!current.me && !justFinished) {
    playSound('fail')
  }
}

function applyState(state: StatePayload): void {
  if (!state || (state.phase !== 'auth' && state.phase !== 'stage' && state.phase !== 'playing')) {
    console.error('[rst-ui] 收到无效 state.phase', state)
    ui.phase = 'auth'
    return
  }

  const previousPhase = ui.phase
  const previousRaceResult = ui.raceResult
  const previousLives = ui.lives

  ui.phase = state.phase
  if (state.serverName) ui.serverName = state.serverName
  ui.mapPoolSize = Number(state.mapPoolSize) || 0
  ui.mapPoolEmpty = state.mapPoolEmpty === true || ui.mapPoolSize === 0
  if (state.me) {
    ui.playerName = state.me.name || ui.playerName
    ui.guest = state.me.guest === true
    ui.mode = state.me.mode || 'playing'
    ui.team = state.me.team || null
  }

  ui.competitiveMode = state.competitiveMode === 'team' ? 'team' : 'solo'
  ui.progress = state.progress || null

  ui.rooms = state.rooms || []
  ui.room = state.room || null
  ui.gameMode = state.mode === 'competitive' ? 'competitive' : 'training'
  ui.lives = typeof state.lives === 'number' ? state.lives : null
  if (previousPhase === 'playing' && previousLives !== null && previousLives > 0 && ui.lives === 0) {
    playSound('fail')
  }
  ui.ob = state.ob === true
  ui.ready = state.ready || { waiting: false, ready: 0, total: 0, me: false, canReady: false }
  ui.competition = state.competition || null
  ui.raceResult = state.raceResult || null
  handleRaceAudio(previousRaceResult, previousPhase)
  ui.personalBest = typeof state.personalBest === 'number' ? state.personalBest : null
  ui.personalBestMs =
    typeof state.personalBestMs === 'number'
      ? state.personalBestMs
      : typeof state.personalBest === 'number'
        ? state.personalBest * 1000
        : null
  ui.vote = state.vote || null
  ui.modeVote = state.modeVote || null
  ui.canStartVote = state.canStartVote === true
  ui.voteCooldown = Math.max(0, Number(state.voteCooldown) || 0)
  ui.canStartModeVote = state.canStartModeVote === true
  ui.modeVoteCooldown = Math.max(0, Number(state.modeVoteCooldown) || 0)
  ui.mapTime = Math.max(0, Number(state.mapTime) || 0)
  ui.mapTimeMs =
    typeof state.mapTimeMs === 'number'
      ? Math.max(0, state.mapTimeMs)
      : Math.max(0, (Number(state.mapTime) || 0) * 1000)

  ui.stateAt = performance.now()

  if (previousPhase !== state.phase) {
    ui.busy = false
    if (state.phase !== 'auth') ui.authError = ''
  }

  if (state.phase !== 'playing') ui.menuOpen = false
  if (
    state.phase !== 'playing' ||
    state.vote?.active ||
    state.modeVote?.active ||
    state.ready?.waiting
  ) {
    ui.chatOpen = false
    ui.helpOpen = false
  }
  if (state.phase !== 'playing') ui.countdown.active = false
}

function onAnyClick(event: MouseEvent): void {
  const target = event.target as HTMLElement | null
  if (target?.closest('button')) {
    emitToLua('sound', { name: 'click' })
  }
}

function onCursorKeydown(event: KeyboardEvent): void {
  if (event.key !== 'F3' || ui.phase !== 'playing') return
  const target = event.target as HTMLElement | null
  if (target?.closest('input, textarea, select, [contenteditable="true"]')) return
  event.preventDefault()
  emitAction('cursor:toggle')
}

onMounted(() => {
  watch(
    () => ui.mapDetailsOpen,
    (open) => {
      emitAction('mapdetails', { open })
    },
  )

  offs.push(
    onBridge('state', applyState),
    onBridge('menu', (payload) => {
      ui.menuOpen = payload.open === true
    }),
    onBridge('rewind', (payload) => {
      ui.rewind = payload
    }),
    onBridge('toast', (payload) => {
      const text = payload.text || ''
      showToast(text)
      if (ui.phase === 'auth') {
        ui.authError = text
        ui.busy = false
      }
    }),
    onBridge('chat', (payload) => {
      ui.chatOpen = payload.open === true
    }),
    onBridge('chatMessage', (payload) => {
      ui.messages.push({
        ...payload,
        id: nextMessageId++,
        time: payload.time ?? Math.floor(Date.now() / 1000),
      })
      if (ui.messages.length > ui.chatLimit) {
        ui.messages.splice(0, ui.messages.length - ui.chatLimit)
      }
    }),
    onBridge('vehicle', (payload) => {
      ui.vehicle = payload.active ? payload : null
    }),
    onBridge('spectate', (payload) => {
      ui.spectateName = payload.name || ''
    }),
    onBridge('help', (payload) => {
      ui.helpOpen = payload.open === true
    }),
    onBridge('countdown', (payload) => {
      if (payload.active === false) {
        ui.countdown.active = false
        return
      }

      ui.countdown = {
        active: true,
        startedAt: Date.now(),
        duration: Math.max(1, Number(payload.duration) || 3),
      }
    }),
    onBridge('cursor', (payload) => {
      ui.cursorMode = payload.mode === 'always' ? 'always' : 'auto'
      ui.cursorVisible = payload.visible === true
      ui.cursorForced = payload.forced === true
      ui.cursorFree = payload.free === true
    }),
  )

  document.addEventListener('click', onAnyClick, true)
  document.addEventListener('keydown', onCursorKeydown)
  emitToLua('ready')
})

onUnmounted(() => {
  offs.forEach((off) => off())
  document.removeEventListener('click', onAnyClick, true)
  document.removeEventListener('keydown', onCursorKeydown)
  window.clearTimeout(toastTimer)
})
</script>

<template>
  <div class="app-root">
    <AuthView v-if="ui.phase === 'auth'" />
    <template v-else-if="ui.phase === 'playing'">
      <GameHud />
      <MapTimer v-if="ui.room" />
      <TrackProgress v-if="ui.room" />
      <ChatPanel />
      <Transition name="speedo">
        <Speedometer v-if="ui.vehicle" />
      </Transition>
      <SpawnCountdown v-if="ui.countdown.active" />
      <CompetitionPanel v-if="ui.competition" />
      <RaceResultOverlay v-if="ui.raceResult" />
      <ReadyOverlay v-if="ui.ready.waiting" />
      <MenuView v-if="ui.menuOpen" />
      <VoteView v-if="ui.vote?.active" />
      <ModeVoteView v-if="ui.modeVote?.active" />
      <RewindOverlay v-if="ui.rewind.active" />
      <HelpOverlay v-if="ui.helpOpen" />
    </template>
    <AuthView v-else />
    <MapDetailsModal v-if="ui.mapDetailsOpen" />
    <BuildTag />
    <ToastMessage :text="toast" />
  </div>
</template>
