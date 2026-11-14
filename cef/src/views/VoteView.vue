<script setup lang="ts">
import { computed } from 'vue'

import IconCheck from '~icons/lucide/check'
import IconClock from '~icons/lucide/clock'
import IconPenLine from '~icons/lucide/pen-line'
import IconVote from '~icons/lucide/vote'
import { emitAction } from '@/mta/bridge'
import { ui } from '@/stores/ui'
import { formatTime } from '@/utils/format'

const options = computed(() => ui.vote?.options ?? [])
const totalVotes = computed(() => options.value.reduce((sum, option) => sum + option.votes, 0))

const votedName = computed(() => {
  const mine = ui.vote?.mine
  if (!mine) return ''
  return options.value.find((option) => option.id === mine)?.name || ''
})

function percent(votes: number): number {
  if (!totalVotes.value) return 0
  return Math.round((votes / totalVotes.value) * 100)
}

function vote(mapId: string): void {
  if (ui.vote?.mine) return
  emitAction('vote:cast', { map: mapId })
}
</script>

<template>
  <div class="vote">
    <section class="vote__panel">
      <header class="vote__head">
        <div class="vote__title-row">
          <span class="vote__emblem"><IconVote class="icon icon--lg" /></span>
          <div>
            <p class="vote__eyebrow">MAP VOTE</p>
            <h1 class="vote__title">换图投票</h1>
          </div>
        </div>
        <span class="vote__timer">
          <IconClock class="icon icon--sm" />
          {{ formatTime(ui.vote?.timeLeft || 0) }}
        </span>
      </header>

      <p class="vote__hint">选择下一张赛道，时间结束或所有人投完后切换。</p>

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
          <span class="vote__fill" :style="{ width: `${percent(option.votes)}%` }" />
          <span class="vote__option-main">
            <span class="vote__option-name">{{ option.name }}</span>
            <span class="vote__option-author">
              <IconPenLine class="icon icon--sm" />
              作者 · {{ option.author }}
            </span>
          </span>
          <span class="vote__option-right">
            <strong>{{ option.votes }}</strong>
            <IconCheck v-if="option.id === ui.vote?.mine" class="icon vote__check" />
          </span>
        </button>
      </div>

      <p v-if="votedName" class="vote__mine">
        <IconCheck class="icon icon--sm" />
        已投给：{{ votedName }}
      </p>
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
  background: radial-gradient(circle at 50% 35%, rgba(26, 46, 74, 0.4), rgba(3, 6, 11, 0.7));
}

.vote__panel {
  width: min(500px, calc(100vw - 96px));
  padding: 24px 26px 20px;
  border: 1px solid var(--rst-border);
  border-radius: 18px;
  background: linear-gradient(160deg, rgba(19, 31, 48, 0.95), rgba(7, 11, 19, 0.96));
  box-shadow: var(--rst-shadow);
}

.vote__head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}

.vote__title-row {
  display: flex;
  align-items: center;
  gap: 12px;
}

.vote__emblem {
  display: grid;
  place-items: center;
  width: 40px;
  height: 40px;
  border-radius: 12px;
  border: 1px solid rgba(255, 212, 121, 0.28);
  background: rgba(255, 212, 121, 0.1);
  color: var(--rst-gold);
}

.vote__eyebrow {
  margin: 0 0 2px;
  font-size: 9px;
  letter-spacing: 0.2em;
  color: var(--rst-muted);
}

.vote__title {
  margin: 0;
  font-size: 21px;
  font-weight: 600;
}

.vote__timer {
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

.vote__hint {
  margin: 14px 0 14px;
  font-size: 11px;
  color: var(--rst-muted);
}

.vote__options {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.vote__option {
  position: relative;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 14px;
  border: 1px solid var(--rst-border);
  border-radius: 11px;
  background: rgba(255, 255, 255, 0.035);
  text-align: left;
  overflow: hidden;
  transition: border-color 0.15s ease, background 0.15s ease;
}

.vote__option:hover:not(:disabled) {
  border-color: rgba(88, 200, 255, 0.4);
  background: rgba(88, 200, 255, 0.07);
}

.vote__option--mine {
  border-color: rgba(126, 226, 168, 0.45);
  background: rgba(126, 226, 168, 0.07);
}

.vote__option:disabled {
  opacity: 0.85;
}

.vote__fill {
  position: absolute;
  inset: 0 auto 0 0;
  width: 0;
  background: linear-gradient(90deg, rgba(88, 200, 255, 0.16), rgba(88, 200, 255, 0.02));
  transition: width 0.3s ease;
}

.vote__option--mine .vote__fill {
  background: linear-gradient(90deg, rgba(126, 226, 168, 0.2), rgba(126, 226, 168, 0.03));
}

.vote__option-main {
  position: relative;
  z-index: 1;
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 3px;
}

.vote__option-name {
  font-size: 13px;
}

.vote__option-author {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 10px;
  color: var(--rst-muted);
}

.vote__option-right {
  position: relative;
  z-index: 1;
  display: flex;
  align-items: center;
  gap: 6px;
}

.vote__option-right strong {
  min-width: 22px;
  text-align: right;
  font-size: 15px;
  font-variant-numeric: tabular-nums;
  color: var(--rst-accent);
}

.vote__check {
  color: var(--rst-green);
}

.vote__mine {
  display: flex;
  align-items: center;
  gap: 5px;
  margin: 14px 0 0;
  font-size: 11px;
  color: var(--rst-green);
}

.vote__mine--wait {
  color: var(--rst-muted);
}
</style>
