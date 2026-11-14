<script setup lang="ts">
import { nextTick, onMounted, ref, watch } from 'vue'

import IconMessageSquare from '~icons/lucide/message-square'
import IconSend from '~icons/lucide/send'
import IconX from '~icons/lucide/x'
import { emitAction } from '@/mta/bridge'
import type { ChatEntry } from '@/mta/protocol'
import { ui } from '@/stores/ui'
import { formatClock } from '@/utils/format'

const draft = ref('')
const listRef = ref<HTMLElement | null>(null)
const inputRef = ref<HTMLInputElement | null>(null)

function nameColor(name: string): string {
  let hash = 0
  for (const char of name) {
    hash = (hash * 31 + (char.codePointAt(0) ?? 0)) % 360
  }
  return `hsl(${hash} 72% 72%)`
}

function nativeStyle(message: ChatEntry): Record<string, string> | undefined {
  if (!message.color) return undefined
  const { r, g, b } = message.color
  return { color: `rgb(${r}, ${g}, ${b})` }
}

function scrollToBottom(): void {
  void nextTick(() => {
    const element = listRef.value
    if (element) element.scrollTop = element.scrollHeight
  })
}

function send(): void {
  const text = draft.value.trim()
  if (text) {
    emitAction('chat:send', { text })
    draft.value = ''
  }
  emitAction('chat:close')
}

function close(): void {
  emitAction('chat:close')
}

watch(
  () => ui.chatOpen,
  (open) => {
    if (open) {
      void nextTick(() => {
        inputRef.value?.focus()
        scrollToBottom()
      })
    } else {
      draft.value = ''
    }
  },
)

watch(
  () => ui.messages.length,
  () => scrollToBottom(),
)

onMounted(scrollToBottom)
</script>

<template>
  <section class="chat" :class="{ 'chat--open': ui.chatOpen }">
    <header class="chat__head">
      <span class="chat__title">
        <IconMessageSquare class="icon icon--sm" />
        聊天
      </span>
      <span class="chat__hint">{{ ui.chatOpen ? 'Enter 发送 · Esc 取消' : 'T 输入' }}</span>
    </header>

    <div ref="listRef" class="chat__list">
      <p v-if="ui.messages.length === 0" class="chat__empty">按 T 发送第一条消息</p>

      <div v-for="message in ui.messages" :key="message.id" class="chat__line">
        <span class="chat__time">{{ formatClock(message.time) }}</span>

        <template v-if="message.kind === 'player'">
          <span class="chat__name" :style="{ color: nameColor(message.name || '') }">
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

    <form v-if="ui.chatOpen" class="chat__input" @submit.prevent="send">
      <IconMessageSquare class="icon icon--sm chat__input-icon" />
      <input
        ref="inputRef"
        v-model="draft"
        maxlength="160"
        autocomplete="off"
        placeholder="输入消息…"
        @keydown.enter.prevent="send"
        @keydown.esc.prevent="close"
      />
      <button type="submit" class="chat__button chat__button--send" aria-label="发送">
        <IconSend class="icon icon--sm" />
      </button>
      <button type="button" class="chat__button" aria-label="关闭聊天" @click="close">
        <IconX class="icon icon--sm" />
      </button>
    </form>
  </section>
</template>

<style scoped>
.chat {
  position: absolute;
  top: 126px;
  left: 24px;
  width: 400px;
  max-height: min(38vh, 380px);
  display: flex;
  flex-direction: column;
  border: 1px solid var(--rst-border);
  border-radius: 14px;
  background: linear-gradient(180deg, rgba(8, 14, 23, 0.72), rgba(6, 11, 19, 0.52));
  box-shadow: 0 14px 38px rgba(0, 0, 0, 0.24);
  overflow: hidden;
  pointer-events: none;
  transition: background 0.16s ease, border-color 0.16s ease;
}

.chat--open {
  pointer-events: auto;
  border-color: rgba(88, 200, 255, 0.35);
  background: linear-gradient(180deg, rgba(8, 14, 23, 0.94), rgba(6, 11, 19, 0.9));
  box-shadow: 0 18px 46px rgba(0, 0, 0, 0.4);
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
  color: rgba(147, 164, 189, 0.8);
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
}

.chat__list::-webkit-scrollbar {
  width: 4px;
}

.chat__list::-webkit-scrollbar-thumb {
  border-radius: 2px;
  background: rgba(140, 180, 255, 0.22);
}

.chat__empty {
  margin: 2px 0;
  font-size: 10px;
  color: rgba(147, 164, 189, 0.72);
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
  color: rgba(147, 164, 189, 0.6);
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
  color: #dbe6f5;
}

.chat__text--native {
  color: #dbe6f5;
}

.chat__text--system {
  color: var(--rst-gold);
  opacity: 0.9;
}

.chat__input {
  display: flex;
  align-items: center;
  gap: 7px;
  padding: 7px 9px;
  border-top: 1px solid rgba(255, 255, 255, 0.06);
  background: rgba(0, 0, 0, 0.14);
}

.chat__input-icon {
  color: var(--rst-accent);
}

.chat__input input {
  flex: 1;
  min-width: 0;
  border: 0;
  background: transparent;
  color: var(--rst-text);
  font: inherit;
  font-size: 12px;
  outline: none;
}

.chat__input input::placeholder {
  color: rgba(147, 164, 189, 0.6);
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
