<script setup lang="ts">
import { onMounted, onUnmounted, ref, watch } from 'vue'

import { ElConfigProvider } from 'element-plus'
import zhCn from 'element-plus/es/locale/lang/zh-cn'

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
import { applyTheme, loadThemeSettings, saveThemeSettings } from '@/theme'

interface ToastItem {
  id: number
  text: string
}

const toasts = ref<ToastItem[]>([])
const toastTimers = new Map<number, number>()
let nextMessageId = 1
let nextToastId = 1
const offs: Array<() => void> = []

function removeToast(id: number): void {
  const timer = toastTimers.get(id)
  if (timer !== undefined) {
    window.clearTimeout(timer)
    toastTimers.delete(id)
  }
  const index = toasts.value.findIndex((item) => item.id === id)
  if (index >= 0) toasts.value.splice(index, 1)
}

function showToast(text: string): void {
  const id = nextToastId++
  toasts.value.push({ id, text })
  const timer = window.setTimeout(() => {
    removeToast(id)
  }, 3200)
  toastTimers.set(id, timer)
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
  const previousVote = ui.vote
  const previousModeVote = ui.modeVote

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
  ui.spectate = state.spectate || null
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
  if (!ui.modeVote?.active) ui.modeVoteOverlayOpen = false
  ui.canStartVote = state.canStartVote === true
  ui.canStartRestartVote = state.canStartRestartVote === true
  ui.voteCooldown = Math.max(0, Number(state.voteCooldown) || 0)
  ui.canStartModeVote = state.canStartModeVote === true
  ui.modeVoteCooldown = Math.max(0, Number(state.modeVoteCooldown) || 0)
  ui.mapTime = Math.max(0, Number(state.mapTime) || 0)
  ui.mapTimeMs =
    typeof state.mapTimeMs === 'number'
      ? Math.max(0, state.mapTimeMs)
      : Math.max(0, (Number(state.mapTime) || 0) * 1000)

  ui.stateAt = performance.now()

  // 刚开始投票时收起地图池/详情，直接让玩家看到投票界面（投票进行中仍可手动再打开）
  const voteJustStarted =
    (!previousVote?.active && ui.vote?.active) || (!previousModeVote?.active && ui.modeVote?.active)
  if (voteJustStarted) {
    ui.mapPoolOpen = false
    ui.mapDetailsOpen = false
    ui.recordsOpen = false
  }

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

function openVotePanel(): void {
  emitAction('voteui', { open: true })
}

function openModeVotePanel(): void {
  emitAction('modevoteui', { open: true })
}

function onAnyClick(event: MouseEvent): void {
  const target = event.target as HTMLElement | null
  if (target?.closest('button')) {
    emitAction('sound', { name: 'click' })
  }
}


onMounted(() => {
  // 纯浏览器调试：?pool 自动打开地图池，?vote 直接进入投票面板（只在 dev 生效）
  if (import.meta.env.DEV) {
    let devOpened = false
    watch(
      () => ui.phase,
      (phase) => {
        if (phase !== 'playing' || devOpened) return
        devOpened = true
        if (window.location.search.includes('pool')) ui.mapPoolOpen = true
        if (window.location.search.includes('vote')) ui.voteOverlayOpen = true
      },
      { immediate: true },
    )
  }

  const theme = loadThemeSettings()
  ui.themeMode = theme.mode
  ui.accentColor = theme.accent
  applyTheme(theme)
  // 旧版本可能存了 "跟随系统"，loadThemeSettings 会归一成深色，这里顺手写回
  saveThemeSettings(theme)

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
    onBridge('voteui', (payload) => {
      ui.voteOverlayOpen = payload.open === true
    }),
    onBridge('modevoteui', (payload) => {
      ui.modeVoteOverlayOpen = payload.open === true
    }),
    // Lua 侧按 Esc 关闭弹窗时，把 CEF 里的开关同步关掉（否则只能靠按钮关闭）
    onBridge('mappool', (payload) => {
      ui.mapPoolOpen = payload.open === true
    }),
    onBridge('mapdetails', (payload) => {
      ui.mapDetailsOpen = payload.open === true
    }),
    onBridge('recordsmodal', (payload) => {
      ui.recordsOpen = payload.open === true
    }),
    onBridge('mapDetail', (payload) => {
      if (Number(payload.requestId) !== ui.mapPoolDetailRequestId) return
      if (!payload.detail) {
        showToast('地图详情加载失败')
        return
      }
      ui.mapDetails = payload.detail
      ui.mapDetailsOpen = true
    }),
    onBridge('mapDetailCover', (payload) => {
      const requestId = Number(payload.requestId)
      if (requestId && requestId !== ui.mapPoolDetailRequestId) return
      if (!ui.mapDetails) return
      if (payload.mapId && ui.mapDetails.id !== payload.mapId) return
      ui.mapDetails.cover = payload.cover || null
      ui.mapDetails.coverPending = payload.pending === true
      ui.mapDetails.coverError = payload.error === true
      ui.mapDetails.coverProgress = typeof payload.progress === 'number' ? payload.progress : -1
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
    onBridge('warps', (payload) => {
      ui.warps = payload.items || []
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
  for (const timer of toastTimers.values()) {
    window.clearTimeout(timer)
  }
  toastTimers.clear()
})
</script>

<template>
  <ElConfigProvider :locale="zhCn">
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
          <Transition name="countdown-fade">
            <SpawnCountdown v-if="ui.countdown.active" />
          </Transition>
          <CompetitionPanel v-if="ui.showHud && ui.competition" />
          <RaceResultOverlay v-if="ui.raceResult" />
          <ReadyOverlay v-if="ui.ready.waiting" />
          <RewindOverlay v-if="ui.rewind.active" />

          <ChatPanel v-if="ui.showChat" />
        </template>
        <Transition name="menu">
          <MenuView v-if="ui.menuOpen" />
        </Transition>
        <VoteView v-if="ui.vote?.active && (ui.vote.forced !== false || ui.voteOverlayOpen)" />
        <button
          v-if="ui.vote?.active && ui.vote.forced === false && !ui.voteOverlayOpen"
          type="button"
          class="vote-hint"
          @click="openVotePanel"
        >
          换图投票中 · 按 F4 参与
        </button>
        <ModeVoteView
          v-if="ui.modeVote?.active && (ui.modeVote.forced !== false || ui.modeVoteOverlayOpen)"
        />
        <button
          v-if="ui.modeVote?.active && ui.modeVote.forced === false && !ui.modeVoteOverlayOpen"
          type="button"
          class="vote-hint"
          @click="openModeVotePanel"
        >
          模式投票中 · 按 F4 参与
        </button>
        <HelpOverlay v-if="ui.helpOpen" />
      </template>
      <AuthView v-else />
      <Transition name="modal">
        <MapDetailsModal v-if="ui.mapDetailsOpen" />
      </Transition>
      <Transition name="modal">
        <MapPoolModal v-if="ui.mapPoolOpen" />
      </Transition>
      <Transition name="modal">
        <RecordsModal v-if="ui.recordsOpen" />
      </Transition>
      <ScoreboardPanel v-if="ui.scoreboardOpen" />
      <BuildTag v-if="!ui.hudHidden && ui.showHud" />
      <ToastMessage :items="toasts" />
    </div>
  </ElConfigProvider>
</template>
