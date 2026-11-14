<script setup lang="ts">
import { computed } from 'vue'

import IconCar from '~icons/lucide/car'
import IconCheck from '~icons/lucide/check'
import IconClock from '~icons/lucide/clock'
import IconTrophy from '~icons/lucide/trophy'
import IconUsers from '~icons/lucide/users'
import IconVote from '~icons/lucide/vote'
import { emitAction } from '@/mta/bridge'
import type { ModeVoteId } from '@/mta/protocol'
import { useTicker } from '@/composables/useTicker'
import { ui } from '@/stores/ui'
import { formatMs } from '@/utils/format'

const vote = computed(() => ui.modeVote)
const now = useTicker()
const remainingMs = computed(() => {
  const base = vote.value?.timeLeftMs ?? (vote.value?.timeLeft ?? 0) * 1000
  const elapsed = ui.stateAt ? Math.max(0, now.value - ui.stateAt) : 0
  return Math.max(0, base - elapsed)
})
const totalVotes = computed(() =>
  (vote.value?.options ?? []).reduce((sum, option) => sum + option.votes, 0),
)

const currentLabel = computed(() => {
  if (vote.value?.currentMode === 'team') return '团队竞技'
  return vote.value?.currentMode === 'competitive' ? '个人竞技' : '训练模式'
})

const votedName = computed(() => {
  const mine = vote.value?.mine
  if (!mine) return ''
  return vote.value?.options.find((option) => option.id === mine)?.name || ''
})

function percent(votes: number): number {
  if (!totalVotes.value) return 0
  return Math.round((votes / totalVotes.value) * 100)
}

function cast(mode: ModeVoteId): void {
  if (vote.value?.mine) return
  emitAction('modevote:cast', { mode })
}
</script>

<template>
  <div v-if="vote" class="mode-vote">
    <section class="mode-vote__panel">
      <header class="mode-vote__head">
        <div class="mode-vote__title-row">
          <span class="mode-vote__emblem"><IconVote class="icon icon--lg" /></span>
          <div>
            <p class="mode-vote__eyebrow">MODE VOTE</p>
            <h1 class="mode-vote__title">模式投票</h1>
          </div>
        </div>
        <span class="mode-vote__timer">
          <IconClock class="icon icon--sm" />
          {{ formatMs(remainingMs) }}
        </span>
      </header>

      <p class="mode-vote__hint">
        地图不变，只切换比赛模式；平票或无人投票时保持当前模式。
      </p>

      <div class="mode-vote__current">
        当前：<strong>{{ currentLabel }}</strong>
      </div>

      <div class="mode-vote__options">
        <button
          v-for="option in vote.options"
          :key="option.id"
          type="button"
          class="mode-option"
          :class="{ 'mode-option--mine': option.id === vote.mine }"
          :disabled="!!vote.mine"
          @click="cast(option.id)"
        >
          <span class="mode-option__fill" :style="{ width: `${percent(option.votes)}%` }" />
          <span class="mode-option__icon">
            <IconTrophy v-if="option.id === 'competitive'" class="icon" />
            <IconUsers v-else-if="option.id === 'team'" class="icon" />
            <IconCar v-else class="icon" />
          </span>
          <span class="mode-option__main">
            <strong>{{ option.name }}</strong>
            <small>{{ option.description }}</small>
          </span>
          <span class="mode-option__right">
            <strong>{{ option.votes }}</strong>
            <IconCheck v-if="option.id === vote.mine" class="icon mode-option__check" />
          </span>
        </button>
      </div>

      <p v-if="vote.mine" class="mode-vote__foot">
        已投给：{{ votedName }}
      </p>
      <p v-else class="mode-vote__foot mode-vote__foot--wait">等待其他玩家投票…</p>
    </section>
  </div>
</template>

<style scoped>
.mode-vote {
  position: absolute;
  inset: 0;
  pointer-events: auto;
  display: flex;
  align-items: center;
  justify-content: center;
  background: radial-gradient(circle at 50% 35%, rgba(26, 46, 74, 0.4), rgba(3, 6, 11, 0.7));
}

.mode-vote__panel {
  width: min(480px, calc(100vw - 96px));
  padding: 24px 26px 20px;
  border: 1px solid var(--rst-border);
  border-radius: 18px;
  background: linear-gradient(160deg, rgba(19, 31, 48, 0.95), rgba(7, 11, 19, 0.96));
  box-shadow: var(--rst-shadow);
}

.mode-vote__head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}

.mode-vote__title-row {
  display: flex;
  align-items: center;
  gap: 12px;
}

.mode-vote__emblem {
  display: grid;
  place-items: center;
  width: 40px;
  height: 40px;
  border-radius: 12px;
  border: 1px solid rgba(255, 212, 121, 0.28);
  background: rgba(255, 212, 121, 0.1);
  color: var(--rst-gold);
}

.mode-vote__eyebrow {
  margin: 0 0 2px;
  font-size: 9px;
  letter-spacing: 0.2em;
  color: var(--rst-muted);
}

.mode-vote__title {
  margin: 0;
  font-size: 21px;
  font-weight: 600;
}

.mode-vote__timer {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 5px 9px;
  border: 1px solid rgba(255, 212, 121, 0.28);
  border-radius: 8px;
  font-size: 15px;
  font-variant-numeric: tabular-nums;
  color: var(--rst-gold);
}

.mode-vote__hint {
  margin: 14px 0 10px;
  font-size: 11px;
  color: var(--rst-muted);
}

.mode-vote__current {
  margin-bottom: 10px;
  font-size: 10px;
  color: var(--rst-muted);
}

.mode-vote__current strong {
  color: var(--rst-text);
}

.mode-vote__options {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.mode-option {
  position: relative;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 14px;
  border: 1px solid var(--rst-border);
  border-radius: 12px;
  background: rgba(255, 255, 255, 0.035);
  text-align: left;
  overflow: hidden;
  transition: border-color 0.15s ease, background 0.15s ease;
}

.mode-option:hover:not(:disabled) {
  border-color: rgba(88, 200, 255, 0.4);
  background: rgba(88, 200, 255, 0.07);
}

.mode-option--mine {
  border-color: rgba(126, 226, 168, 0.45);
  background: rgba(126, 226, 168, 0.07);
}

.mode-option:disabled {
  opacity: 0.85;
}

.mode-option__fill {
  position: absolute;
  inset: 0 auto 0 0;
  background: linear-gradient(90deg, rgba(88, 200, 255, 0.16), rgba(88, 200, 255, 0.02));
  transition: width 0.3s ease;
}

.mode-option__icon {
  position: relative;
  z-index: 1;
  display: grid;
  place-items: center;
  width: 34px;
  height: 34px;
  border-radius: 10px;
  color: var(--rst-accent);
  background: rgba(88, 200, 255, 0.1);
}

.mode-option__main {
  position: relative;
  z-index: 1;
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 3px;
}

.mode-option__main strong {
  font-size: 14px;
}

.mode-option__main small {
  font-size: 10px;
  color: var(--rst-muted);
}

.mode-option__right {
  position: relative;
  z-index: 1;
  display: flex;
  align-items: center;
  gap: 6px;
}

.mode-option__right strong {
  min-width: 20px;
  text-align: right;
  color: var(--rst-accent);
  font-size: 15px;
  font-variant-numeric: tabular-nums;
}

.mode-option__check {
  color: var(--rst-green);
}

.mode-vote__foot {
  margin: 14px 0 0;
  font-size: 11px;
  color: var(--rst-green);
}

.mode-vote__foot--wait {
  color: var(--rst-muted);
}
</style>
