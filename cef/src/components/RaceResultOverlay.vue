<script setup lang="ts">
import { computed } from 'vue'

import IconFlag from '~icons/lucide/flag'
import IconTimer from '~icons/lucide/timer'
import IconTrophy from '~icons/lucide/trophy'
import { useTicker } from '@/composables/useTicker'
import { ui } from '@/stores/ui'
import { formatMs } from '@/utils/format'

const result = computed(() => ui.raceResult)
const now = useTicker()

const isTraining = computed(() => result.value?.mode === 'training')
const isFinal = computed(() => result.value?.final === true)

const title = computed(() => {
  if (isTraining.value) return '完成赛道'
  return isFinal.value ? '比赛结束' : '第一名已完赛'
})

const subtitle = computed(() => {
  if (isTraining.value) return '个人训练结算'
  return isFinal.value ? '最终排行' : '其他玩家还可以继续冲线'
})

const elapsedMs = computed(() => (ui.stateAt ? Math.max(0, now.value - ui.stateAt) : 0))

const remainingMs = computed(() => {
  const value = result.value
  if (!value) return 0

  if (isTraining.value) {
    return Math.max(0, (value.returnInMs ?? (value.returnIn || 0) * 1000) - elapsedMs.value)
  }
  if (!isFinal.value) {
    return Math.max(0, (value.countdownMs ?? (value.countdown || 0) * 1000) - elapsedMs.value)
  }
  return Math.max(0, (value.resultsInMs ?? (value.resultsIn || 0) * 1000) - elapsedMs.value)
})
</script>

<template>
  <div
    v-if="result"
    class="race-result"
    :class="{ 'race-result--banner': !isTraining && !isFinal }"
  >
    <div v-if="!isTraining && !isFinal" class="race-result__banner">
      <span class="race-result__banner-title"><IconFlag class="icon icon--sm" />{{ title }}</span>
      <span class="race-result__banner-sub">{{ subtitle }}</span>
      <strong class="race-result__banner-time">{{ formatMs(remainingMs) }} 后结算</strong>
      <div class="race-result__mini">
        <span v-for="entry in result.top" :key="entry.rank">
          #{{ entry.rank }} {{ entry.name }}
        </span>
      </div>
    </div>

    <section v-else class="race-result__panel">
      <header class="race-result__head">
        <span class="race-result__icon"><IconTrophy class="icon" /></span>
        <div>
          <p class="race-result__eyebrow">
            {{ isTraining ? '训练结算' : '竞速结算' }}
          </p>
          <h2>{{ title }}</h2>
          <p>{{ subtitle }}</p>
        </div>
      </header>

      <div class="race-result__timer">
        <IconTimer class="icon icon--sm" />
        <span v-if="isTraining">
          {{ formatMs(remainingMs) }} 后回到出生点
        </span>
        <span v-else>
          {{ formatMs(remainingMs) }} 后进入换图投票
        </span>
      </div>

      <div v-if="result.format === 'team' && result.teams" class="race-result__teams">
        <div
          v-for="team in result.teams"
          :key="team.id"
          class="race-result__team-score"
          :class="`race-result__team-score--${team.id}`"
        >
          <span>{{ team.name }}</span>
          <strong>{{ team.score }} 分</strong>
          <small>{{ team.finished }} 人完赛</small>
        </div>
      </div>

      <div class="race-result__podium">
        <div
          v-for="entry in result.top"
          :key="entry.rank"
          class="race-result__row"
          :class="{
            'is-me': entry.me,
            'is-red': entry.team === 'red',
            'is-blue': entry.team === 'blue',
          }"
        >
          <span class="race-result__rank">#{{ entry.rank }}</span>
          <span class="race-result__name">
            {{ entry.name }}
            <small v-if="entry.team">{{ entry.team === 'red' ? '红队' : '蓝队' }}</small>
          </span>
          <span class="race-result__time">{{ formatMs(entry.elapsedMs ?? entry.elapsed * 1000) }}</span>
        </div>
        <p v-if="result.top.length === 0" class="race-result__empty">还没有人冲线</p>
      </div>

      <p v-if="result.me" class="race-result__mine">
        你的成绩：第 {{ result.me.rank }} 名 ·
        {{ formatMs(result.me.elapsedMs ?? result.me.elapsed * 1000) }}
      </p>
      <p v-else-if="!isTraining" class="race-result__mine">你还没有完成比赛</p>
      <p v-if="ui.personalBestMs !== null" class="race-result__best">
        当前地图个人最佳 · {{ formatMs(ui.personalBestMs) }}
      </p>
    </section>
  </div>
</template>

<style scoped>
.race-result {
  position: absolute;
  inset: 0;
  z-index: 70;
  display: grid;
  place-items: center;
  pointer-events: none;
}

.race-result--banner {
  inset: auto 0 auto;
  top: 78px;
  display: flex;
  justify-content: center;
}

.race-result__banner {
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 10px 15px;
  border: 1px solid rgba(var(--rst-accent-rgb), 0.3);
  border-radius: 11px;
  background: rgba(8, 16, 28, 0.9);
  box-shadow: 0 14px 36px rgba(0, 0, 0, 0.35);
  backdrop-filter: blur(8px);
}

.race-result__banner-title {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  color: var(--rst-accent);
  font-size: 11px;
  font-weight: 600;
}

.race-result__banner-sub,
.race-result__banner-time {
  color: var(--rst-muted);
  font-size: 10px;
}

.race-result__banner-time {
  color: var(--rst-text);
  font-variant-numeric: tabular-nums;
}

.race-result__mini {
  display: flex;
  gap: 7px;
  padding-left: 12px;
  border-left: 1px solid var(--rst-border);
  color: var(--rst-muted);
  font-size: 9px;
}

.race-result__panel {
  width: min(520px, calc(100vw - 60px));
  padding: 24px;
  border: 1px solid rgba(var(--rst-accent-rgb), 0.26);
  border-radius: 18px;
  background: linear-gradient(155deg, rgba(17, 29, 45, 0.98), rgba(6, 11, 19, 0.98));
  box-shadow: 0 28px 80px rgba(0, 0, 0, 0.5);
}

.race-result__head {
  display: flex;
  align-items: center;
  gap: 13px;
}

.race-result__icon {
  display: grid;
  place-items: center;
  width: 42px;
  height: 42px;
  border: 1px solid rgba(255, 209, 103, 0.3);
  border-radius: 12px;
  color: #ffd167;
  background: rgba(255, 209, 103, 0.1);
}

.race-result__eyebrow {
  margin: 0 0 3px;
  color: var(--rst-muted);
  font-size: 9px;
  letter-spacing: 0.14em;
}

.race-result__head h2 {
  margin: 0;
  font-size: 22px;
  font-weight: 600;
}

.race-result__head p:last-child {
  margin: 4px 0 0;
  color: var(--rst-muted);
  font-size: 11px;
}

.race-result__timer {
  display: flex;
  align-items: center;
  gap: 6px;
  margin: 18px 0 12px;
  padding: 8px 10px;
  border-radius: 8px;
  background: rgba(var(--rst-accent-rgb), 0.07);
  color: var(--rst-accent);
  font-size: 11px;
}

.race-result__podium {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.race-result__teams {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 7px;
  margin-bottom: 10px;
}

.race-result__team-score {
  display: flex;
  flex-direction: column;
  gap: 2px;
  padding: 8px 9px;
  border: 1px solid var(--rst-border);
  border-radius: 8px;
  font-size: 10px;
}

.race-result__team-score strong {
  font-size: 17px;
  color: var(--rst-text);
}

.race-result__team-score small {
  color: var(--rst-muted);
  font-size: 9px;
}

.race-result__team-score--red {
  color: #ff9b9b;
  border-color: rgba(255, 110, 110, 0.3);
  background: rgba(255, 110, 110, 0.07);
}

.race-result__team-score--blue {
  color: #9cc9ff;
  border-color: rgba(100, 170, 255, 0.3);
  background: rgba(100, 170, 255, 0.07);
}

.race-result__row {
  display: grid;
  grid-template-columns: 34px minmax(0, 1fr) auto;
  align-items: center;
  gap: 9px;
  padding: 9px 10px;
  border: 1px solid var(--rst-border);
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.025);
}

.race-result__row.is-me {
  border-color: rgba(var(--rst-accent-rgb), 0.35);
  background: rgba(var(--rst-accent-rgb), 0.08);
}

.race-result__row.is-red {
  border-left: 2px solid rgba(255, 110, 110, 0.7);
}

.race-result__row.is-blue {
  border-left: 2px solid rgba(100, 170, 255, 0.7);
}

.race-result__name small {
  margin-left: 5px;
  color: var(--rst-muted);
  font-size: 8px;
}

.race-result__rank {
  color: var(--rst-accent);
  font-size: 11px;
  font-weight: 600;
}

.race-result__name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 12px;
}

.race-result__time {
  color: var(--rst-muted);
  font-size: 10px;
  font-variant-numeric: tabular-nums;
}

.race-result__empty,
.race-result__mine {
  margin: 12px 0 0;
  color: var(--rst-muted);
  font-size: 10px;
}

.race-result__mine {
  padding-top: 11px;
  border-top: 1px solid var(--rst-border);
}

.race-result__best {
  margin: 9px 0 0;
  color: #ffd167;
  font-size: 10px;
}
</style>
