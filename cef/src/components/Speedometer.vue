<script setup lang="ts">
import { computed } from 'vue'

import IconCar from '~icons/lucide/car'
import IconHeart from '~icons/lucide/heart'
import IconZap from '~icons/lucide/zap'
import { ui } from '@/stores/ui'

const MAX_SPEED = 240

const speed = computed(() => Math.round(ui.vehicle?.speed ?? 0))
const speedPercent = computed(() =>
  Math.min(100, Math.max(0, (speed.value / MAX_SPEED) * 100)),
)
const gear = computed(() => Math.max(0, Math.floor(ui.vehicle?.gear ?? 0)))
const healthPercent = computed(() =>
  Math.min(100, Math.max(0, Math.round(ui.vehicle?.healthPercent ?? 0))),
)
const healthTone = computed(() => {
  if (healthPercent.value > 60) return 'good'
  if (healthPercent.value > 30) return 'warn'
  return 'bad'
})
const hasNitro = computed(() => ui.vehicle?.hasNitro === true)
const nitroPercent = computed(() =>
  Math.min(100, Math.max(0, Math.round(ui.vehicle?.nitroPercent ?? 0))),
)
const nitroActive = computed(() => ui.vehicle?.nitroActive === true)
const nitroRecharging = computed(() => ui.vehicle?.nitroRecharging === true)
const nitroLabel = computed(() => {
  if (!hasNitro.value) return '无氮气'
  if (ui.vehicle?.nitroInfinite) return '∞'
  return `x${ui.vehicle?.nitroCount ?? 0}`
})
</script>

<template>
  <div class="speedo">
    <header class="speedo__head">
      <span class="speedo__vehicle">
        <IconCar class="icon icon--sm" />
        <span>{{ ui.vehicle?.name || '车辆' }}</span>
      </span>
      <span v-if="gear > 0" class="speedo__gear">{{ gear }}</span>
    </header>

    <div class="speedo__value">
      <span class="speedo__speed">{{ speed }}</span>
      <span class="speedo__unit">km/h</span>
    </div>

    <div class="speedo__bar">
      <div class="speedo__bar-fill" :style="{ width: `${speedPercent}%` }" />
    </div>

    <div class="speedo__meters">
      <div class="meter">
        <span class="meter__icon meter__icon--health"><IconHeart class="icon icon--sm" /></span>
        <div class="meter__body">
          <div class="meter__track">
            <div
              class="meter__fill meter__fill--health"
              :class="healthTone"
              :style="{ width: `${healthPercent}%` }"
            />
          </div>
        </div>
        <span class="meter__value">{{ healthPercent }}%</span>
      </div>

      <div class="meter">
        <span class="meter__icon meter__icon--nitro" :class="{ 'is-active': nitroActive }">
          <IconZap class="icon icon--sm" />
        </span>
        <div class="meter__body">
          <div class="meter__track">
            <div
              class="meter__fill meter__fill--nitro"
              :class="{ 'is-active': nitroActive, 'is-recharging': nitroRecharging }"
              :style="{ width: `${nitroPercent}%` }"
            />
          </div>
        </div>
        <span class="meter__value">{{ nitroLabel }}</span>
      </div>
    </div>
  </div>
</template>

<style scoped>
.speedo {
  position: absolute;
  left: 50%;
  bottom: 24px;
  width: 292px;
  transform: translateX(-50%);
  padding: 13px 16px 12px;
  border: 1px solid var(--rst-border);
  border-radius: 18px;
  background: linear-gradient(180deg, rgba(12, 20, 32, 0.92), rgba(6, 11, 19, 0.95));
  box-shadow: var(--rst-shadow);
  pointer-events: none;
}

.speedo::before {
  content: '';
  position: absolute;
  inset: 0 0 auto;
  height: 1px;
  border-radius: 18px 18px 0 0;
  background: linear-gradient(90deg, transparent, rgba(88, 200, 255, 0.5), transparent);
  opacity: 0.55;
}

.speedo__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
}

.speedo__vehicle {
  display: flex;
  align-items: center;
  gap: 6px;
  min-width: 0;
  color: var(--rst-muted);
  font-size: 11px;
  letter-spacing: 0.03em;
}

.speedo__vehicle span {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.speedo__vehicle .icon {
  color: var(--rst-accent);
}

.speedo__gear {
  padding: 2px 7px;
  border: 1px solid rgba(88, 200, 255, 0.3);
  border-radius: 6px;
  color: var(--rst-accent);
  font-size: 10px;
  font-variant-numeric: tabular-nums;
}

.speedo__value {
  display: flex;
  align-items: baseline;
  justify-content: center;
  gap: 6px;
  margin: 5px 0 5px;
}

.speedo__speed {
  font-size: 46px;
  font-weight: 600;
  line-height: 1;
  letter-spacing: 0.01em;
  font-variant-numeric: tabular-nums;
  color: var(--rst-text);
  text-shadow: 0 0 24px rgba(88, 200, 255, 0.16);
}

.speedo__unit {
  font-size: 10px;
  letter-spacing: 0.18em;
  color: var(--rst-muted);
}

.speedo__bar {
  height: 5px;
  border-radius: 3px;
  background: rgba(255, 255, 255, 0.08);
  overflow: hidden;
}

.speedo__bar-fill {
  height: 100%;
  border-radius: inherit;
  background: linear-gradient(90deg, #58c8ff, #8b7cff 62%, #ffd479);
  box-shadow: 0 0 12px rgba(88, 200, 255, 0.4);
  transition: width 0.12s linear;
}

.speedo__meters {
  display: flex;
  flex-direction: column;
  gap: 6px;
  margin-top: 11px;
}

.meter {
  display: flex;
  align-items: center;
  gap: 8px;
}

.meter__icon {
  display: grid;
  place-items: center;
  width: 22px;
  height: 22px;
  border-radius: 7px;
}

.meter__icon--health {
  color: #7ee2a8;
  background: rgba(126, 226, 168, 0.12);
}

.meter__icon--nitro {
  color: var(--rst-accent);
  background: rgba(88, 200, 255, 0.12);
  transition: color 0.15s ease, background 0.15s ease;
}

.meter__icon--nitro.is-active {
  color: var(--rst-gold);
  background: rgba(255, 212, 121, 0.14);
}

.meter__body {
  flex: 1;
}

.meter__track {
  height: 4px;
  border-radius: 2px;
  background: rgba(255, 255, 255, 0.08);
  overflow: hidden;
}

.meter__fill {
  height: 100%;
  border-radius: inherit;
  transition: width 0.15s linear, background 0.15s ease;
}

.meter__fill--health.good {
  background: linear-gradient(90deg, #34d399, #a3e635);
}

.meter__fill--health.warn {
  background: linear-gradient(90deg, #fbbf24, #f59e0b);
}

.meter__fill--health.bad {
  background: linear-gradient(90deg, #f87171, #ef4444);
}

.meter__fill--nitro {
  background: linear-gradient(90deg, #58c8ff, #8b7cff);
}

.meter__fill--nitro.is-active {
  background: linear-gradient(90deg, #ffd479, #ff9f43);
  box-shadow: 0 0 10px rgba(255, 212, 121, 0.55);
}

.meter__fill--nitro.is-recharging {
  opacity: 0.7;
}

.meter__value {
  width: 38px;
  text-align: right;
  font-size: 10px;
  font-variant-numeric: tabular-nums;
  color: var(--rst-muted);
}
</style>
