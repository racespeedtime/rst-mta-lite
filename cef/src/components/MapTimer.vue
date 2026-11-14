<script setup lang="ts">
import { computed } from 'vue'

import IconClock from '~icons/lucide/clock'
import IconMap from '~icons/lucide/map'
import IconTimer from '~icons/lucide/timer'
import IconTrophy from '~icons/lucide/trophy'
import { useTicker } from '@/composables/useTicker'
import { ui } from '@/stores/ui'
import { formatMs } from '@/utils/format'

const now = useTicker()
const voteActive = computed(() => ui.vote?.active === true)
const remainingLabel = computed(() => (voteActive.value ? '投票' : '剩余'))

const elapsedMs = computed(() => (ui.stateAt ? Math.max(0, now.value - ui.stateAt) : 0))

const remainingMs = computed(() => {
  const base = voteActive.value
    ? (ui.vote?.timeLeftMs ?? (ui.vote?.timeLeft ?? 0) * 1000)
    : (ui.room?.timeLeftMs ?? (ui.room?.timeLeft ?? 0) * 1000)
  return Math.max(0, base - elapsedMs.value)
})

const remainingValue = computed(() => formatMs(remainingMs.value))
const remainingTone = computed(() => {
  if (voteActive.value) return 'is-vote'
  if (remainingMs.value <= 60_000) return 'is-danger'
  if (remainingMs.value <= 300_000) return 'is-warn'
  return ''
})

const personalMs = computed(
  () => (ui.mapTimeMs || ui.mapTime * 1000) + elapsedMs.value,
)
const personalTime = computed(() => formatMs(personalMs.value))
const bestMs = computed(() => ui.personalBestMs)
</script>

<template>
  <div class="maptimer">
    <span class="maptimer__map">
      <IconMap class="icon icon--sm" />
      <span>{{ ui.room?.mapName }}</span>
    </span>

    <span class="maptimer__divider" />

    <span class="maptimer__item" :class="remainingTone">
      <IconTimer class="icon icon--sm" />
      <span class="maptimer__label">{{ remainingLabel }}</span>
      <strong>{{ remainingValue }}</strong>
    </span>

    <span class="maptimer__item maptimer__item--personal">
      <IconClock class="icon icon--sm" />
      <span class="maptimer__label">本图</span>
      <strong>{{ personalTime }}</strong>
    </span>

    <span class="maptimer__item maptimer__item--best">
      <IconTrophy class="icon icon--sm" />
      <span class="maptimer__label">最佳</span>
      <strong>{{ bestMs !== null ? formatMs(bestMs) : '--:--.---' }}</strong>
    </span>
  </div>
</template>

<style scoped>
.maptimer {
  position: absolute;
  top: 18px;
  left: 50%;
  transform: translateX(-50%);
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px 15px;
  border: 1px solid var(--rst-border);
  border-radius: 999px;
  background: linear-gradient(180deg, rgba(11, 19, 30, 0.86), rgba(7, 12, 20, 0.9));
  box-shadow: 0 12px 34px rgba(0, 0, 0, 0.3);
  pointer-events: none;
  white-space: nowrap;
}

.maptimer__map {
  display: flex;
  align-items: center;
  gap: 6px;
  min-width: 0;
  max-width: 210px;
  color: var(--rst-accent);
  font-size: 11px;
  letter-spacing: 0.02em;
}

.maptimer__map span {
  overflow: hidden;
  text-overflow: ellipsis;
}

.maptimer__divider {
  width: 1px;
  height: 16px;
  background: var(--rst-border);
}

.maptimer__item {
  display: flex;
  align-items: center;
  gap: 5px;
  color: var(--rst-muted);
  font-size: 10px;
  letter-spacing: 0.05em;
}

.maptimer__item strong {
  color: var(--rst-text);
  font-size: 12px;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
  letter-spacing: 0.02em;
}

.maptimer__item.is-warn strong {
  color: var(--rst-gold);
}

.maptimer__item.is-danger strong {
  color: #ff8a8a;
}

.maptimer__item.is-vote strong {
  color: var(--rst-gold);
}

.maptimer__item--personal strong {
  color: var(--rst-accent);
}

@media (max-width: 1180px) {
  .maptimer__map {
    display: none;
  }

  .maptimer__divider {
    display: none;
  }
}
</style>
