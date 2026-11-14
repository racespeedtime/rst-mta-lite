<script setup lang="ts">
import { onMounted, onUnmounted, ref } from 'vue'
import { useRouter } from 'vue-router'

import { emitToLua, onBridge } from '@/mta/bridge'
import { session } from '@/stores/session'

const router = useRouter()
const toast = ref('')

let offToast: (() => void) | undefined
let toastTimer: number | undefined

function close(): void {
  emitToLua('menu:close')
  void router.push('/')
}

function testLua(): void {
  emitToLua('test')
}

function openDevTools(): void {
  emitToLua('devtools')
}

function onKeydown(event: KeyboardEvent): void {
  if (event.key === 'Escape') close()
}

onMounted(() => {
  window.addEventListener('keydown', onKeydown)
  offToast = onBridge('toast', (payload) => {
    toast.value = payload.text || ''
    window.clearTimeout(toastTimer)
    toastTimer = window.setTimeout(() => {
      toast.value = ''
    }, 3000)
  })
})

onUnmounted(() => {
  window.removeEventListener('keydown', onKeydown)
  offToast?.()
  window.clearTimeout(toastTimer)
})
</script>

<template>
  <div class="menu-backdrop">
    <section class="menu-panel">
      <header class="menu-panel__head">
        <div>
          <p class="menu-panel__eyebrow">RST MTA LITE</p>
          <h1 class="menu-panel__title">主菜单</h1>
        </div>
        <button class="menu-close" type="button" aria-label="关闭菜单" @click="close">×</button>
      </header>

      <dl class="menu-meta">
        <div>
          <dt>玩家</dt>
          <dd>{{ session.playerName }}</dd>
        </div>
        <div>
          <dt>服务器</dt>
          <dd>{{ session.serverName }}</dd>
        </div>
        <div>
          <dt>在线</dt>
          <dd>{{ session.online }}</dd>
        </div>
      </dl>

      <div class="menu-actions">
        <button type="button" class="menu-action" @click="testLua">
          <span>测试 Lua 回调</span>
          <small>JS → Lua → JS</small>
        </button>
        <button type="button" class="menu-action" @click="openDevTools">
          <span>打开 DevTools</span>
          <small>CEF 调试</small>
        </button>
        <button type="button" class="menu-action menu-action--ghost" @click="close">
          <span>关闭菜单</span>
          <small>Esc</small>
        </button>
      </div>

      <transition name="fade">
        <p v-if="toast" class="menu-toast">{{ toast }}</p>
      </transition>
    </section>
  </div>
</template>

<style scoped>
.menu-backdrop {
  position: absolute;
  inset: 0;
  pointer-events: auto;
  display: flex;
  align-items: center;
  justify-content: center;
  background: radial-gradient(circle at 50% 30%, rgba(20, 40, 70, 0.55), rgba(4, 7, 12, 0.78));
  animation: menu-fade 0.16s ease-out;
}

.menu-panel {
  width: min(560px, calc(100vw - 96px));
  padding: 26px 28px;
  border: 1px solid var(--rst-border);
  border-radius: 16px;
  background: var(--rst-panel);
  box-shadow: 0 24px 64px rgba(0, 0, 0, 0.45);
  display: flex;
  flex-direction: column;
  gap: 20px;
}

.menu-panel__head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}

.menu-panel__eyebrow {
  margin: 0 0 4px;
  font-size: 10px;
  letter-spacing: 0.2em;
  color: var(--rst-muted);
}

.menu-panel__title {
  margin: 0;
  font-size: 22px;
  font-weight: 600;
  letter-spacing: 0.02em;
}

.menu-close {
  width: 32px;
  height: 32px;
  border: 1px solid var(--rst-border);
  border-radius: 8px;
  color: var(--rst-muted);
  font-size: 18px;
  line-height: 1;
  transition: background 0.15s ease, color 0.15s ease;
}

.menu-close:hover {
  color: var(--rst-text);
  background: rgba(255, 255, 255, 0.06);
}

.menu-meta {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 10px;
  margin: 0;
}

.menu-meta div {
  padding: 10px 12px;
  border-radius: 10px;
  background: rgba(255, 255, 255, 0.04);
}

.menu-meta dt {
  font-size: 10px;
  letter-spacing: 0.08em;
  color: var(--rst-muted);
}

.menu-meta dd {
  margin: 4px 0 0;
  font-size: 13px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.menu-actions {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.menu-action {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 14px;
  border: 1px solid var(--rst-border);
  border-radius: 10px;
  background: rgba(255, 255, 255, 0.04);
  text-align: left;
  transition: background 0.15s ease, border-color 0.15s ease;
}

.menu-action:hover {
  background: rgba(76, 194, 255, 0.12);
  border-color: rgba(76, 194, 255, 0.4);
}

.menu-action small {
  color: var(--rst-muted);
  font-size: 11px;
}

.menu-action--ghost {
  color: var(--rst-muted);
}

.menu-toast {
  margin: 0;
  padding: 10px 12px;
  border-radius: 8px;
  background: rgba(76, 194, 255, 0.12);
  color: var(--rst-accent);
  font-size: 12px;
}

.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.2s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}

@keyframes menu-fade {
  from {
    opacity: 0;
  }
  to {
    opacity: 1;
  }
}
</style>
