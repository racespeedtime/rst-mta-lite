<script setup lang="ts">
import { computed } from 'vue'

import { session } from '@/stores/session'

function clampPercent(value: number): number {
  return Math.min(100, Math.max(0, Number(value) || 0))
}

const healthWidth = computed(() => `${clampPercent(session.health)}%`)
const armorWidth = computed(() => `${clampPercent(session.armor)}%`)
</script>

<template>
  <div class="hud">
    <div class="hud__top">
      <div class="hud__brand">
        <span class="hud__dot" />
        <span class="hud__brand-name">RST MTA LITE</span>
        <span class="hud__revision">v{{ session.revision }}</span>
      </div>
      <div class="hud__player">
        <strong>{{ session.playerName }}</strong>
        <span>{{ session.serverName }} · {{ session.online }} 在线</span>
      </div>
    </div>

    <div class="hud__vitals">
      <div class="vital">
        <span class="vital__label">HP</span>
        <div class="vital__track">
          <div class="vital__fill vital__fill--health" :style="{ width: healthWidth }" />
        </div>
        <span class="vital__value">{{ session.health }}</span>
      </div>
      <div class="vital">
        <span class="vital__label">AR</span>
        <div class="vital__track">
          <div class="vital__fill vital__fill--armor" :style="{ width: armorWidth }" />
        </div>
        <span class="vital__value">{{ session.armor }}</span>
      </div>
    </div>

    <div class="hud__hint">F2 · 菜单</div>
  </div>
</template>

<style scoped>
.hud {
  position: absolute;
  inset: 0;
  pointer-events: none;
  font-size: 13px;
}

.hud__top {
  position: absolute;
  top: 20px;
  left: 24px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.hud__brand {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  width: fit-content;
  padding: 6px 12px;
  border: 1px solid var(--rst-border);
  border-radius: 999px;
  background: var(--rst-panel-soft);
  backdrop-filter: blur(6px);
}

.hud__dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: var(--rst-accent);
  box-shadow: 0 0 8px var(--rst-accent);
}

.hud__brand-name {
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.18em;
}

.hud__revision {
  font-size: 10px;
  color: var(--rst-muted);
  letter-spacing: 0.06em;
}

.hud__player {
  display: flex;
  flex-direction: column;
  gap: 2px;
  padding-left: 4px;
}

.hud__player strong {
  font-size: 15px;
  font-weight: 600;
  letter-spacing: 0.02em;
}

.hud__player span {
  font-size: 11px;
  color: var(--rst-muted);
}

.hud__vitals {
  position: absolute;
  left: 24px;
  bottom: 24px;
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.vital {
  display: flex;
  align-items: center;
  gap: 8px;
}

.vital__label {
  width: 18px;
  font-size: 10px;
  letter-spacing: 0.08em;
  color: var(--rst-muted);
}

.vital__track {
  width: 180px;
  height: 6px;
  border-radius: 3px;
  background: rgba(255, 255, 255, 0.12);
  overflow: hidden;
}

.vital__fill {
  height: 100%;
  border-radius: inherit;
  transition: width 0.25s ease;
}

.vital__fill--health {
  background: linear-gradient(90deg, #34d399, #a3e635);
}

.vital__fill--armor {
  background: linear-gradient(90deg, #38bdf8, #818cf8);
}

.vital__value {
  width: 26px;
  font-size: 11px;
  color: var(--rst-muted);
  font-variant-numeric: tabular-nums;
}

.hud__hint {
  position: absolute;
  right: 24px;
  bottom: 24px;
  padding: 6px 10px;
  border: 1px solid var(--rst-border);
  border-radius: 8px;
  background: var(--rst-panel-soft);
  font-size: 11px;
  letter-spacing: 0.06em;
  color: var(--rst-muted);
}
</style>
