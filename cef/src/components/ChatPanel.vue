<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue'

import type { ChatEntry } from '@/mta/protocol'
import { ui } from '@/stores/ui'
import { formatClock } from '@/utils/format'

const CHAT_IDLE_MS = 15_000
// 只展示最新几条：不提供历史滚动，面板高度正好放得下
const CHAT_VISIBLE_LINES = 15

const listRef = ref<HTMLElement | null>(null)
const idle = ref(false)
let idleTimer: number | undefined
let lastMessageId = ui.messages.at(-1)?.id ?? 0

const visibleMessages = computed(() => ui.messages.slice(-CHAT_VISIBLE_LINES))

// 不做历史滚动，但要让最新几条始终留在可视区（内容超出时由这里程序化贴底）
function keepLatestVisible(): void {
  void nextTick(() => {
    const element = listRef.value
    if (element) element.scrollTop = element.scrollHeight
  })
}

function resetIdleTimer(): void {
  idle.value = false
  window.clearTimeout(idleTimer)
  if (ui.chatOpen) return
  idleTimer = window.setTimeout(() => {
    idle.value = true
  }, CHAT_IDLE_MS)
}

function nameColor(message: ChatEntry): string {
  if (message.team === 'red') return 'rgb(255, 110, 110)'
  if (message.team === 'blue') return 'rgb(100, 170, 255)'
  let hash = 0
  for (const char of message.name || '') {
    hash = (hash * 31 + (char.codePointAt(0) ?? 0)) % 360
  }
  return `hsl(${hash} 72% 72%)`
}

function nativeStyle(message: ChatEntry): Record<string, string> | undefined {
  if (!message.color) return undefined
  const { r, g, b } = message.color
  return { color: `rgb(${r}, ${g}, ${b})` }
}

// 新消息只负责续上淡出计时；进场动画交给 TransitionGroup
watch(
  () => ui.messages.at(-1)?.id ?? 0,
  (id) => {
    if (id === lastMessageId) return
    lastMessageId = id
    resetIdleTimer()
    keepLatestVisible()
  },
)

watch(
  () => ui.chatOpen,
  (open) => {
    if (open) {
      idle.value = false
      window.clearTimeout(idleTimer)
    } else {
      resetIdleTimer()
    }
  },
)

onMounted(() => {
  resetIdleTimer()
  keepLatestVisible()
})

onUnmounted(() => {
  window.clearTimeout(idleTimer)
})
</script>

<template>
  <section class="chat" :class="{ 'chat--open': ui.chatOpen, 'chat--idle': idle && !ui.chatOpen }">
    <div ref="listRef" class="chat__list">
      <p v-if="ui.messages.length === 0" class="chat__empty">按 T 发送第一条消息</p>

      <TransitionGroup name="chat-line" tag="div" class="chat__messages">
        <div v-for="message in visibleMessages" :key="message.id" class="chat__line">
          <span class="chat__time">{{ formatClock(message.time) }}</span>

          <template v-if="message.kind === 'player'">
            <span class="chat__name" :style="{ color: nameColor(message) }">
              {{ message.name }}
            </span>
            <span class="chat__text">{{ message.text }}</span>
          </template>

          <template v-else-if="message.kind === 'native'">
            <span class="chat__text chat__text--native" :style="nativeStyle(message)">
              {{ message.text }}
            </span>
          </template>

          <template v-else>
            <span class="chat__text chat__text--system">{{ message.text }}</span>
          </template>
        </div>
      </TransitionGroup>
    </div>
  </section>
</template>

<style scoped>
.chat {
  position: absolute;
  top: 36%;
  left: 24px;
  width: 400px;
  height: 336px;
  display: flex;
  flex-direction: column;
  border: 0;
  border-radius: 14px;
  background: transparent;
  box-shadow: none;
  overflow: hidden;
  pointer-events: none;
  opacity: 1;
  transition: opacity 0.45s ease;
}

.chat--open {
  pointer-events: auto;
}

.chat--idle {
  opacity: 0;
}

.chat__messages {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.chat-line-enter-active {
  transition: opacity 0.18s ease, transform 0.18s ease;
}

.chat-line-enter-from {
  opacity: 0;
  transform: translateY(4px);
}

.chat-line-leave-active {
  display: none;
}

.chat-line-move {
  transition: transform 0.18s ease;
}

.chat__list {
  flex: 1;
  min-height: 0;
  padding: 7px 11px 9px;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  gap: 4px;
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.72);
}

.chat__empty {
  margin: 2px 0;
  font-size: 10px;
  color: var(--rst-muted);
}

.chat__line {
  display: flex;
  align-items: baseline;
  gap: 6px;
  font-size: 12px;
  line-height: 1.45;
  word-break: break-word;
}

.chat__time {
  flex: 0 0 auto;
  padding-top: 1px;
  font-size: 9px;
  font-variant-numeric: tabular-nums;
  color: var(--rst-muted);
}

.chat__name {
  flex: 0 0 auto;
  font-weight: 600;
  white-space: nowrap;
  max-width: 110px;
  overflow: hidden;
  text-overflow: ellipsis;
}

.chat__text {
  color: var(--rst-text);
}

.chat__text--native {
  color: var(--rst-text);
}

.chat__text--system {
  color: var(--rst-gold);
  opacity: 0.9;
}
</style>
