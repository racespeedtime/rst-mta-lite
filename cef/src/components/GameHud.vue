<script setup lang="ts">
import { computed } from 'vue'

import { ui } from '@/stores/ui'
import { clampPercent, formatTime } from '@/utils/format'

const healthWidth = computed(() => `${clampPercent(ui.health)}%`)
const armorWidth = computed(() => `${clampPercent(ui.armor)}%`)
const spectating = computed(() => ui.mode === 'spectating')
const modeLabel = computed(() => (spectating.value ? '观战' : '战斗中'))
const roundTime = computed(() => (ui.room ? formatTime(ui.room.timeLeft) : '--:--'))
</script>

<template>
  <div class="hud">
    <div class="hud__top">
      <div class="hud__brand">
        <span class="hud__dot" />
        <span class="hud__brand-name">RST MTA LITE</span>
      </div>
      <div class="hud__player">
        <strong>{{ ui.playerName }}</strong>
        <span>{{ ui.guest ? '游客' : '已登录' }} · {{ ui.serverName }}</span>
      </div>
    </div>

    <section v-if="ui.room" class="room">
      <div class="room__head">
        <span class="room__name">{{ ui.room.name }}</span>
        <span class="room__mode" :class="{ 'room__mode--spectate': spectating }">{{ modeLabel }}</span>
      </div>
      <p class="room__map">{{ ui.room.mapName }}</p>
      <div class="room__stats">
        <span>剩余 <strong>{{ roundTime }}</strong></span>
        <span>{{ ui.room.players }} 玩家</span>
        <span>{{ ui.room.spectators }} 观战</span>
      </div>
      <p v-if="ui.vote?.active" class="room__vote">
        换图投票 · {{ formatTime(ui.vote.timeLeft) }}
      </p>
    </section>

    <div v-if="spectating" class="spectate">观战中 · 下一回合自动加入战斗</div>

    <div class="hud__vitals">
      <div class="vital">
        <span class="vital__label">HP</span>
        <div class="vital__track">
          <div class="vital__fill vital__fill--health" :style="{ width: healthWidth }" />
        </div>
        <span class="vital__value">{{ ui.health }}</span>
      </div>
      <div class="vital">
        <span class="vital__label">AR</span>
        <div class="vital__track">
          <div class="vital__fill vital__fill--armor" :style="{ width: armorWidth }" />
        </div>
        <span class="vital__value">{{ ui.armor }}</span>
      </div>
    </div>

    <div class="hud__hints">
      <span>F2 菜单</span>
      <span v-if="!spectating">长按 Y 回放</span>
    </div>
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

.hud__player {
  display: flex;
  flex-direction: column;
  gap: 2px;
  padding-left: 4px;
}

.hud__player strong {
  font-size: 15px;
  font-weight: 600;
}

.hud__player span {
  font-size: 11px;
  color: var(--rst-muted);
}

.room {
  position: absolute;
  top: 20px;
  right: 24px;
  width: 240px;
  padding: 14px 16px;
  border: 1px solid var(--rst-border);
  border-radius: 12px;
  background: var(--rst-panel);
}

.room__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.room__name {
  font-size: 12px;
  font-weight: 600;
}

.room__mode {
  padding: 2px 8px;
  border-radius: 999px;
  font-size: 10px;
  color: #7ee2a8;
  background: rgba(126, 226, 168, 0.12);
}

.room__mode--spectate {
  color: #ffd479;
  background: rgba(255, 212, 121, 0.12);
}

.room__map {
  margin: 8px 0 10px;
  font-size: 13px;
  color: var(--rst-accent);
}

.room__stats {
  display: flex;
  flex-wrap: wrap;
  gap: 6px 12px;
  font-size: 11px;
  color: var(--rst-muted);
}

.room__stats strong {
  color: var(--rst-text);
  font-variant-numeric: tabular-nums;
}

.room__vote {
  margin: 10px 0 0;
  padding-top: 8px;
  border-top: 1px solid var(--rst-border);
  font-size: 11px;
  color: #ffd479;
}

.spectate {
  position: absolute;
  top: 76px;
  left: 50%;
  transform: translateX(-50%);
  padding: 6px 14px;
  border: 1px solid rgba(255, 212, 121, 0.3);
  border-radius: 999px;
  background: rgba(40, 32, 12, 0.7);
  color: #ffd479;
  font-size: 11px;
  letter-spacing: 0.06em;
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

.hud__hints {
  position: absolute;
  right: 24px;
  bottom: 24px;
  display: flex;
  gap: 8px;
}

.hud__hints span {
  padding: 6px 10px;
  border: 1px solid var(--rst-border);
  border-radius: 8px;
  background: var(--rst-panel-soft);
  font-size: 11px;
  letter-spacing: 0.06em;
  color: var(--rst-muted);
}
</style>
