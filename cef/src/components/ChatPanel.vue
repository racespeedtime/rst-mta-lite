<script setup lang="ts">
import { nextTick, onMounted, ref, watch } from 'vue'

import type { ChatEntry } from '@/mta/protocol'
import { ui } from '@/stores/ui'
import { formatClock } from '@/utils/format'

const listRef = ref<HTMLElement | null>(null)
const stickToBottom = ref(true)
const unread = ref(0)
let lastMessageId = ui.messages.at(-1)?.id ?? 0

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

function scrollToBottom(force = false): void {
  if (!force && !stickToBottom.value) return
  void nextTick(() => {
    const element = listRef.value
    if (element) element.scrollTop = element.scrollHeight
    stickToBottom.value = true
    unread.value = 0
  })
}

function isNearBottom(): boolean {
  const element = listRef.value
  if (!element) return true
  return element.scrollHeight - element.scrollTop - element.clientHeight < 28
}

function onScroll(): void {
  stickToBottom.value = isNearBottom()
  if (stickToBottom.value) unread.value = 0
}

watch(
  () => ui.chatOpen,
  (open) => {
    if (open) {
      stickToBottom.value = true
      unread.value = 0
      void nextTick(() => scrollToBottom(true))
    }
  },
)

watch(
  () => ui.messages.at(-1)?.id ?? 0,
  (id) => {
    if (id === lastMessageId) return
    lastMessageId = id
    if (!ui.chatOpen) {
      unread.value = 0
      return
    }
    if (stickToBottom.value) {
      scrollToBottom(true)
    } else {
      unread.value += 1
    }
  },
)

onMounted(() => scrollToBottom(true))
</script>

<template>
  <section class="chat" :class="{ 'chat--open': ui.chatOpen }">
    <div ref="listRef" class="chat__list" @scroll="onScroll">
      <p v-if="ui.messages.length === 0" class="chat__empty">按 T 发送第一条消息</p>

      <div v-for="message in ui.messages" :key="message.id" class="chat__line">
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
    </div>

    <button
      v-if="ui.chatOpen && unread > 0"
      type="button"
      class="chat__new"
      @click="scrollToBottom(true)"
    >
      {{ unread }} 条新消息 ↓
    </button>
  </section>
</template>

<style scoped>
.chat {
  position: absolute;
  top: 36%;
  left: 24px;
  width: 400px;
  height: min(48vh, 380px);
  display: flex;
  flex-direction: column;
  border: 0;
  border-radius: 14px;
  background: transparent;
  box-shadow: none;
  overflow: hidden;
  pointer-events: none;
}

.chat--open {
  pointer-events: auto;
}

.chat__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  padding: 8px 12px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.05);
}

.chat__title {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.14em;
  color: var(--rst-muted);
}

.chat__hint {
  font-size: 9px;
  letter-spacing: 0.05em;
  color: var(--rst-muted);
}

.chat--open .chat__hint {
  color: var(--rst-accent);
}

.chat__list {
  flex: 1;
  min-height: 34px;
  padding: 7px 11px 9px;
  overflow-y: auto;
  overflow-x: hidden;
  display: flex;
  flex-direction: column;
  gap: 4px;
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.72);
}

.chat__list::-webkit-scrollbar {
  width: 4px;
}

.chat__list::-webkit-scrollbar-thumb {
  border-radius: 2px;
  background: rgba(140, 180, 255, 0.22);
}

.chat__new {
  margin: 0 10px 7px;
  padding: 5px 9px;
  border: 1px solid rgba(var(--rst-accent-rgb), 0.28);
  border-radius: 7px;
  background: rgba(var(--rst-accent-rgb), 0.12);
  color: var(--rst-accent);
  font-size: 10px;
  text-align: center;
}

.chat__new:hover {
  background: rgba(var(--rst-accent-rgb), 0.2);
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

.chat__native-hint {
  padding: 7px 12px;
  border-top: 1px solid rgba(255, 255, 255, 0.06);
  background: rgba(0, 0, 0, 0.14);
  color: var(--rst-muted);
  font-size: 10px;
  letter-spacing: 0.04em;
}

.chat__button {
  display: grid;
  place-items: center;
  width: 26px;
  height: 26px;
  border-radius: 7px;
  color: var(--rst-muted);
  transition: color 0.15s ease, background 0.15s ease;
}

.chat__button:hover {
  color: var(--rst-text);
  background: rgba(255, 255, 255, 0.08);
}

.chat__button--send {
  color: var(--rst-accent);
}
</style>
