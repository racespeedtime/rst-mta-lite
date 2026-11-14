<script setup lang="ts">
import { computed } from 'vue'

import IconChevronRight from '~icons/lucide/chevron-right'
import IconCar from '~icons/lucide/car'
import IconCircleQuestionMark from '~icons/lucide/circle-question-mark'
import IconCode from '~icons/lucide/code'
import IconDoorOpen from '~icons/lucide/door-open'
import IconEye from '~icons/lucide/eye'
import IconFlag from '~icons/lucide/flag'
import IconMap from '~icons/lucide/map'
import IconMapPinned from '~icons/lucide/map-pinned'
import IconMousePointer2 from '~icons/lucide/mouse-pointer-2'
import IconSettings from '~icons/lucide/settings'
import IconTrophy from '~icons/lucide/trophy'
import IconUser from '~icons/lucide/user'
import IconVote from '~icons/lucide/vote'
import IconX from '~icons/lucide/x'
import { emitAction } from '@/mta/bridge'
import { ui } from '@/stores/ui'
import { formatTime } from '@/utils/format'

const voteHint = computed(() => {
  if (ui.mapPoolEmpty) return '地图池为空'
  if (ui.vote?.active) return '投票进行中'
  if (ui.canStartVote) return '30 秒后结算'
  if (ui.voteCooldown > 0) return `冷却中 ${formatTime(ui.voteCooldown)}`
  return '当前不可发起'
})

const modeLabel = computed(() => (ui.gameMode === 'competitive' ? '竞技模式' : '训练模式'))
const spectating = computed(() => ui.mode === 'spectating')

const obLabel = computed(() => {
  if (!spectating.value) return '切换纯观战'
  return ui.ob ? '下回合参赛' : '保持纯观战'
})

const obHint = computed(() => {
  if (!spectating.value) return '放弃本回合，下回合继续观战'
  return ui.ob ? '取消纯观战，回到比赛' : '下回合不自动参赛'
})

const modeVoteHint = computed(() => {
  if (ui.modeVote?.active) return '模式投票进行中'
  if (ui.canStartModeVote) return `${modeLabel.value} · 20 秒后结算`
  if (ui.modeVoteCooldown > 0) return `冷却中 ${formatTime(ui.modeVoteCooldown)}`
  return `当前：${modeLabel.value}`
})

function close(): void {
  emitAction('menu:close')
}

function startVote(): void {
  if (!ui.canStartVote) return
  emitAction('vote:start')
  emitAction('menu:close')
}

function startModeVote(): void {
  if (!ui.canStartModeVote) return
  emitAction('modevote:start')
  emitAction('menu:close')
}

function toggleOb(): void {
  if (!spectating.value) {
    emitAction('ob:spectate')
  } else if (ui.ob) {
    emitAction('ob:race')
  } else {
    emitAction('ob:spectate')
  }
  emitAction('menu:close')
}

function devtools(): void {
  emitAction('devtools')
}

function setCursor(mode: 'auto' | 'always'): void {
  emitAction('cursor:set', { mode })
}

function openMapDetails(): void {
  if (!ui.room) return
  ui.mapDetails = ui.room.mapDetails || null
  ui.mapDetailsOpen = true
  emitAction('menu:close')
}

function openHelp(): void {
  emitAction('help:open')
  emitAction('menu:close')
}

function leaveStage(): void {
  emitAction('stage:leave')
  emitAction('menu:close')
}
</script>

<template>
  <div class="menu-backdrop">
    <section class="menu-panel">
      <header class="menu-panel__head">
        <div class="menu-panel__title-row">
          <span class="menu-panel__emblem"><IconSettings class="icon" /></span>
          <div>
            <p class="menu-panel__eyebrow">RST MTA LITE</p>
            <h1 class="menu-panel__title">菜单</h1>
          </div>
        </div>
        <button class="menu-close" type="button" aria-label="关闭菜单" @click="close">
          <IconX class="icon" />
        </button>
      </header>

      <dl class="menu-meta">
        <div>
          <dt><IconUser class="icon icon--sm" />玩家</dt>
          <dd>{{ ui.playerName }}</dd>
        </div>
        <div>
          <dt><IconFlag class="icon icon--sm" />舞台</dt>
          <dd>{{ ui.room?.name || '-' }}</dd>
        </div>
        <div>
          <dt><IconMap class="icon icon--sm" />赛道</dt>
          <dd>{{ ui.room?.mapName || '-' }}</dd>
        </div>
        <div>
          <dt><IconCar class="icon icon--sm" />模式</dt>
          <dd>{{ modeLabel }}</dd>
        </div>
      </dl>

      <div v-if="ui.room" class="menu-round">
        <span>本图剩余 <strong>{{ formatTime(ui.room.timeLeft) }}</strong></span>
        <span>{{ ui.room.players }} 玩家 / {{ ui.room.spectators }} 观战</span>
      </div>

      <div v-if="ui.mapPoolEmpty" class="menu-warning">
        地图池为空，无法发起换图投票。请联系管理员在 config.mapPool 添加地图。
      </div>

      <div class="menu-cursor">
        <span class="menu-cursor__label">
          <IconMousePointer2 class="icon icon--sm" />
          光标显示
        </span>
        <div class="menu-cursor__modes">
          <button
            type="button"
            :class="{ 'is-active': ui.cursorMode === 'auto' }"
            @click="setCursor('auto')"
          >
            自动
          </button>
          <button
            type="button"
            :class="{ 'is-active': ui.cursorMode === 'always' }"
            @click="setCursor('always')"
          >
            始终显示
          </button>
        </div>
        <small>
          {{ ui.cursorForced ? '当前界面强制显示光标' : '游戏内按 F3 临时切换' }}
        </small>
      </div>

      <div class="menu-actions">
        <button type="button" class="menu-action" :disabled="!ui.canStartVote" @click="startVote">
          <span class="menu-action__icon"><IconVote class="icon" /></span>
          <span class="menu-action__text">
            <strong>发起换图投票</strong>
            <small>{{ voteHint }}</small>
          </span>
          <IconChevronRight class="icon menu-action__arrow" />
        </button>

        <button
          type="button"
          class="menu-action"
          :disabled="!ui.canStartModeVote"
          @click="startModeVote"
        >
          <span class="menu-action__icon">
            <IconTrophy v-if="ui.gameMode === 'competitive'" class="icon" />
            <IconCar v-else class="icon" />
          </span>
          <span class="menu-action__text">
            <strong>切换比赛模式</strong>
            <small>{{ modeVoteHint }}</small>
          </span>
          <IconChevronRight class="icon menu-action__arrow" />
        </button>

        <button type="button" class="menu-action" @click="toggleOb">
          <span class="menu-action__icon">
            <IconEye v-if="spectating" class="icon" />
            <IconCar v-else class="icon" />
          </span>
          <span class="menu-action__text">
            <strong>{{ obLabel }}</strong>
            <small>{{ obHint }}</small>
          </span>
          <IconChevronRight class="icon menu-action__arrow" />
        </button>

        <button type="button" class="menu-action" @click="openMapDetails">
          <span class="menu-action__icon"><IconMapPinned class="icon" /></span>
          <span class="menu-action__text">
            <strong>地图详情</strong>
            <small>封面 / 作者 / 下载 / 链接</small>
          </span>
          <IconChevronRight class="icon menu-action__arrow" />
        </button>

        <button type="button" class="menu-action" @click="openHelp">
          <span class="menu-action__icon"><IconCircleQuestionMark class="icon" /></span>
          <span class="menu-action__text">
            <strong>操作帮助</strong>
            <small>查看全部快捷键</small>
          </span>
          <IconChevronRight class="icon menu-action__arrow" />
        </button>

        <button type="button" class="menu-action" @click="devtools">
          <span class="menu-action__icon"><IconCode class="icon" /></span>
          <span class="menu-action__text">
            <strong>打开 DevTools</strong>
            <small>CEF 调试</small>
          </span>
          <IconChevronRight class="icon menu-action__arrow" />
        </button>

        <button type="button" class="menu-action menu-action--ghost" @click="leaveStage">
          <span class="menu-action__icon"><IconDoorOpen class="icon" /></span>
          <span class="menu-action__text">
            <strong>离开舞台</strong>
            <small>回到舞台选择</small>
          </span>
          <IconChevronRight class="icon menu-action__arrow" />
        </button>
      </div>

      <p class="menu-foot">Esc 关闭菜单</p>
    </section>
  </div>
</template>

<style scoped>
.menu-backdrop {
  position: absolute;
  inset: 0;
  pointer-events: auto;
  display: flex;
  align-items: center;
  justify-content: center;
  background: radial-gradient(circle at 50% 28%, rgba(20, 40, 70, 0.45), rgba(3, 6, 11, 0.76));
  animation: menu-fade 0.16s ease-out;
}

.menu-panel {
  width: min(520px, calc(100vw - 96px));
  padding: 24px 26px 20px;
  border: 1px solid var(--rst-border);
  border-radius: 18px;
  background: linear-gradient(160deg, rgba(19, 31, 48, 0.95), rgba(7, 11, 19, 0.96));
  box-shadow: var(--rst-shadow);
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.menu-panel__head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}

.menu-panel__title-row {
  display: flex;
  align-items: center;
  gap: 12px;
}

.menu-panel__emblem {
  display: grid;
  place-items: center;
  width: 38px;
  height: 38px;
  border-radius: 11px;
  border: 1px solid rgba(88, 200, 255, 0.24);
  background: rgba(88, 200, 255, 0.1);
  color: var(--rst-accent);
}

.menu-panel__eyebrow {
  margin: 0 0 2px;
  font-size: 9px;
  letter-spacing: 0.2em;
  color: var(--rst-muted);
}

.menu-panel__title {
  margin: 0;
  font-size: 21px;
  font-weight: 600;
}

.menu-close {
  display: grid;
  place-items: center;
  width: 32px;
  height: 32px;
  border: 1px solid var(--rst-border);
  border-radius: 9px;
  color: var(--rst-muted);
  transition: color 0.15s ease, background 0.15s ease;
}

.menu-close:hover {
  color: var(--rst-text);
  background: rgba(255, 255, 255, 0.06);
}

.menu-meta {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 10px;
  margin: 0;
}

.menu-meta div {
  padding: 10px 12px;
  border-radius: 11px;
  background: rgba(255, 255, 255, 0.035);
  border: 1px solid rgba(255, 255, 255, 0.03);
}

.menu-meta dt {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 10px;
  letter-spacing: 0.06em;
  color: var(--rst-muted);
}

.menu-meta dd {
  margin: 5px 0 0;
  font-size: 12px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.menu-round {
  display: flex;
  flex-wrap: wrap;
  gap: 8px 16px;
  padding: 9px 12px;
  border-radius: 9px;
  background: rgba(88, 200, 255, 0.06);
  border: 1px solid rgba(88, 200, 255, 0.12);
  font-size: 11px;
  color: var(--rst-muted);
}

.menu-round strong {
  color: var(--rst-text);
  font-variant-numeric: tabular-nums;
}

.menu-cursor {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  padding: 9px 12px;
  border: 1px solid var(--rst-border);
  border-radius: 9px;
  background: rgba(255, 255, 255, 0.025);
}

.menu-cursor__label {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 11px;
  color: var(--rst-muted);
}

.menu-cursor__modes {
  display: flex;
  gap: 4px;
}

.menu-cursor__modes button {
  padding: 5px 8px;
  border: 1px solid var(--rst-border);
  border-radius: 6px;
  background: rgba(255, 255, 255, 0.03);
  color: var(--rst-muted);
  font-size: 10px;
}

.menu-cursor__modes button.is-active {
  border-color: rgba(88, 200, 255, 0.4);
  background: rgba(88, 200, 255, 0.1);
  color: var(--rst-text);
}

.menu-cursor small {
  margin-left: auto;
  font-size: 9px;
  color: var(--rst-muted);
}

.menu-warning {
  padding: 9px 12px;
  border: 1px solid rgba(255, 190, 92, 0.28);
  border-radius: 9px;
  background: rgba(255, 190, 92, 0.08);
  color: #ffd18a;
  font-size: 11px;
  line-height: 1.45;
}

.menu-actions {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.menu-action {
  display: flex;
  align-items: center;
  gap: 11px;
  padding: 11px 13px;
  border: 1px solid var(--rst-border);
  border-radius: 11px;
  background: rgba(255, 255, 255, 0.035);
  text-align: left;
  transition: background 0.15s ease, border-color 0.15s ease, transform 0.15s ease;
}

.menu-action:hover:not(:disabled) {
  transform: translateX(2px);
  background: rgba(88, 200, 255, 0.1);
  border-color: rgba(88, 200, 255, 0.38);
}

.menu-action:disabled {
  opacity: 0.45;
}

.menu-action__icon {
  display: grid;
  place-items: center;
  width: 30px;
  height: 30px;
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.05);
  color: var(--rst-accent);
}

.menu-action--ghost .menu-action__icon {
  color: var(--rst-muted);
}

.menu-action__text {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 1px;
}

.menu-action__text strong {
  font-size: 13px;
  font-weight: 500;
}

.menu-action__text small {
  font-size: 10px;
  color: var(--rst-muted);
}

.menu-action__arrow {
  color: var(--rst-muted);
  opacity: 0.5;
}

.menu-action:hover .menu-action__arrow {
  opacity: 1;
}

.menu-foot {
  margin: 0;
  text-align: center;
  font-size: 10px;
  color: var(--rst-muted);
}

@keyframes menu-fade {
  from {
    opacity: 0;
    transform: translateY(4px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
</style>
