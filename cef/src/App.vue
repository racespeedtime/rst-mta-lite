<script setup lang="ts">
import { onMounted, onUnmounted, ref } from 'vue'

import GameHud from '@/components/GameHud.vue'
import ChatPanel from '@/components/ChatPanel.vue'
import MapTimer from '@/components/MapTimer.vue'
import Speedometer from '@/components/Speedometer.vue'
import RewindOverlay from '@/components/RewindOverlay.vue'
import ToastMessage from '@/components/ToastMessage.vue'
import AuthView from '@/views/AuthView.vue'
import MenuView from '@/views/MenuView.vue'
import StageSelectView from '@/views/StageSelectView.vue'
import VoteView from '@/views/VoteView.vue'
import { emitToLua, onBridge } from '@/mta/bridge'
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

function applyState(state: StatePayload): void {
  const previousPhase = ui.phase

  ui.phase = state.phase
  if (state.serverName) ui.serverName = state.serverName
  if (state.me) {
    ui.playerName = state.me.name || ui.playerName
    ui.guest = state.me.guest === true
    ui.mode = state.me.mode || 'playing'
  }

  ui.rooms = state.rooms || []
  ui.room = state.room || null
  ui.vote = state.vote || null
  ui.canStartVote = state.canStartVote === true
  ui.mapTime = Math.max(0, Number(state.mapTime) || 0)

  if (previousPhase !== state.phase) {
    ui.busy = false
    if (state.phase !== 'auth') ui.authError = ''
  }

  if (state.phase !== 'playing') ui.menuOpen = false
  if (state.phase !== 'playing' || state.vote?.active) ui.chatOpen = false
}

function onAnyClick(event: MouseEvent): void {
  const target = event.target as HTMLElement | null
  if (target?.closest('button')) {
    emitToLua('sound', { name: 'click' })
  }
}

onMounted(() => {
  offs.push(
    onBridge('state', applyState),
    onBridge('menu', (payload) => {
      ui.menuOpen = payload.open === true
    }),
    onBridge('rewind', (payload) => {
      ui.rewind = payload
    }),
    onBridge('stats', (payload) => {
      ui.health = Math.round(Number(payload.health) || 0)
      ui.armor = Math.round(Number(payload.armor) || 0)
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
      if (ui.messages.length > 100) {
        ui.messages.splice(0, ui.messages.length - 100)
      }
    }),
    onBridge('vehicle', (payload) => {
      ui.vehicle = payload.active ? payload : null
    }),
  )

  document.addEventListener('click', onAnyClick, true)
  emitToLua('ready')
})

onUnmounted(() => {
  offs.forEach((off) => off())
  document.removeEventListener('click', onAnyClick, true)
  window.clearTimeout(toastTimer)
})
</script>

<template>
  <div class="app-root">
    <AuthView v-if="ui.phase === 'auth'" />
    <StageSelectView v-else-if="ui.phase === 'stage'" />
    <template v-else>
      <GameHud />
      <MapTimer v-if="ui.room" />
      <ChatPanel />
      <Transition name="speedo">
        <Speedometer v-if="ui.vehicle" />
      </Transition>
      <MenuView v-if="ui.menuOpen" />
      <VoteView v-if="ui.vote?.active" />
      <RewindOverlay v-if="ui.rewind.active" />
    </template>
    <ToastMessage :text="toast" />
  </div>
</template>
