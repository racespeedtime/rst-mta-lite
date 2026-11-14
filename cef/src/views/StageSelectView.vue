<script setup lang="ts">
import { emitAction } from '@/mta/bridge'
import type { RoomSummary } from '@/mta/protocol'
import { ui } from '@/stores/ui'
import { formatTime } from '@/utils/format'

function select(room: RoomSummary): void {
  if (ui.busy) return
  ui.busy = true
  emitAction('stage:select', { room: room.id })
}

function refresh(): void {
  emitAction('stage:refresh')
}
</script>

<template>
  <div class="stage">
    <header class="stage__head">
      <div>
        <p class="stage__eyebrow">RST MTA LITE</p>
        <h1 class="stage__title">选择对战舞台</h1>
        <p class="stage__subtitle">
          {{ ui.playerName }} · {{ ui.guest ? '游客' : '正式账号' }} · {{ ui.serverName }}
        </p>
      </div>
      <button type="button" class="stage__refresh" :disabled="ui.busy" @click="refresh">刷新</button>
    </header>

    <div class="stage__grid">
      <button
        v-for="room in ui.rooms"
        :key="room.id"
        type="button"
        class="stage-card"
        :class="{ 'stage-card--live': room.active }"
        :disabled="ui.busy"
        @click="select(room)"
      >
        <div class="stage-card__top">
          <span class="stage-card__name">{{ room.name }}</span>
          <span class="stage-card__badge">
            {{ room.active ? '进行中' : room.voteActive ? '投票中' : '空闲' }}
          </span>
        </div>

        <p class="stage-card__map">{{ room.mapName }}</p>

        <div class="stage-card__meta">
          <span>{{ room.players }} 玩家</span>
          <span>{{ room.spectators }} 观战</span>
          <span v-if="room.active">剩余 {{ formatTime(room.timeLeft) }}</span>
          <span v-else-if="room.voteActive">换图投票中</span>
          <span v-else>等待开局</span>
        </div>

        <span class="stage-card__hint">
          {{
            room.voteActive
              ? '等待换图'
              : room.active && room.players > 0
                ? '进入观战'
                : '加入战斗'
          }}
        </span>
      </button>
    </div>

    <p class="stage__hint">进入已有玩家的舞台会先观战，下一回合自动加入战斗。</p>
  </div>
</template>

<style scoped>
.stage {
  position: absolute;
  inset: 0;
  pointer-events: auto;
  display: flex;
  flex-direction: column;
  gap: 26px;
  padding: 56px 64px;
  background:
    radial-gradient(circle at 20% 0%, rgba(38, 92, 160, 0.16), transparent 45%),
    radial-gradient(circle at 85% 100%, rgba(130, 80, 255, 0.1), transparent 40%),
    rgba(4, 8, 14, 0.6);
}

.stage__head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 24px;
}

.stage__eyebrow {
  margin: 0 0 6px;
  font-size: 10px;
  letter-spacing: 0.24em;
  color: var(--rst-muted);
}

.stage__title {
  margin: 0;
  font-size: 30px;
  font-weight: 600;
  letter-spacing: 0.02em;
}

.stage__subtitle {
  margin: 8px 0 0;
  font-size: 12px;
  color: var(--rst-muted);
}

.stage__refresh {
  padding: 8px 14px;
  border: 1px solid var(--rst-border);
  border-radius: 8px;
  color: var(--rst-muted);
  font-size: 12px;
  transition: color 0.15s ease, border-color 0.15s ease;
}

.stage__refresh:hover:not(:disabled) {
  color: var(--rst-text);
  border-color: rgba(76, 194, 255, 0.4);
}

.stage__grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 18px;
  max-width: 900px;
}

.stage-card {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 22px;
  border: 1px solid var(--rst-border);
  border-radius: 16px;
  background: linear-gradient(160deg, rgba(18, 30, 48, 0.92), rgba(8, 13, 22, 0.92));
  text-align: left;
  transition: transform 0.16s ease, border-color 0.16s ease, box-shadow 0.16s ease;
}

.stage-card:hover:not(:disabled) {
  transform: translateY(-2px);
  border-color: rgba(76, 194, 255, 0.45);
  box-shadow: 0 18px 46px rgba(0, 0, 0, 0.35);
}

.stage-card:disabled {
  opacity: 0.6;
}

.stage-card__top {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
}

.stage-card__name {
  font-size: 16px;
  font-weight: 600;
}

.stage-card__badge {
  padding: 3px 9px;
  border: 1px solid var(--rst-border);
  border-radius: 999px;
  font-size: 10px;
  letter-spacing: 0.08em;
  color: var(--rst-muted);
}

.stage-card--live .stage-card__badge {
  color: #7ee2a8;
  border-color: rgba(126, 226, 168, 0.35);
}

.stage-card__map {
  margin: 0;
  font-size: 13px;
  color: var(--rst-accent);
}

.stage-card__meta {
  display: flex;
  flex-wrap: wrap;
  gap: 8px 16px;
  font-size: 11px;
  color: var(--rst-muted);
}

.stage-card__hint {
  margin-top: 4px;
  font-size: 12px;
  color: var(--rst-text);
}

.stage__hint {
  margin: 0;
  font-size: 11px;
  color: var(--rst-muted);
}
</style>
