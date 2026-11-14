<script setup lang="ts">
import { computed } from 'vue'

import { emitAction } from '@/mta/bridge'
import { ui } from '@/stores/ui'
import { formatTime } from '@/utils/format'

const options = computed(() => ui.vote?.options ?? [])

const votedName = computed(() => {
  const mine = ui.vote?.mine
  if (!mine) return ''
  return options.value.find((option) => option.id === mine)?.name || ''
})

function vote(mapId: string): void {
  if (ui.vote?.mine) return
  emitAction('vote:cast', { map: mapId })
}
</script>

<template>
  <div class="vote">
    <section class="vote__panel">
      <header class="vote__head">
        <div>
          <p class="vote__eyebrow">MAP VOTE</p>
          <h1 class="vote__title">换图投票</h1>
        </div>
        <span class="vote__timer">{{ formatTime(ui.vote?.timeLeft || 0) }}</span>
      </header>

      <p class="vote__hint">选择下一张地图，时间结束或所有人投完后切换。</p>

      <div class="vote__options">
        <button
          v-for="option in options"
          :key="option.id"
          type="button"
          class="vote__option"
          :class="{ 'vote__option--mine': option.id === ui.vote?.mine }"
          :disabled="!!ui.vote?.mine"
          @click="vote(option.id)"
        >
          <span class="vote__option-name">{{ option.name }}</span>
          <span class="vote__count">{{ option.votes }}</span>
        </button>
      </div>

      <p v-if="votedName" class="vote__mine">已投给：{{ votedName }}</p>
      <p v-else class="vote__mine vote__mine--wait">等待其他玩家投票…</p>
    </section>
  </div>
</template>

<style scoped>
.vote {
  position: absolute;
  inset: 0;
  pointer-events: auto;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(4, 7, 12, 0.55);
}

.vote__panel {
  width: min(480px, calc(100vw - 96px));
  padding: 24px 26px;
  border: 1px solid var(--rst-border);
  border-radius: 16px;
  background: var(--rst-panel);
  box-shadow: 0 24px 64px rgba(0, 0, 0, 0.45);
}

.vote__head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}

.vote__eyebrow {
  margin: 0 0 4px;
  font-size: 10px;
  letter-spacing: 0.2em;
  color: var(--rst-muted);
}

.vote__title {
  margin: 0;
  font-size: 22px;
  font-weight: 600;
}

.vote__timer {
  font-size: 22px;
  font-variant-numeric: tabular-nums;
  color: #ffd479;
}

.vote__hint {
  margin: 14px 0 16px;
  font-size: 12px;
  color: var(--rst-muted);
}

.vote__options {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.vote__option {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 14px;
  padding: 13px 15px;
  border: 1px solid var(--rst-border);
  border-radius: 10px;
  background: rgba(255, 255, 255, 0.04);
  text-align: left;
  transition: background 0.15s ease, border-color 0.15s ease;
}

.vote__option:hover:not(:disabled) {
  background: rgba(76, 194, 255, 0.12);
  border-color: rgba(76, 194, 255, 0.4);
}

.vote__option--mine {
  border-color: rgba(126, 226, 168, 0.45);
  background: rgba(126, 226, 168, 0.1);
}

.vote__option:disabled {
  opacity: 0.75;
}

.vote__count {
  min-width: 28px;
  text-align: right;
  font-variant-numeric: tabular-nums;
  color: var(--rst-accent);
}

.vote__mine {
  margin: 14px 0 0;
  font-size: 12px;
  color: #7ee2a8;
}

.vote__mine--wait {
  color: var(--rst-muted);
}
</style>
