<script setup lang="ts">
import { computed, ref } from 'vue'

import IconChevronRight from '~icons/lucide/chevron-right'
import IconCar from '~icons/lucide/car'
import IconCircleQuestionMark from '~icons/lucide/circle-question-mark'
import IconCode from '~icons/lucide/code'
import IconEye from '~icons/lucide/eye'
import IconEyeOff from '~icons/lucide/eye-off'
import IconFlag from '~icons/lucide/flag'
import IconMap from '~icons/lucide/map'
import IconMapPinned from '~icons/lucide/map-pinned'
import IconMousePointer2 from '~icons/lucide/mouse-pointer-2'
import IconPalette from '~icons/lucide/palette'
import IconRotateCcw from '~icons/lucide/rotate-ccw'
import IconSettings from '~icons/lucide/settings'
import IconTrash2 from '~icons/lucide/trash-2'
import IconTrophy from '~icons/lucide/trophy'
import IconUser from '~icons/lucide/user'
import IconVote from '~icons/lucide/vote'
import IconX from '~icons/lucide/x'
import { emitAction } from '@/mta/bridge'
import { useTicker } from '@/composables/useTicker'
import { ui } from '@/stores/ui'
import { applyTheme, saveThemeSettings, type ThemeMode } from '@/theme'
import { formatMs, formatTime } from '@/utils/format'

const now = useTicker()
const activeTab = ref<'play' | 'training' | 'view' | 'system'>('play')

const THEME_MODES: { value: ThemeMode; label: string }[] = [
  { value: 'dark', label: '深色' },
  { value: 'light', label: '浅色' },
  { value: 'system', label: '跟随系统' },
]
const ACCENT_PRESETS = ['#58c8ff', '#8b7cff', '#7ee2a8', '#ffd479', '#ff8fab', '#ff8a5c', '#5eead4', '#f472b6']
const MENU_LEAVE_DELAY_MS = 190
const roomRemainingMs = computed(() => {
  const base = ui.room?.timeLeftMs ?? (ui.room?.timeLeft ?? 0) * 1000
  const elapsed = ui.stateAt ? Math.max(0, now.value - ui.stateAt) : 0
  return Math.max(0, base - elapsed)
})

const voteHint = computed(() => {
  if (ui.mapPoolEmpty) return '地图池为空'
  if (ui.vote?.active) return '投票进行中'
  if (ui.canStartVote) return '30 秒后结算'
  if (ui.voteCooldown > 0) return `冷却中 ${formatTime(ui.voteCooldown)}`
  return '当前不可发起'
})

const modeLabel = computed(() => {
  if (ui.gameMode !== 'competitive') return '训练模式'
  return ui.competitiveMode === 'team' ? '团队竞技' : '个人竞技'
})
const spectating = computed(() => ui.mode === 'spectating')

const obLabel = computed(() => {
  if (ui.gameMode === 'training') {
    return spectating.value ? '立即重生' : '切换观战'
  }
  if (!spectating.value) return '切换纯观战'
  return ui.ob ? '下回合参赛' : '保持纯观战'
})

const obHint = computed(() => {
  if (ui.gameMode === 'training') {
    return spectating.value ? '返回当前训练赛道' : '进入观战，可随时重生'
  }
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
  if (ui.gameMode === 'training' && spectating.value) {
    emitAction('respawn')
  } else if (!spectating.value) {
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

function toggleHud(): void {
  ui.hudHidden = !ui.hudHidden
  emitAction('visibility:master', { visible: !ui.hudHidden })
}

type VisibilityKey = 'hud' | 'chat' | 'radar' | 'crosshair' | 'nametags'

function saveVisibility(): void {
  window.localStorage.setItem(
    'rst.visibility',
    JSON.stringify({
      hud: ui.showHud,
      chat: ui.showChat,
      radar: ui.showRadar,
      crosshair: ui.showCrosshair,
      nametags: ui.nametagsVisible,
    }),
  )
}

function setVisibility(key: VisibilityKey, visible: boolean): void {
  if (key === 'hud') ui.showHud = visible
  else if (key === 'chat') ui.showChat = visible
  else if (key === 'radar') ui.showRadar = visible
  else if (key === 'crosshair') ui.showCrosshair = visible
  else ui.nametagsVisible = visible

  saveVisibility()
  emitAction('visibility:set', { key, visible })
}

function persistTheme(): void {
  const theme = { mode: ui.themeMode, accent: ui.accentColor }
  saveThemeSettings(theme)
  applyTheme(theme)
}

function setThemeMode(mode: ThemeMode): void {
  ui.themeMode = mode
  persistTheme()
}

function setAccentColor(color: string): void {
  if (!/^#[0-9a-f]{6}$/i.test(color)) return
  ui.accentColor = color.toLowerCase()
  persistTheme()
}

function onAccentInput(event: Event): void {
  setAccentColor((event.target as HTMLInputElement).value)
}

function setCursor(mode: 'auto' | 'always'): void {
  emitAction('cursor:set', { mode })
}

function saveWarp(): void {
  emitAction('warp:save')
}

function goWarp(id: number): void {
  emitAction('menu:close')
  emitAction('warp:go', { id })
}

function goLatestWarp(): void {
  emitAction('menu:close')
  emitAction('warp:latest')
}

function deleteWarp(id: number): void {
  emitAction('warp:delete', { id })
}

function warpTime(at: number): string {
  if (!at) return ''
  return new Date(at * 1000).toLocaleTimeString('zh-CN', { hour12: false })
}

function warpPosition(x: number, y: number, z: number): string {
  return `${Math.round(x)}, ${Math.round(y)}, ${Math.round(z)}`
}

function openMapPool(): void {
  emitAction('menu:close')
  window.setTimeout(() => {
    ui.mapPoolOpen = true
  }, MENU_LEAVE_DELAY_MS)
}

function openRecords(): void {
  emitAction('menu:close')
  window.setTimeout(() => {
    ui.recordsOpen = true
  }, MENU_LEAVE_DELAY_MS)
}

function openMapDetails(): void {
  if (!ui.room) return
  const details = ui.room.mapDetails || null
  emitAction('menu:close')
  window.setTimeout(() => {
    ui.mapDetails = details
    ui.mapDetailsOpen = true
  }, MENU_LEAVE_DELAY_MS)
}

function openHelp(): void {
  emitAction('help:open')
  emitAction('menu:close')
}

function respawn(): void {
  emitAction('respawn')
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
          <dt><IconFlag class="icon icon--sm" />服务器</dt>
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
        <span>本图剩余 <strong>{{ formatMs(roomRemainingMs) }}</strong></span>
        <span>{{ ui.room.players }} 玩家 / {{ ui.room.spectators }} 观战</span>
      </div>

      <div v-if="ui.mapPoolEmpty" class="menu-warning">
        地图池为空，无法发起换图投票。请联系管理员在 config.mapPool 添加地图。
      </div>

      <nav class="menu-tabs" role="tablist" aria-label="菜单分类">
        <button
          type="button"
          role="tab"
          :aria-selected="activeTab === 'play'"
          :class="{ 'is-active': activeTab === 'play' }"
          @click="activeTab = 'play'"
        >
          玩法
        </button>
        <button
          type="button"
          role="tab"
          :aria-selected="activeTab === 'training'"
          :class="{ 'is-active': activeTab === 'training' }"
          @click="activeTab = 'training'"
        >
          训练
        </button>
        <button
          type="button"
          role="tab"
          :aria-selected="activeTab === 'view'"
          :class="{ 'is-active': activeTab === 'view' }"
          @click="activeTab = 'view'"
        >
          界面
        </button>
        <button
          type="button"
          role="tab"
          :aria-selected="activeTab === 'system'"
          :class="{ 'is-active': activeTab === 'system' }"
          @click="activeTab = 'system'"
        >
          系统
        </button>
      </nav>

      <div v-if="activeTab === 'play'" class="menu-actions">
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

        <button
          v-if="ui.gameMode === 'training'"
          type="button"
          class="menu-action"
          @click="respawn"
        >
          <span class="menu-action__icon"><IconRotateCcw class="icon" /></span>
          <span class="menu-action__text">
            <strong>{{ spectating ? '立即重生' : '重生' }}</strong>
            <small>{{ spectating ? '回到当前训练赛道' : '回到随机出生点，重新 3 秒倒计时' }}</small>
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

        <button type="button" class="menu-action" @click="openMapPool">
          <span class="menu-action__icon"><IconMap class="icon" /></span>
          <span class="menu-action__text">
            <strong>地图池</strong>
            <small>浏览全部地图</small>
          </span>
          <IconChevronRight class="icon menu-action__arrow" />
        </button>

        <button type="button" class="menu-action" @click="openRecords">
          <span class="menu-action__icon"><IconTrophy class="icon" /></span>
          <span class="menu-action__text">
            <strong>赛道排行榜</strong>
            <small>当前地图历史最佳成绩</small>
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
      </div>

      <div v-else-if="activeTab === 'training'" class="menu-actions">
        <p class="warp-hint">
          短按左 <kbd>Alt</kbd> 保存当前位置；长按左 <kbd>Alt</kbd> 到阈值立即回到最近一个点，不需要等松开。
          传送后冻结 0.5 秒，且不能与倒带同时进行。换图、换房间或切换模式会清空传送点。
        </p>

        <template v-if="ui.gameMode === 'training'">
          <button type="button" class="menu-action" @click="saveWarp">
            <span class="menu-action__icon"><IconMapPinned class="icon" /></span>
            <span class="menu-action__text">
              <strong>保存当前位置</strong>
              <small>也可以短按左 Alt</small>
            </span>
            <IconChevronRight class="icon menu-action__arrow" />
          </button>

          <button
            type="button"
            class="menu-action"
            :disabled="!ui.warps.length"
            @click="goLatestWarp"
          >
            <span class="menu-action__icon"><IconRotateCcw class="icon" /></span>
            <span class="menu-action__text">
              <strong>回到最近传送点</strong>
              <small>{{ ui.warps.length ? `#${ui.warps[0]?.id} · ${warpTime(ui.warps[0]?.at || 0)}` : '还没有保存' }}</small>
            </span>
            <IconChevronRight class="icon menu-action__arrow" />
          </button>

          <div v-if="ui.warps.length" class="warp-list">
            <div v-for="warp in ui.warps" :key="warp.id" class="warp-row">
              <div class="warp-row__main">
                <strong>#{{ warp.id }}<span v-if="warp.id === ui.warps[0]?.id"> 最近</span></strong>
                <small>
                  {{ warpTime(warp.at) }} · {{ warp.vehicle ? `车辆 ${warp.vehicle}` : '步行' }} ·
                  {{ warpPosition(warp.x, warp.y, warp.z) }}
                </small>
              </div>
              <button type="button" class="warp-row__button" @click="goWarp(warp.id)">回到</button>
              <button type="button" class="warp-row__button warp-row__button--danger" @click="deleteWarp(warp.id)">
                <IconTrash2 class="icon icon--sm" />
                删除
              </button>
            </div>
          </div>
          <p v-else class="warp-empty">还没有保存传送点，按左 Alt 保存第一个。</p>
        </template>
        <p v-else class="warp-empty">传送点仅在训练模式可用。</p>
      </div>

      <div v-else-if="activeTab === 'view'" class="menu-actions">
        <button type="button" class="menu-action menu-action--switch" @click="toggleHud">
          <span class="menu-action__icon">
            <IconEyeOff v-if="!ui.hudHidden" class="icon" />
            <IconEye v-else class="icon" />
          </span>
          <span class="menu-action__text">
            <strong>全部 GUI</strong>
            <small>{{ ui.hudHidden ? '当前已隐藏，点击恢复' : '一键显示 / 隐藏' }}</small>
          </span>
          <span class="menu-switch" :class="{ 'is-on': !ui.hudHidden }" aria-hidden="true" />
        </button>

        <button
          type="button"
          class="menu-action menu-action--switch"
          @click="setVisibility('hud', !ui.showHud)"
        >
          <span class="menu-action__icon"><IconSettings class="icon" /></span>
          <span class="menu-action__text">
            <strong>HUD</strong>
            <small>计时 / 速度表 / 排行</small>
          </span>
          <span class="menu-switch" :class="{ 'is-on': ui.showHud }" aria-hidden="true" />
        </button>

        <button
          type="button"
          class="menu-action menu-action--switch"
          @click="setVisibility('chat', !ui.showChat)"
        >
          <span class="menu-action__icon"><IconCircleQuestionMark class="icon" /></span>
          <span class="menu-action__text">
            <strong>聊天记录</strong>
            <small>CEF 聊天面板</small>
          </span>
          <span class="menu-switch" :class="{ 'is-on': ui.showChat }" aria-hidden="true" />
        </button>

        <button
          type="button"
          class="menu-action menu-action--switch"
          @click="setVisibility('radar', !ui.showRadar)"
        >
          <span class="menu-action__icon"><IconMap class="icon" /></span>
          <span class="menu-action__text">
            <strong>小地图</strong>
            <small>原生雷达</small>
          </span>
          <span class="menu-switch" :class="{ 'is-on': ui.showRadar }" aria-hidden="true" />
        </button>

        <button
          type="button"
          class="menu-action menu-action--switch"
          @click="setVisibility('crosshair', !ui.showCrosshair)"
        >
          <span class="menu-action__icon"><IconMousePointer2 class="icon" /></span>
          <span class="menu-action__text">
            <strong>准星</strong>
            <small>原生瞄准准星</small>
          </span>
          <span class="menu-switch" :class="{ 'is-on': ui.showCrosshair }" aria-hidden="true" />
        </button>

        <button
          type="button"
          class="menu-action menu-action--switch"
          @click="setVisibility('nametags', !ui.nametagsVisible)"
        >
          <span class="menu-action__icon">
            <IconEye v-if="ui.nametagsVisible" class="icon" />
            <IconEyeOff v-else class="icon" />
          </span>
          <span class="menu-action__text">
            <strong>玩家名字牌</strong>
            <small>仅影响自己看到的</small>
          </span>
          <span class="menu-switch" :class="{ 'is-on': ui.nametagsVisible }" aria-hidden="true" />
        </button>

        <div class="theme-settings">
          <div class="theme-settings__head">
            <span><IconPalette class="icon icon--sm" />主题</span>
            <small>本机保存</small>
          </div>
          <div class="theme-modes">
            <button
              v-for="mode in THEME_MODES"
              :key="mode.value"
              type="button"
              :class="{ 'is-active': ui.themeMode === mode.value }"
              @click="setThemeMode(mode.value)"
            >
              {{ mode.label }}
            </button>
          </div>
          <div class="accent-row">
            <button
              v-for="color in ACCENT_PRESETS"
              :key="color"
              type="button"
              class="accent-dot"
              :class="{ 'is-active': ui.accentColor === color }"
              :style="{ background: color }"
              :aria-label="`主题色 ${color}`"
              @click="setAccentColor(color)"
            />
            <label class="accent-custom">
              自定义
              <input type="color" :value="ui.accentColor" @input="onAccentInput" />
            </label>
          </div>
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
      </div>

      <div v-else class="menu-actions">
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
}

.menu-enter-active,
.menu-leave-active {
  transition: opacity 0.18s ease;
}

.menu-enter-active .menu-panel,
.menu-leave-active .menu-panel {
  transition: opacity 0.18s ease, transform 0.18s ease;
}

.menu-enter-from,
.menu-leave-to {
  opacity: 0;
}

.menu-enter-from .menu-panel,
.menu-leave-to .menu-panel {
  opacity: 0;
  transform: translateY(8px) scale(0.98);
}

.menu-panel {
  width: min(520px, calc(100vw - 96px));
  max-height: min(90vh, 780px);
  padding: 24px 26px 20px;
  border: 1px solid var(--rst-border);
  border-radius: 18px;
  background: linear-gradient(160deg, rgba(19, 31, 48, 0.95), rgba(7, 11, 19, 0.96));
  box-shadow: var(--rst-shadow);
  display: flex;
  flex-direction: column;
  gap: 16px;
  overflow-y: auto;
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
  border: 1px solid rgba(var(--rst-accent-rgb), 0.24);
  background: rgba(var(--rst-accent-rgb), 0.1);
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
  background: rgba(var(--rst-accent-rgb), 0.06);
  border: 1px solid rgba(var(--rst-accent-rgb), 0.12);
  font-size: 11px;
  color: var(--rst-muted);
}

.menu-round strong {
  color: var(--rst-text);
  font-variant-numeric: tabular-nums;
}

.theme-settings {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 10px 12px;
  border: 1px solid var(--rst-border);
  border-radius: 9px;
  background: rgba(255, 255, 255, 0.025);
}

.theme-settings__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  color: var(--rst-text);
  font-size: 10px;
}

.theme-settings__head span {
  display: inline-flex;
  align-items: center;
  gap: 6px;
}

.theme-settings__head .icon {
  color: var(--rst-accent);
}

.theme-settings__head small {
  color: var(--rst-muted);
  font-size: 8px;
}

.theme-modes {
  display: flex;
  gap: 4px;
}

.theme-modes button {
  flex: 1;
  padding: 5px 8px;
  border: 1px solid var(--rst-border);
  border-radius: 5px;
  color: var(--rst-muted);
  font-size: 9px;
}

.theme-modes button:hover {
  color: var(--rst-text);
  border-color: rgba(var(--rst-accent-rgb), 0.35);
}

.theme-modes button.is-active {
  color: var(--rst-accent);
  border-color: rgba(var(--rst-accent-rgb), 0.45);
  background: rgba(var(--rst-accent-rgb), 0.1);
}

.accent-row {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 6px;
}

.accent-dot {
  width: 18px;
  height: 18px;
  border: 2px solid transparent;
  border-radius: 50%;
  box-shadow: 0 0 0 1px rgba(255, 255, 255, 0.16);
}

.accent-dot.is-active {
  border-color: var(--rst-text);
  box-shadow: 0 0 0 2px rgba(var(--rst-accent-rgb), 0.35);
}

.accent-custom {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  margin-left: auto;
  color: var(--rst-muted);
  font-size: 8px;
  cursor: pointer;
}

.accent-custom input {
  width: 24px;
  height: 18px;
  padding: 0;
  border: 1px solid var(--rst-border);
  border-radius: 4px;
  background: transparent;
  cursor: pointer;
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
  border-color: rgba(var(--rst-accent-rgb), 0.4);
  background: rgba(var(--rst-accent-rgb), 0.1);
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
  color: var(--rst-gold);
  font-size: 11px;
  line-height: 1.45;
}

.menu-actions {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.warp-hint {
  margin: 0 0 2px;
  padding: 9px 11px;
  border: 1px solid rgba(var(--rst-accent-rgb), 0.16);
  border-radius: 8px;
  background: rgba(var(--rst-accent-rgb), 0.05);
  color: var(--rst-muted);
  font-size: 10px;
  line-height: 1.55;
}

.warp-hint kbd {
  padding: 1px 4px;
  border: 1px solid rgba(255, 255, 255, 0.16);
  border-radius: 3px;
  background: rgba(255, 255, 255, 0.06);
  color: var(--rst-text);
  font-family: inherit;
  font-size: 9px;
}

.warp-list {
  display: flex;
  flex-direction: column;
  gap: 5px;
  margin-top: 2px;
}

.warp-row {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 8px 9px;
  border: 1px solid var(--rst-border);
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.025);
}

.warp-row__main {
  flex: 1;
  min-width: 0;
}

.warp-row__main strong {
  display: block;
  color: var(--rst-text);
  font-size: 10px;
  font-weight: 600;
}

.warp-row__main strong span {
  margin-left: 5px;
  color: var(--rst-accent);
  font-size: 8px;
  font-weight: 500;
}

.warp-row__main small {
  display: block;
  overflow: hidden;
  margin-top: 2px;
  color: var(--rst-muted);
  font-size: 8px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.warp-row__button {
  flex: 0 0 auto;
  padding: 4px 7px;
  border: 1px solid rgba(var(--rst-accent-rgb), 0.22);
  border-radius: 5px;
  background: rgba(var(--rst-accent-rgb), 0.08);
  color: var(--rst-accent);
  font-size: 8px;
}

.warp-row__button:hover {
  background: rgba(var(--rst-accent-rgb), 0.16);
}

.warp-row__button--danger {
  display: inline-flex;
  align-items: center;
  gap: 3px;
  border-color: rgba(255, 123, 114, 0.2);
  background: rgba(255, 123, 114, 0.06);
  color: var(--rst-red);
}

.warp-empty {
  margin: 0;
  padding: 12px 8px;
  color: var(--rst-muted);
  font-size: 10px;
  text-align: center;
}

.menu-tabs {
  display: flex;
  gap: 4px;
  padding: 3px;
  border: 1px solid var(--rst-border);
  border-radius: 9px;
  background: rgba(0, 0, 0, 0.16);
}

.menu-tabs button {
  flex: 1;
  padding: 7px 8px;
  border-radius: 6px;
  color: var(--rst-muted);
  font-size: 10px;
}

.menu-tabs button:hover {
  color: var(--rst-text);
  background: rgba(255, 255, 255, 0.05);
}

.menu-tabs button.is-active {
  color: var(--rst-text);
  background: rgba(var(--rst-accent-rgb), 0.14);
  box-shadow: inset 0 0 0 1px rgba(var(--rst-accent-rgb), 0.16);
}

.menu-action--switch {
  cursor: pointer;
}

.menu-switch {
  position: relative;
  flex: 0 0 auto;
  width: 34px;
  height: 18px;
  border: 1px solid rgba(255, 255, 255, 0.15);
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.08);
  transition: background 0.15s ease, border-color 0.15s ease;
}

.menu-switch::after {
  content: '';
  position: absolute;
  top: 2px;
  left: 2px;
  width: 12px;
  height: 12px;
  border-radius: 50%;
  background: var(--rst-muted);
  transition: transform 0.15s ease, background 0.15s ease;
}

.menu-switch.is-on {
  border-color: rgba(var(--rst-accent-rgb), 0.45);
  background: rgba(var(--rst-accent-rgb), 0.22);
}

.menu-switch.is-on::after {
  transform: translateX(16px);
  background: var(--rst-accent);
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
  background: rgba(var(--rst-accent-rgb), 0.1);
  border-color: rgba(var(--rst-accent-rgb), 0.38);
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
</style>
