<script setup lang="ts">
import { computed } from 'vue'

import IconRewind from '~icons/lucide/rewind'
import { ui } from '@/stores/ui'
import { formatSeconds } from '@/utils/format'

const progressWidth = computed(
  () => `${Math.round(Math.max(0, Math.min(1, ui.rewind.progress)) * 100)}%`,
)
</script>

<template>
  <div class="rewind">
    <div class="rewind__head">
      <span class="rewind__title">
        <IconRewind class="icon" />
        倒带
      </span>
      <span class="rewind__time">{{ formatSeconds(ui.rewind.seconds) }}</span>
    </div>
    <div class="rewind__track">
      <div class="rewind__fill" :style="{ width: progressWidth }" />
    </div>
    <p class="rewind__hint">松开 Y 后 0.5 秒继续</p>
  </div>
</template>

<style scoped>
.rewind {
  position: absolute;
  left: 50%;
  bottom: 86px;
  width: min(360px, calc(100vw - 120px));
  transform: translateX(-50%);
  padding: 12px 16px;
  border: 1px solid rgba(var(--rst-accent-rgb), 0.35);
  border-radius: 13px;
  background: linear-gradient(160deg, rgba(16, 32, 52, 0.86), rgba(6, 12, 22, 0.9));
  box-shadow: 0 16px 44px rgba(0, 0, 0, 0.4), 0 0 30px rgba(var(--rst-accent-rgb), 0.08);
  pointer-events: none;
}

.rewind__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.rewind__title {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  font-weight: 600;
  letter-spacing: 0.16em;
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
  background: linear-gradient(90deg, rgba(var(--rst-accent-rgb), 0.55), var(--rst-accent));
  box-shadow: 0 0 12px rgba(var(--rst-accent-rgb), 0.5);
}

.rewind__hint {
  margin: 8px 0 0;
  font-size: 10px;
  letter-spacing: 0.08em;
  color: var(--rst-muted);
}
</style>
