<script setup lang="ts">
import { emitAction } from '@/mta/bridge'
import { ui } from '@/stores/ui'
import { formatTime } from '@/utils/format'

function close(): void {
  emitAction('menu:close')
}

function startVote(): void {
  if (!ui.canStartVote) return
  emitAction('vote:start')
  emitAction('menu:close')
}

function devtools(): void {
  emitAction('devtools')
}

function leaveStage(): void {
  emitAction('stage:leave')
  emitAction('menu:close')
}
</script>

<template>
  <div class="menu-backdrop">
    <section class="menu-panel">
      <header class="menu-panel__head">
        <div>
          <p class="menu-panel__eyebrow">RST MTA LITE</p>
          <h1 class="menu-panel__title">菜单</h1>
        </div>
        <button class="menu-close" type="button" aria-label="关闭菜单" @click="close">×</button>
      </header>

      <dl class="menu-meta">
        <div>
          <dt>玩家</dt>
          <dd>{{ ui.playerName }}</dd>
        </div>
        <div>
          <dt>舞台</dt>
          <dd>{{ ui.room?.name || '-' }}</dd>
        </div>
        <div>
          <dt>地图</dt>
          <dd>{{ ui.room?.mapName || '-' }}</dd>
        </div>
      </dl>

      <div v-if="ui.room" class="menu-round">
        <span>本图剩余 <strong>{{ formatTime(ui.room.timeLeft) }}</strong></span>
        <span>{{ ui.room.players }} 玩家 / {{ ui.room.spectators }} 观战</span>
      </div>

      <div class="menu-actions">
        <button
          type="button"
          class="menu-action"
          :disabled="!ui.canStartVote"
          @click="startVote"
        >
          <span>发起换图投票</span>
          <small>{{ ui.canStartVote ? '30 秒后结算' : '当前不可发起' }}</small>
        </button>
        <button type="button" class="menu-action" @click="devtools">
          <span>打开 DevTools</span>
          <small>CEF 调试</small>
        </button>
        <button type="button" class="menu-action menu-action--ghost" @click="leaveStage">
          <span>离开舞台</span>
          <small>回到舞台选择</small>
        </button>
        <button type="button" class="menu-action menu-action--ghost" @click="close">
          <span>关闭菜单</span>
          <small>Esc</small>
        </button>
      </div>
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
  background: radial-gradient(circle at 50% 30%, rgba(20, 40, 70, 0.45), rgba(4, 7, 12, 0.72));
  animation: menu-fade 0.16s ease-out;
}

.menu-panel {
  width: min(520px, calc(100vw - 96px));
  padding: 26px 28px;
  border: 1px solid var(--rst-border);
  border-radius: 16px;
  background: var(--rst-panel);
  box-shadow: 0 24px 64px rgba(0, 0, 0, 0.45);
  display: flex;
  flex-direction: column;
  gap: 18px;
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
}

.menu-close {
  width: 32px;
  height: 32px;
  border: 1px solid var(--rst-border);
  border-radius: 8px;
  color: var(--rst-muted);
  font-size: 18px;
  line-height: 1;
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

.menu-round {
  display: flex;
  flex-wrap: wrap;
  gap: 8px 16px;
  font-size: 11px;
  color: var(--rst-muted);
}

.menu-round strong {
  color: var(--rst-text);
  font-variant-numeric: tabular-nums;
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

.menu-action:hover:not(:disabled) {
  background: rgba(76, 194, 255, 0.12);
  border-color: rgba(76, 194, 255, 0.4);
}

.menu-action:disabled {
  opacity: 0.45;
}

.menu-action small {
  color: var(--rst-muted);
  font-size: 11px;
}

.menu-action--ghost {
  color: var(--rst-muted);
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
