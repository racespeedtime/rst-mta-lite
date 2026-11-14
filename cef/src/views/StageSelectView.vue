<script setup lang="ts">
import IconChevronRight from '~icons/lucide/chevron-right'
import IconClock from '~icons/lucide/clock'
import IconEye from '~icons/lucide/eye'
import IconFlag from '~icons/lucide/flag'
import IconInfo from '~icons/lucide/info'
import IconMap from '~icons/lucide/map'
import IconPenLine from '~icons/lucide/pen-line'
import IconRefreshCw from '~icons/lucide/refresh-cw'
import IconTrophy from '~icons/lucide/trophy'
import IconUser from '~icons/lucide/user'
import IconUsers from '~icons/lucide/users'
import { emitAction } from '@/mta/bridge'
import type { RoomSummary } from '@/mta/protocol'
import { ui } from '@/stores/ui'
import { formatMs } from '@/utils/format'

function select(room: RoomSummary): void {
  if (ui.busy || ui.mapPoolEmpty) return
  ui.busy = true
  emitAction('stage:select', { room: room.id })
}

function openDetails(room: RoomSummary): void {
  ui.mapDetails = room.mapDetails || null
  ui.mapDetailsOpen = true
}

function refresh(): void {
  emitAction('stage:refresh')
}

function statusLabel(room: RoomSummary): string {
  if (room.waiting) return '准备中'
  if (room.active) return '进行中'
  if (room.voteActive) return '投票中'
  return '空闲'
}

function actionLabel(room: RoomSummary): string {
  if (room.voteActive) return '等待换图'
  return room.active && room.players > 0 ? '进入观战' : '加入比赛'
}
</script>

<template>
  <div class="stage">
    <div class="stage__grid-bg" />
    <div class="stage__glow" />

    <header class="stage__head">
      <div>
        <p class="stage__eyebrow">
          <IconFlag class="icon icon--sm" />
          <span>RST MTA LITE · 竞速</span>
        </p>
        <h1 class="stage__title">选择对战舞台</h1>
        <p class="stage__subtitle">
          <IconUser class="icon icon--sm" />
          <span>{{ ui.playerName }}</span>
          <span class="stage__dot" />
          <span>{{ ui.guest ? '游客' : '正式账号' }}</span>
          <span class="stage__dot" />
          <span>{{ ui.serverName }}</span>
        </p>
      </div>
      <button type="button" class="stage__refresh" :disabled="ui.busy" @click="refresh">
        <IconRefreshCw class="icon icon--sm" />
        <span>刷新</span>
      </button>
    </header>

    <div v-if="ui.mapPoolEmpty" class="stage__warning">
      地图池为空，当前无法加入比赛。请联系管理员在 config.mapPool 添加地图。
    </div>

    <div class="stage__list">
      <div
        v-for="room in ui.rooms"
        :key="room.id"
        class="stage-card"
        :class="{
          'stage-card--live': room.active,
          'stage-card--vote': room.voteActive,
          'stage-card--disabled': ui.busy || ui.mapPoolEmpty,
        }"
        role="button"
        tabindex="0"
        :aria-disabled="ui.busy || ui.mapPoolEmpty"
        @click="select(room)"
        @keydown.enter.prevent="select(room)"
      >
        <span class="stage-card__accent" />

        <div class="stage-card__top">
          <span class="stage-card__icon"><IconFlag class="icon icon--lg" /></span>
          <span class="stage-card__name">{{ room.name }}</span>
          <span class="stage-card__badge">
            <span class="stage-card__badge-dot" />
            {{ statusLabel(room) }}
          </span>
          <IconChevronRight class="icon stage-card__arrow" />
        </div>

        <p class="stage-card__map">
          <IconMap class="icon" />
          <span>{{ room.mapName }}</span>
        </p>
        <p class="stage-card__author">
          <IconPenLine class="icon icon--sm" />
          <span>作者 · {{ room.author }}</span>
        </p>

        <div class="stage-card__meta">
          <span><IconUsers class="icon icon--sm" />{{ room.players }} 玩家</span>
          <span><IconEye class="icon icon--sm" />{{ room.spectators }} 观战</span>
          <span>
            <IconTrophy class="icon icon--sm" />
            {{ room.gameMode === 'competitive' ? (room.competitiveMode === 'team' ? '团队竞技' : '个人竞技') : '训练' }}
          </span>
          <span>
            <IconClock class="icon icon--sm" />
            <template v-if="room.waiting">等待准备</template>
            <template v-else-if="room.active">
              剩余 {{ formatMs(room.timeLeftMs ?? room.timeLeft * 1000) }}
            </template>
            <template v-else-if="room.voteActive">换图投票中</template>
            <template v-else>等待开局</template>
          </span>
        </div>

        <div class="stage-card__foot">
          <span class="stage-card__cta">{{ actionLabel(room) }}</span>
          <button
            v-if="room.mapDetails"
            type="button"
            class="stage-card__detail"
            @click.stop="openDetails(room)"
          >
            地图详情
          </button>
          <span v-else class="stage-card__detail stage-card__detail--muted">加入后看详情</span>
        </div>
      </div>
    </div>

    <p class="stage__hint">
      <IconInfo class="icon icon--sm" />
      <span>进入已有玩家的舞台会先观战，下一回合自动加入比赛。</span>
    </p>
  </div>
</template>

<style scoped>
.stage {
  position: absolute;
  inset: 0;
  pointer-events: auto;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 26px;
  padding: 0 62px;
  overflow: hidden;
  background:
    radial-gradient(circle at 16% -10%, rgba(44, 110, 180, 0.24), transparent 50%),
    radial-gradient(circle at 92% 108%, rgba(139, 124, 255, 0.14), transparent 46%),
    linear-gradient(180deg, #050a12 0%, #04070c 100%);
}

.stage__grid-bg {
  position: absolute;
  inset: -12%;
  background-image:
    linear-gradient(rgba(120, 170, 255, 0.05) 1px, transparent 1px),
    linear-gradient(90deg, rgba(120, 170, 255, 0.05) 1px, transparent 1px);
  background-size: 50px 50px;
  mask-image: radial-gradient(circle at 50% 20%, #000 0%, transparent 75%);
  -webkit-mask-image: radial-gradient(circle at 50% 20%, #000 0%, transparent 75%);
  pointer-events: none;
}

.stage__glow {
  position: absolute;
  top: -220px;
  left: 38%;
  width: 620px;
  height: 420px;
  border-radius: 50%;
  background: radial-gradient(circle, rgba(88, 200, 255, 0.12), transparent 65%);
  filter: blur(20px);
  pointer-events: none;
}

.stage__head,
.stage__list,
.stage__hint,
.stage__warning {
  position: relative;
  width: 100%;
  max-width: 980px;
}

.stage__head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 24px;
}

.stage__eyebrow {
  display: flex;
  align-items: center;
  gap: 7px;
  margin: 0 0 8px;
  font-size: 10px;
  letter-spacing: 0.22em;
  color: var(--rst-muted);
}

.stage__title {
  margin: 0;
  font-size: 32px;
  font-weight: 600;
  letter-spacing: 0.01em;
}

.stage__subtitle {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  margin: 10px 0 0;
  font-size: 12px;
  color: var(--rst-muted);
}

.stage__dot {
  width: 3px;
  height: 3px;
  border-radius: 50%;
  background: var(--rst-muted);
  opacity: 0.7;
}

.stage__refresh {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  padding: 9px 14px;
  border: 1px solid var(--rst-border);
  border-radius: 10px;
  color: var(--rst-muted);
  font-size: 12px;
  background: rgba(255, 255, 255, 0.03);
  transition: color 0.15s ease, border-color 0.15s ease, background 0.15s ease;
}

.stage__refresh:hover:not(:disabled) {
  color: var(--rst-text);
  border-color: rgba(88, 200, 255, 0.4);
  background: rgba(88, 200, 255, 0.08);
}

.stage__list {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(380px, 1fr));
  gap: 18px;
}

.stage__warning {
  margin-top: 20px;
  padding: 10px 13px;
  border: 1px solid rgba(255, 190, 92, 0.28);
  border-radius: 10px;
  background: rgba(255, 190, 92, 0.08);
  color: #ffd18a;
  font-size: 12px;
}

.stage-card {
  position: relative;
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 20px 22px 18px;
  border: 1px solid var(--rst-border);
  border-radius: 18px;
  background: linear-gradient(160deg, rgba(20, 33, 52, 0.9), rgba(8, 13, 22, 0.94));
  text-align: left;
  color: var(--rst-text);
  cursor: pointer;
  overflow: hidden;
  transition: transform 0.18s ease, border-color 0.18s ease, box-shadow 0.18s ease;
}

.stage-card:focus-visible {
  outline: 1px solid rgba(88, 200, 255, 0.6);
  outline-offset: 2px;
}

.stage-card:hover:not(.stage-card--disabled) {
  transform: translateY(-3px);
  border-color: rgba(88, 200, 255, 0.45);
  box-shadow: 0 24px 56px rgba(0, 0, 0, 0.4), 0 0 0 1px rgba(88, 200, 255, 0.08);
}

.stage-card--disabled {
  opacity: 0.6;
  cursor: default;
}

.stage-card__accent {
  position: absolute;
  inset: 0 0 auto;
  height: 2px;
  background: linear-gradient(90deg, rgba(88, 200, 255, 0.7), rgba(139, 124, 255, 0.5), transparent);
  opacity: 0.5;
}

.stage-card--live .stage-card__accent {
  background: linear-gradient(90deg, rgba(126, 226, 168, 0.85), rgba(88, 200, 255, 0.5), transparent);
  opacity: 0.9;
}

.stage-card__top {
  display: flex;
  align-items: center;
  gap: 10px;
}

.stage-card__icon {
  display: grid;
  place-items: center;
  width: 36px;
  height: 36px;
  border-radius: 11px;
  border: 1px solid rgba(88, 200, 255, 0.22);
  background: linear-gradient(150deg, rgba(88, 200, 255, 0.18), rgba(139, 124, 255, 0.1));
  color: var(--rst-accent);
}

.stage-card__name {
  font-size: 15px;
  font-weight: 600;
  flex: 1;
}

.stage-card__badge {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 3px 9px;
  border: 1px solid var(--rst-border);
  border-radius: 999px;
  font-size: 10px;
  color: var(--rst-muted);
  white-space: nowrap;
}

.stage-card__badge-dot {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background: currentColor;
  opacity: 0.8;
}

.stage-card--live .stage-card__badge {
  color: var(--rst-green);
  border-color: rgba(126, 226, 168, 0.32);
}

.stage-card--vote .stage-card__badge {
  color: var(--rst-gold);
  border-color: rgba(255, 212, 121, 0.32);
}

.stage-card__arrow {
  color: var(--rst-muted);
  opacity: 0.6;
  transition: transform 0.15s ease, opacity 0.15s ease;
}

.stage-card:hover .stage-card__arrow {
  transform: translateX(2px);
  opacity: 1;
}

.stage-card__map {
  display: flex;
  align-items: center;
  gap: 7px;
  margin: 6px 0 0;
  font-size: 14px;
  color: var(--rst-accent);
}

.stage-card__author {
  display: flex;
  align-items: center;
  gap: 6px;
  margin: 0;
  font-size: 11px;
  color: var(--rst-muted);
}

.stage-card__meta {
  display: flex;
  flex-wrap: wrap;
  gap: 7px 14px;
  margin-top: 8px;
  font-size: 11px;
  color: var(--rst-muted);
}

.stage-card__meta span {
  display: inline-flex;
  align-items: center;
  gap: 5px;
}

.stage-card__foot {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  margin-top: 12px;
  padding-top: 12px;
  border-top: 1px solid var(--rst-border);
}

.stage-card__cta {
  font-size: 12px;
  color: var(--rst-text);
  letter-spacing: 0.02em;
  display: flex;
  align-items: center;
}

.stage-card__cta::after {
  content: '›';
  font-size: 18px;
  line-height: 1;
  margin-left: 6px;
  color: var(--rst-accent);
}

.stage-card__detail {
  flex: 0 0 auto;
  padding: 4px 8px;
  border: 1px solid var(--rst-border);
  border-radius: 6px;
  color: var(--rst-muted);
  font-size: 10px;
  background: rgba(255, 255, 255, 0.03);
}

.stage-card__detail:hover {
  color: var(--rst-text);
  border-color: rgba(88, 200, 255, 0.4);
  background: rgba(88, 200, 255, 0.08);
}

.stage-card__detail--muted {
  opacity: 0.55;
  font-size: 9px;
}

.stage__hint {
  display: flex;
  align-items: center;
  gap: 7px;
  margin: 0;
  font-size: 11px;
  color: var(--rst-muted);
}

@media (max-width: 900px) {
  .stage {
    padding: 0 40px;
  }

  .stage__list {
    grid-template-columns: 1fr;
  }
}
</style>
