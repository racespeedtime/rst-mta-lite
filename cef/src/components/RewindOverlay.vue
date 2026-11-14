<script setup lang="ts">
import { computed } from 'vue'

import { ui } from '@/stores/ui'
import { formatSeconds } from '@/utils/format'

const progressWidth = computed(() => `${Math.round(Math.max(0, Math.min(1, ui.rewind.progress)) * 100)}%`)
</script>

<template>
  <div class="rewind">
    <div class="rewind__head">
      <span class="rewind__title">◀ REWIND</span>
      <span class="rewind__time">{{ formatSeconds(ui.rewind.seconds) }}</span>
    </div>
    <div class="rewind__track">
      <div class="rewind__fill" :style="{ width: progressWidth }" />
    </div>
    <p class="rewind__hint">松开 Y 继续</p>
  </div>
</template>

<style scoped>
.rewind {
  position: absolute;
  left: 50%;
  bottom: 82px;
  width: min(360px, calc(100vw - 120px));
  transform: translateX(-50%);
  padding: 12px 16px;
  border: 1px solid rgba(76, 194, 255, 0.35);
  border-radius: 12px;
  background: rgba(8, 16, 28, 0.78);
  box-shadow: 0 12px 36px rgba(0, 0, 0, 0.35);
  pointer-events: none;
}

.rewind__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.rewind__title {
  font-size: 12px;
  font-weight: 600;
  letter-spacing: 0.18em;
  color: var(--rst-accent);
}

.rewind__time {
  font-size: 12px;
  font-variant-numeric: tabular-nums;
  color: var(--rst-muted);
}

.rewind__track {
  margin-top: 9px;
  height: 4px;
  border-radius: 2px;
  background: rgba(255, 255, 255, 0.12);
  overflow: hidden;
}

.rewind__fill {
  height: 100%;
  border-radius: inherit;
  background: linear-gradient(90deg, rgba(76, 194, 255, 0.6), var(--rst-accent));
}

.rewind__hint {
  margin: 8px 0 0;
  font-size: 10px;
  letter-spacing: 0.08em;
  color: var(--rst-muted);
}
</style>
