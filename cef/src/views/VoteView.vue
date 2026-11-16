<script setup lang="ts">
import { computed, ref } from 'vue'

import IconArrowDownAZ from '~icons/lucide/arrow-down-a-z'
import IconArrowUpAZ from '~icons/lucide/arrow-up-a-z'
import IconCheck from '~icons/lucide/check'
import IconClock from '~icons/lucide/clock'
import IconFlame from '~icons/lucide/flame'
import IconPenLine from '~icons/lucide/pen-line'
import IconSearch from '~icons/lucide/search'
import IconVote from '~icons/lucide/vote'
import IconX from '~icons/lucide/x'
import { emitAction } from '@/mta/bridge'
import { useTicker } from '@/composables/useTicker'
import { ui } from '@/stores/ui'
import { formatMs } from '@/utils/format'

type SortMode = 'name-asc' | 'name-desc' | 'popularity'

const query = ref('')
const sortMode = ref<SortMode>('popularity')
const now = useTicker()

const options = computed(() => ui.vote?.options ?? [])
const totalVotes = computed(() => options.value.reduce((sum, option) => sum + option.votes, 0))

const remainingMs = computed(() => {
  const base = ui.vote?.timeLeftMs ?? (ui.vote?.timeLeft ?? 0) * 1000
  const elapsed = ui.stateAt ? Math.max(0, now.value - ui.stateAt) : 0
  return Math.max(0, base - elapsed)
})

const visibleOptions = computed(() => {
  const keyword = query.value.trim().toLowerCase()
  const filtered = keyword
    ? options.value.filter(
        (option) =>
          option.name.toLowerCase().includes(keyword) ||
          option.author.toLowerCase().includes(keyword),
      )
    : [...options.value]

  return filtered.sort((a, b) => {
    if (sortMode.value === 'popularity') {
      return b.popularity - a.popularity || a.name.localeCompare(b.name, 'zh-CN')
    }
    const result = a.name.localeCompare(b.name, 'zh-CN')
    return sortMode.value === 'name-asc' ? result : -result
  })
})

const pinnedOption = computed(() => visibleOptions.value.find((option) => option.nominee) ?? null)

const orderedOptions = computed(() => {
  const pinned = pinnedOption.value
  if (!pinned) return visibleOptions.value
  return [pinned, ...visibleOptions.value.filter((option) => option.id !== pinned.id)]
})

const votedName = computed(() => {
  const mine = ui.vote?.mine
  if (!mine) return ''
  return options.value.find((option) => option.id === mine)?.name || ''
})

const forced = computed(() => ui.vote?.forced !== false)
const restartVote = computed(() => ui.vote?.restart === true)
const abstained = computed(() => ui.vote?.abstain || 0)
const mineAbstain = computed(() => ui.vote?.mine === '__abstain')

function close(): void {
  emitAction('voteui', { open: false })
}

function abstain(): void {
  emitAction('vote:abstain')
}

const nomineeName = computed(() => {
  const id = ui.vote?.nominee
  if (!id) return ''
  return options.value.find((option) => option.id === id)?.name || ''
})

function percent(votes: number): number {
  if (!totalVotes.value) return 0
  return Math.round((votes / totalVotes.value) * 100)
}

function vote(mapId: string): void {
  emitAction('vote:cast', { map: mapId })
}
</script>

<template>
  <div class="vote">
    <section class="vote__panel">
      <header class="vote__head">
        <div class="vote__title-row">
          <span class="vote__emblem"><IconVote class="icon icon--lg" /></span>
          <div>
            <p class="vote__eyebrow">{{ restartVote ? '重开投票' : '地图投票' }}</p>
            <h1 class="vote__title">{{ restartVote ? '重开当前地图' : '换图投票' }}</h1>
          </div>
        </div>
        <div class="vote__head-right">
          <span class="vote__timer">
            <IconClock class="icon icon--sm" />
            {{ formatMs(remainingMs) }}
          </span>
          <button v-if="!forced" type="button" class="vote__close" aria-label="关闭投票面板" @click="close">
            <IconX class="icon" />
          </button>
        </div>
      </header>

      <p class="vote__hint">
        <template v-if="restartVote">
          当前地图重新开局，发起人自动投赞成；超过一半参赛者同意才通过。投票期间当前比赛继续，未通过则继续本回合。
        </template>
        <template v-else-if="forced">
          从随机图池中选择下一张赛道，票数最多者胜出；平票按热度、再随机决定。
        </template>
        <template v-else>
          玩家自发的换图投票，不打断当前比赛；票数最多者胜出，结果立即生效（选中的就是当前地图时本回合继续）。发起人的提名自动计 1 票，投票可改（改投或弃权，以最后一次为准）。按 F4 可随时开关本面板。
        </template>
        <template v-if="nomineeName && !restartVote">
          · 本场由 {{ ui.vote?.nomineeBy || '玩家' }} 提名：{{ nomineeName }}（自动计 1 票）
        </template>
      </p>

      <div v-if="!forced && !restartVote" class="vote__toolbar">
        <label class="vote__search">
          <IconSearch class="icon icon--sm" />
          <input
            v-model="query"
            type="search"
            placeholder="搜索地图 / 作者"
            autocomplete="off"
          />
        </label>

        <div class="vote__sorts">
          <button
            type="button"
            :class="{ 'is-active': sortMode === 'name-asc' }"
            @click="sortMode = 'name-asc'"
          >
            <IconArrowUpAZ class="icon icon--sm" />
            名称 ↑
          </button>
          <button
            type="button"
            :class="{ 'is-active': sortMode === 'name-desc' }"
            @click="sortMode = 'name-desc'"
          >
            <IconArrowDownAZ class="icon icon--sm" />
            名称 ↓
          </button>
          <button
            type="button"
            :class="{ 'is-active': sortMode === 'popularity' }"
            @click="sortMode = 'popularity'"
          >
            <IconFlame class="icon icon--sm" />
            热度
          </button>
        </div>

        <span class="vote__count">{{ orderedOptions.length }} 张</span>
      </div>

      <div class="vote__options">
        <p v-if="orderedOptions.length === 0" class="vote__empty">没有匹配的地图</p>

        <template v-for="(option, index) in orderedOptions" :key="option.id">
          <div v-if="pinnedOption && index === 1" class="vote__divider">
            <span>系统随机推荐</span>
          </div>

          <button
            type="button"
            class="vote__option"
            :class="{ 'vote__option--mine': option.id === ui.vote?.mine, 'vote__option--nominee': option.nominee && !restartVote }"
            @click="vote(option.id)"
          >
          <span class="vote__fill" :style="{ width: `${percent(option.votes)}%` }" />
          <span class="vote__option-main">
            <span class="vote__option-name">
              {{ option.name }}
              <em v-if="option.nominee && !restartVote" class="vote__option-nominee">提名 +1</em>
            </span>
            <span v-if="!restartVote" class="vote__option-meta">
              <span class="vote__option-author">
                <IconPenLine class="icon icon--sm" />
                作者 · {{ option.author }}
              </span>
              <span class="vote__option-popularity">
                <IconFlame class="icon icon--sm" />
                热度 {{ option.popularity }}
                <span v-if="option.plays" class="vote__option-plays">· {{ option.plays }} 场</span>
              </span>
            </span>
          </span>
          <span class="vote__option-right">
            <strong>{{ option.votes }}</strong>
            <IconCheck v-if="option.id === ui.vote?.mine" class="icon vote__check" />
          </span>
          </button>
        </template>
      </div>

      <div class="vote__foot">
        <button type="button" class="vote__abstain" @click="abstain">
          {{ restartVote ? '反对 / 不参与重开' : '弃权（交给系统按热度裁决）' }}
        </button>
        <span v-if="abstained" class="vote__abstain-count">{{ abstained }} 人已弃权</span>
      </div>

      <p v-if="mineAbstain" class="vote__mine vote__mine--abstain">
        {{ restartVote ? '已反对 / 不参与（点选项可改投赞成）' : '已弃权：结果按票数、再按热度裁决（点其它地图可改票）' }}
      </p>
      <p v-else-if="votedName" class="vote__mine">
        <IconCheck class="icon icon--sm" />
        {{ restartVote ? '已赞成重开' : `已投给：${votedName}` }}（点选项可改票）
      </p>
      <p v-else class="vote__mine vote__mine--wait">等待其他玩家投票…（也可以弃权）</p>
    </section>
  </div>
</template>

<style scoped>
.vote {
  position: absolute;
  inset: 0;
  pointer-events: auto;
  display: flex;
  align-items: center;
  justify-content: center;
  background: radial-gradient(circle at 50% 35%, rgba(26, 46, 74, 0.4), rgba(3, 6, 11, 0.7));
}

.vote__panel {
  width: min(560px, calc(100vw - 96px));
  padding: 24px 26px 20px;
  border: 1px solid var(--rst-border);
  border-radius: 18px;
  background: linear-gradient(160deg, rgba(19, 31, 48, 0.95), rgba(7, 11, 19, 0.96));
  box-shadow: var(--rst-shadow);
}

.vote__head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}

.vote__title-row {
  display: flex;
  align-items: center;
  gap: 12px;
}

.vote__emblem {
  display: grid;
  place-items: center;
  width: 40px;
  height: 40px;
  border-radius: 12px;
  border: 1px solid rgba(255, 212, 121, 0.28);
  background: rgba(255, 212, 121, 0.1);
  color: var(--rst-gold);
}

.vote__eyebrow {
  margin: 0 0 2px;
  font-size: 9px;
  letter-spacing: 0.2em;
  color: var(--rst-muted);
}

.vote__title {
  margin: 0;
  font-size: 21px;
  font-weight: 600;
}

.vote__timer {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 5px 9px;
  border: 1px solid rgba(255, 212, 121, 0.28);
  border-radius: 8px;
  font-size: 15px;
  font-variant-numeric: tabular-nums;
  color: var(--rst-gold);
}

.vote__hint {
  margin: 14px 0 10px;
  font-size: 11px;
  color: var(--rst-muted);
}

.vote__toolbar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  margin-bottom: 10px;
}

.vote__search {
  flex: 1 1 180px;
  display: flex;
  align-items: center;
  gap: 6px;
  min-width: 0;
  padding: 7px 10px;
  border: 1px solid var(--rst-border);
  border-radius: 9px;
  background: rgba(4, 8, 14, 0.6);
  color: var(--rst-muted);
}

.vote__search input {
  flex: 1;
  min-width: 0;
  border: 0;
  background: transparent;
  color: var(--rst-text);
  font: inherit;
  font-size: 11px;
  outline: none;
}

.vote__search input::placeholder {
  color: var(--rst-muted);
}

.vote__sorts {
  display: flex;
  align-items: center;
  gap: 4px;
}

.vote__sorts button {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 6px 8px;
  border: 1px solid var(--rst-border);
  border-radius: 7px;
  background: rgba(255, 255, 255, 0.03);
  color: var(--rst-muted);
  font-size: 10px;
  transition: color 0.15s ease, border-color 0.15s ease, background 0.15s ease;
}

.vote__sorts button:hover,
.vote__sorts button.is-active {
  color: var(--rst-text);
  border-color: rgba(var(--rst-accent-rgb), 0.38);
  background: rgba(var(--rst-accent-rgb), 0.1);
}

.vote__count {
  margin-left: auto;
  font-size: 9px;
  letter-spacing: 0.08em;
  color: var(--rst-muted);
}

.vote__options {
  display: flex;
  flex-direction: column;
  gap: 8px;
  max-height: 300px;
  overflow-y: auto;
  padding-right: 2px;
}

.vote__options::-webkit-scrollbar {
  width: 4px;
}

.vote__options::-webkit-scrollbar-thumb {
  border-radius: 2px;
  background: rgba(140, 180, 255, 0.22);
}

.vote__empty {
  margin: 6px 0;
  font-size: 11px;
  color: var(--rst-muted);
  text-align: center;
}

.vote__option {
  position: relative;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 14px;
  border: 1px solid var(--rst-border);
  border-radius: 11px;
  background: rgba(255, 255, 255, 0.035);
  text-align: left;
  overflow: hidden;
  transition: border-color 0.15s ease, background 0.15s ease;
}

.vote__option:hover:not(:disabled) {
  border-color: rgba(var(--rst-accent-rgb), 0.4);
  background: rgba(var(--rst-accent-rgb), 0.07);
}

.vote__option--mine {
  border-color: rgba(126, 226, 168, 0.45);
  background: rgba(126, 226, 168, 0.07);
}

.vote__option:disabled {
  opacity: 0.85;
}

.vote__fill {
  position: absolute;
  inset: 0 auto 0 0;
  width: 0;
  background: linear-gradient(90deg, rgba(var(--rst-accent-rgb), 0.16), rgba(var(--rst-accent-rgb), 0.02));
  transition: width 0.3s ease;
}

.vote__option--mine .vote__fill {
  background: linear-gradient(90deg, rgba(126, 226, 168, 0.2), rgba(126, 226, 168, 0.03));
}

.vote__option-main {
  position: relative;
  z-index: 1;
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 3px;
}

.vote__option-name {
  font-size: 13px;
}

.vote__option-nominee {
  margin-left: 6px;
  padding: 1px 5px;
  border: 1px solid rgba(255, 212, 121, 0.4);
  border-radius: 999px;
  color: var(--rst-gold);
  font-size: 8px;
  font-style: normal;
  font-weight: 500;
  vertical-align: middle;
}

.vote__option--nominee {
  border-color: rgba(255, 212, 121, 0.34);
}

.vote__divider {
  display: flex;
  align-items: center;
  gap: 8px;
  margin: 6px 2px 2px;
  color: var(--rst-muted);
  font-size: 9px;
  letter-spacing: 0.1em;
}

.vote__divider::before,
.vote__divider::after {
  content: '';
  flex: 1;
  height: 1px;
  background: var(--rst-border);
}

.vote__option-meta {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 4px 10px;
}

.vote__option-author,
.vote__option-popularity {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 10px;
  color: var(--rst-muted);
}

.vote__option-popularity {
  color: var(--rst-gold);
}

.vote__option-plays {
  color: var(--rst-muted);
}

.vote__option-right {
  position: relative;
  z-index: 1;
  display: flex;
  align-items: center;
  gap: 6px;
}

.vote__option-right strong {
  min-width: 22px;
  text-align: right;
  font-size: 15px;
  font-variant-numeric: tabular-nums;
  color: var(--rst-accent);
}

.vote__check {
  color: var(--rst-green);
}

.vote__mine {
  display: flex;
  align-items: center;
  gap: 5px;
  margin: 14px 0 0;
  font-size: 11px;
  color: var(--rst-green);
}

.vote__mine--wait {
  color: var(--rst-muted);
}
.vote__head-right {
  display: flex;
  align-items: center;
  gap: 8px;
}

.vote__close {
  display: grid;
  place-items: center;
  width: 30px;
  height: 30px;
  border: 1px solid var(--rst-border);
  border-radius: 8px;
  color: var(--rst-muted);
  background: rgba(255, 255, 255, 0.03);
}

.vote__close:hover {
  color: var(--rst-text);
}

.vote__foot {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  margin-top: 14px;
}

.vote__abstain {
  padding: 6px 10px;
  border: 1px solid var(--rst-border);
  border-radius: 8px;
  color: var(--rst-muted);
  font-size: 10px;
}

.vote__abstain:hover:not(:disabled) {
  color: var(--rst-text);
  border-color: rgba(var(--rst-accent-rgb), 0.45);
}

.vote__abstain:disabled {
  opacity: 0.4;
}

.vote__abstain-count {
  color: var(--rst-gold);
  font-size: 10px;
}

.vote__mine--abstain {
  color: var(--rst-gold);
}
</style>
