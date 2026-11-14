<script setup lang="ts">
import { computed } from 'vue'

import IconFlag from '~icons/lucide/flag'
import { emitAction } from '@/mta/bridge'
import { ui } from '@/stores/ui'

const percent = computed(() => {
  if (!ui.ready.total) return 0
  return Math.round(((ui.ready.ready || 0) / ui.ready.total) * 100)
})

function ready(): void {
  if (ui.ready.me) return
  emitAction('ready')
}

function spectate(): void {
  emitAction('ob:spectate')
}
</script>

<template>
  <div class="ready">
    <section class="ready__panel">
      <span class="ready__emblem"><IconFlag class="icon icon--lg" /></span>
      <p class="ready__eyebrow">竞技准备</p>
      <h1 class="ready__title">准备发车</h1>
      <p class="ready__hint">竞技模式需要所有玩家准备后，才会开始 5 秒倒计时。</p>

      <div class="ready__count">
        <strong>{{ ui.ready.ready || 0 }}</strong>
        <span>/ {{ ui.ready.total || 0 }} 已准备</span>
      </div>
      <div class="ready__bar">
        <i :style="{ width: `${percent}%` }" />
      </div>

      <button
        type="button"
        class="ready__button"
        :class="{ 'ready__button--done': ui.ready.me }"
        :disabled="ui.ready.me"
        @click="ready"
      >
        {{ ui.ready.me ? '已准备，等待其他玩家' : '准备' }}
      </button>

      <button type="button" class="ready__ob" @click="spectate">
        改为纯观战
      </button>
    </section>
  </div>
</template>

<style scoped>
.ready {
  position: absolute;
  inset: 0;
  pointer-events: auto;
  display: flex;
  align-items: center;
  justify-content: center;
  background: radial-gradient(circle at 50% 40%, rgba(24, 43, 70, 0.35), rgba(3, 6, 11, 0.6));
}

.ready__panel {
  width: min(390px, calc(100vw - 96px));
  padding: 28px 30px 24px;
  border: 1px solid var(--rst-border);
  border-radius: 18px;
  background: linear-gradient(160deg, rgba(19, 31, 48, 0.96), rgba(7, 11, 19, 0.97));
  box-shadow: var(--rst-shadow);
  text-align: center;
}

.ready__emblem {
  display: grid;
  place-items: center;
  width: 48px;
  height: 48px;
  margin: 0 auto 12px;
  border-radius: 14px;
  border: 1px solid rgba(255, 212, 121, 0.3);
  background: rgba(255, 212, 121, 0.1);
  color: var(--rst-gold);
}

.ready__eyebrow {
  margin: 0 0 3px;
  font-size: 9px;
  letter-spacing: 0.2em;
  color: var(--rst-muted);
}

.ready__title {
  margin: 0;
  font-size: 24px;
  font-weight: 600;
}

.ready__hint {
  margin: 10px auto 18px;
  max-width: 290px;
  font-size: 11px;
  line-height: 1.6;
  color: var(--rst-muted);
}

.ready__count {
  display: flex;
  align-items: baseline;
  justify-content: center;
  gap: 5px;
}

.ready__count strong {
  font-size: 34px;
  color: var(--rst-accent);
  font-variant-numeric: tabular-nums;
}

.ready__count span {
  font-size: 11px;
  color: var(--rst-muted);
}

.ready__bar {
  height: 5px;
  margin: 10px 0 18px;
  border-radius: 3px;
  background: rgba(255, 255, 255, 0.09);
  overflow: hidden;
}

.ready__bar i {
  display: block;
  height: 100%;
  border-radius: inherit;
  background: linear-gradient(90deg, #38bdf8, #a78bfa);
  transition: width 0.25s ease;
}

.ready__button {
  width: 100%;
  padding: 11px 16px;
  border: 1px solid rgba(88, 200, 255, 0.45);
  border-radius: 10px;
  background: rgba(88, 200, 255, 0.16);
  color: var(--rst-text);
  font-size: 13px;
  font-weight: 600;
  letter-spacing: 0.04em;
  transition: background 0.15s ease, border-color 0.15s ease;
}

.ready__button:hover:not(:disabled) {
  background: rgba(88, 200, 255, 0.26);
  border-color: rgba(88, 200, 255, 0.7);
}

.ready__button--done {
  border-color: rgba(126, 226, 168, 0.35);
  background: rgba(126, 226, 168, 0.1);
  color: var(--rst-green);
}

.ready__ob {
  margin-top: 10px;
  padding: 6px 10px;
  border: 0;
  background: transparent;
  color: var(--rst-muted);
  font-size: 10px;
  letter-spacing: 0.04em;
}

.ready__ob:hover {
  color: var(--rst-text);
}
</style>
