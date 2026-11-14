<script setup lang="ts">
import { computed } from 'vue'

import { ui } from '@/stores/ui'

const progress = computed(() => ui.progress)
const percent = computed(() =>
  progress.value ? Math.max(0, Math.min(100, progress.value.percent)) : 0,
)
</script>

<template>
  <div
    v-if="progress && ui.mode === 'playing' && !ui.raceResult"
    class="track-progress"
  >
    <div class="track-progress__head">
      <span>完赛进度</span>
      <strong>{{ percent }}%</strong>
      <span v-if="progress.finished" class="track-progress__done">已完成</span>
      <span v-else class="track-progress__distance">距终点 {{ progress.distance }}m</span>
    </div>
    <div class="track-progress__bar">
      <i :style="{ width: `${percent}%` }" />
    </div>
  </div>
</template>

<style scoped>
.track-progress {
  position: absolute;
  top: 66px;
  left: 50%;
  transform: translateX(-50%);
  width: min(360px, calc(100vw - 500px));
  padding: 7px 11px;
  border: 1px solid var(--rst-border);
  border-radius: 9px;
  background: rgba(8, 16, 28, 0.82);
  box-shadow: 0 10px 24px rgba(0, 0, 0, 0.24);
  backdrop-filter: blur(8px);
  pointer-events: none;
}

.track-progress__head {
  display: flex;
  align-items: baseline;
  gap: 7px;
  color: var(--rst-muted);
  font-size: 9px;
}

.track-progress__head strong {
  color: var(--rst-accent);
  font-size: 12px;
  font-variant-numeric: tabular-nums;
}

.track-progress__distance,
.track-progress__done {
  margin-left: auto;
  color: var(--rst-muted);
  font-size: 9px;
}

.track-progress__done {
  color: var(--rst-green);
}

.track-progress__bar {
  height: 4px;
  margin-top: 5px;
  border-radius: 2px;
  background: rgba(255, 255, 255, 0.1);
  overflow: hidden;
}

.track-progress__bar i {
  display: block;
  height: 100%;
  border-radius: inherit;
  background: linear-gradient(90deg, rgba(88, 200, 255, 0.55), var(--rst-accent));
  transition: width 0.4s ease;
}
</style>
