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
import MapPoolModal from '@/components/MapPoolModal.vue'
import RecordsModal from '@/components/RecordsModal.vue'
import ScoreboardPanel from '@/components/ScoreboardPanel.vue'
import RaceResultOverlay from '@/components/RaceResultOverlay.vue'
import BuildTag from '@/components/BuildTag.vue'
import RewindOverlay from '@/components/RewindOverlay.vue'
import ToastMessage from '@/components/ToastMessage.vue'
import AuthView from '@/views/AuthView.vue'
import StageView from '@/components/StageView.vue'
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
  emitAction('sound', { name })
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
    ui.registered = state.me.registered === true
      ? true
      : state.me.registered === false
        ? false
        : null
    ui.mode = state.me.mode || 'playing'
    ui.team = state.me.team || null
  }

  ui.competitiveMode = state.competitiveMode === 'team' ? 'team' : 'solo'

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

  if (state.phase !== 'playing') {
    ui.menuOpen = false
    ui.mapDetailsOpen = false
    ui.mapPoolOpen = false
    ui.recordsOpen = false
  }
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
    emitAction('sound', { name: 'click' })
  }
}

function onCursorKeydown(event: KeyboardEvent): void {
  if (ui.phase !== 'playing') return
  if (ui.chatOpen) return
  const target = event.target as HTMLElement | null
  if (target?.closest('input, textarea, select, [contenteditable="true"]')) return

  if (event.key === 'F3') {
    event.preventDefault()
    emitAction('cursor:toggle')
    return
  }

  if (event.key === 'F1') {
    event.preventDefault()
    if (ui.helpOpen) {
      ui.helpOpen = false
      emitAction('help:close')
    } else {
      emitAction('help:open')
    }
    return
  }

  if (event.key === 'F2') {
    event.preventDefault()
    emitAction(ui.menuOpen ? 'menu:close' : 'menu:open')
    return
  }

  if (event.key === 'Escape' && !ui.chatOpen) {
    let handled = false
    if (ui.mapDetailsOpen) {
      ui.mapDetailsOpen = false
      handled = true
    }
    if (ui.mapPoolOpen) {
      ui.mapPoolOpen = false
      handled = true
    }
    if (ui.recordsOpen) {
      ui.recordsOpen = false
      handled = true
    }
    if (ui.helpOpen) {
      ui.helpOpen = false
      emitAction('help:close')
      handled = true
    }
    if (ui.menuOpen) {
      emitAction('menu:close')
      handled = true
    }
    if (handled) event.preventDefault()
  }
}

onMounted(() => {
  watch(
    () => ui.mapDetailsOpen,
    (open) => {
      emitAction('mapdetails', { open })
    },
  )

  watch(
    () => ui.mapPoolOpen,
    (open) => {
      emitAction('mappool', { open })
    },
  )

  watch(
    () => ui.recordsOpen,
    (open) => {
      emitAction('recordsmodal', { open })
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
    onBridge('mapsPage', (payload) => {
      if (Number(payload.requestId) !== ui.mapPoolRequestId) return
      ui.mapPool = payload
      ui.mapPoolLoading = false
    }),
    onBridge('recordsPage', (payload) => {
      if (Number(payload.requestId) !== ui.recordsRequestId) return
      ui.records = payload
      ui.recordsLoading = false
    }),
    onBridge('scoreboard', (payload) => {
      if (payload.open !== undefined) ui.scoreboardOpen = payload.open
      if (payload.players) ui.scoreboard = payload
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

  // 界面显示偏好保存在本机 CEF，仅影响当前客户端
  const savedVisibility = window.localStorage.getItem('rst.visibility')
  let visibility = {
    hud: true,
    chat: true,
    radar: true,
    crosshair: true,
    nametags: true,
  }
  if (savedVisibility) {
    try {
      const parsed = JSON.parse(savedVisibility) as Partial<typeof visibility>
      visibility = { ...visibility, ...parsed }
    } catch {
      // 旧值损坏时保持默认
    }
  }
  ui.showHud = visibility.hud !== false
  ui.showChat = visibility.chat !== false
  ui.showRadar = visibility.radar !== false
  ui.showCrosshair = visibility.crosshair !== false
  ui.nametagsVisible = visibility.nametags !== false
  emitAction('visibility:load', visibility)

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
    <StageView v-else-if="ui.phase === 'stage'" />
    <template v-else-if="ui.phase === 'playing'">
      <template v-if="!ui.hudHidden">
        <GameHud v-if="ui.showHud" />
        <MapTimer v-if="ui.showHud && ui.room" />
        <Transition name="speedo">
          <Speedometer v-if="ui.showHud && ui.vehicle" />
        </Transition>
        <SpawnCountdown v-if="ui.countdown.active" />
        <CompetitionPanel v-if="ui.showHud && ui.competition" />
        <RaceResultOverlay v-if="ui.raceResult" />
        <ReadyOverlay v-if="ui.ready.waiting" />
        <RewindOverlay v-if="ui.rewind.active" />
        <ChatPanel v-if="ui.showChat" />
      </template>
      <MenuView v-if="ui.menuOpen" />
      <VoteView v-if="ui.vote?.active" />
      <ModeVoteView v-if="ui.modeVote?.active" />
      <HelpOverlay v-if="ui.helpOpen" />
    </template>
    <AuthView v-else />
    <MapDetailsModal v-if="ui.mapDetailsOpen" />
    <MapPoolModal v-if="ui.mapPoolOpen" />
    <RecordsModal v-if="ui.recordsOpen" />
    <ScoreboardPanel v-if="ui.scoreboardOpen" />
    <BuildTag v-if="!ui.hudHidden && ui.showHud" />
    <ToastMessage :text="toast" />
  </div>
</template>
