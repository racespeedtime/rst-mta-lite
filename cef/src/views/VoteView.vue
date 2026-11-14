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
import { emitAction } from '@/mta/bridge'
import { ui } from '@/stores/ui'
import { formatTime } from '@/utils/format'

type SortMode = 'name-asc' | 'name-desc' | 'popularity'

const query = ref('')
const sortMode = ref<SortMode>('popularity')

const options = computed(() => ui.vote?.options ?? [])
const totalVotes = computed(() => options.value.reduce((sum, option) => sum + option.votes, 0))

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

const votedName = computed(() => {
  const mine = ui.vote?.mine
  if (!mine) return ''
  return options.value.find((option) => option.id === mine)?.name || ''
})

function percent(votes: number): number {
  if (!totalVotes.value) return 0
  return Math.round((votes / totalVotes.value) * 100)
}

function vote(mapId: string): void {
  if (ui.vote?.mine) return
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
            <p class="vote__eyebrow">MAP VOTE</p>
            <h1 class="vote__title">换图投票</h1>
          </div>
        </div>
        <span class="vote__timer">
          <IconClock class="icon icon--sm" />
          {{ formatTime(ui.vote?.timeLeft || 0) }}
        </span>
      </header>

      <p class="vote__hint">从随机图池中选择下一张赛道，票数最多者胜出；平票按热度、再随机决定。</p>

      <div class="vote__toolbar">
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

        <span class="vote__count">{{ visibleOptions.length }} 张</span>
      </div>

      <div class="vote__options">
        <p v-if="visibleOptions.length === 0" class="vote__empty">没有匹配的地图</p>

        <button
          v-for="option in visibleOptions"
          :key="option.id"
          type="button"
          class="vote__option"
          :class="{ 'vote__option--mine': option.id === ui.vote?.mine }"
          :disabled="!!ui.vote?.mine"
          @click="vote(option.id)"
        >
          <span class="vote__fill" :style="{ width: `${percent(option.votes)}%` }" />
          <span class="vote__option-main">
            <span class="vote__option-name">{{ option.name }}</span>
            <span class="vote__option-meta">
              <span class="vote__option-author">
                <IconPenLine class="icon icon--sm" />
                作者 · {{ option.author }}
              </span>
              <span class="vote__option-popularity">
                <IconFlame class="icon icon--sm" />
                热度 {{ option.popularity }}
              </span>
            </span>
          </span>
          <span class="vote__option-right">
            <strong>{{ option.votes }}</strong>
            <IconCheck v-if="option.id === ui.vote?.mine" class="icon vote__check" />
          </span>
        </button>
      </div>

      <p v-if="votedName" class="vote__mine">
        <IconCheck class="icon icon--sm" />
        已投给：{{ votedName }}
      </p>
      <p v-else class="vote__mine vote__mine--wait">等待其他玩家投票…</p>
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
  color: rgba(147, 164, 189, 0.6);
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
  border-color: rgba(88, 200, 255, 0.38);
  background: rgba(88, 200, 255, 0.1);
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
  border-color: rgba(88, 200, 255, 0.4);
  background: rgba(88, 200, 255, 0.07);
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
  background: linear-gradient(90deg, rgba(88, 200, 255, 0.16), rgba(88, 200, 255, 0.02));
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
  color: rgba(255, 212, 121, 0.8);
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
</style>
