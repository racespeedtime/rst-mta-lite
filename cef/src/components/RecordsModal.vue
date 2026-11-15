<script setup lang="ts">
import { onMounted } from 'vue'

import IconChevronLeft from '~icons/lucide/chevron-left'
import IconChevronRight from '~icons/lucide/chevron-right'
import IconTimer from '~icons/lucide/timer'
import IconTrophy from '~icons/lucide/trophy'
import IconX from '~icons/lucide/x'
import { emitAction } from '@/mta/bridge'
import type { MapRecordsPage } from '@/mta/protocol'
import { ui } from '@/stores/ui'
import { formatMs } from '@/utils/format'

const PAGE_SIZE = 20

function request(page: number): void {
  const requestId = ui.recordsRequestId + 1
  ui.recordsRequestId = requestId
  ui.recordsLoading = true
  emitAction('records:page', {
    page,
    pageSize: PAGE_SIZE,
    requestId,
  })
}

function go(page: number): void {
  if (!ui.records) return
  request(Math.max(1, Math.min(ui.records.pages, page)))
}

function close(): void {
  ui.recordsOpen = false
}

function formatDate(timestamp?: number): string {
  if (!timestamp) return '—'
  const date = new Date(timestamp * 1000)
  if (Number.isNaN(date.getTime())) return '—'
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
}

function formatPages(pool: MapRecordsPage | null): string {
  if (!pool) return ''
  return `第 ${pool.page} / ${pool.pages} 页 · 共 ${pool.total} 条`
}

onMounted(() => request(1))
</script>

<template>
  <div class="records">
    <section class="records__panel">
      <header class="records__head">
        <div class="records__title">
          <IconTrophy class="icon" />
          <div>
            <span>赛道排行榜</span>
            <small v-if="ui.records">
              {{ ui.records.mapName }} · {{ ui.records.mapAuthor }} · {{ formatPages(ui.records) }}
            </small>
            <small v-else>当前地图历史最佳</small>
          </div>
        </div>
        <button type="button" class="records__close" aria-label="关闭" @click="close">
          <IconX class="icon" />
        </button>
      </header>

      <div class="records__table-wrap">
        <table class="records__table">
          <thead>
            <tr>
              <th class="records__rank">#</th>
              <th>玩家</th>
              <th>最佳成绩</th>
              <th class="records__date">日期</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="item in ui.records?.items || []" :key="item.rank">
              <td class="records__rank">{{ item.rank }}</td>
              <td class="records__name">{{ item.name }}</td>
              <td class="records__time">
                <IconTimer class="icon icon--sm" />
                {{ formatMs(item.bestMs) }}
              </td>
              <td class="records__date">{{ formatDate(item.updatedAt) }}</td>
            </tr>
          </tbody>
        </table>

        <p v-if="ui.recordsLoading" class="records__empty">加载中…</p>
        <p v-else-if="!ui.records?.items.length" class="records__empty">这张地图还没有完赛记录</p>
      </div>

      <footer class="records__foot">
        <button
          type="button"
          :disabled="!ui.records || ui.records.page <= 1"
          @click="go((ui.records?.page || 1) - 1)"
        >
          <IconChevronLeft class="icon icon--sm" />
          上一页
        </button>
        <span>{{ formatPages(ui.records) }}</span>
        <button
          type="button"
          :disabled="!ui.records || ui.records.page >= ui.records.pages"
          @click="go((ui.records?.page || 1) + 1)"
        >
          下一页
          <IconChevronRight class="icon icon--sm" />
        </button>
      </footer>
    </section>
  </div>
</template>

<style scoped>
.records {
  position: absolute;
  inset: 0;
  display: grid;
  place-items: center;
  padding: 26px;
  background: rgba(2, 6, 12, 0.62);
  backdrop-filter: blur(10px);
  pointer-events: auto;
  z-index: 40;
}

.records__panel {
  display: flex;
  flex-direction: column;
  width: min(720px, calc(100vw - 52px));
  max-height: min(82vh, 760px);
  border: 1px solid var(--rst-border);
  border-radius: 18px;
  background: var(--rst-panel);
  box-shadow: var(--rst-shadow);
  overflow: hidden;
}

.records__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 16px 18px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
}

.records__title {
  display: flex;
  align-items: center;
  gap: 10px;
  color: var(--rst-text);
}

.records__title > .icon {
  color: var(--rst-accent);
}

.records__title span {
  display: block;
  font-size: 16px;
  font-weight: 700;
}

.records__title small {
  display: block;
  margin-top: 2px;
  color: var(--rst-muted);
  font-size: 10px;
}

.records__close {
  display: grid;
  place-items: center;
  width: 30px;
  height: 30px;
  border-radius: 8px;
  color: var(--rst-muted);
}

.records__close:hover {
  color: var(--rst-text);
  background: rgba(255, 255, 255, 0.08);
}

.records__table-wrap {
  flex: 1;
  min-height: 180px;
  overflow-y: auto;
  padding: 4px 18px 8px;
}

.records__table {
  width: 100%;
  border-collapse: collapse;
  table-layout: fixed;
}

.records__table th {
  padding: 8px 6px;
  color: var(--rst-muted);
  font-size: 9px;
  font-weight: 500;
  text-align: left;
  text-transform: uppercase;
  letter-spacing: 0.08em;
}

.records__table td {
  padding: 10px 6px;
  border-top: 1px solid rgba(255, 255, 255, 0.045);
  color: var(--rst-muted);
  font-size: 11px;
}

.records__table tbody tr:hover {
  background: rgba(88, 200, 255, 0.05);
}

.records__rank {
  width: 40px;
  color: var(--rst-accent);
  font-variant-numeric: tabular-nums;
}

.records__name {
  overflow: hidden;
  color: var(--rst-text);
  text-overflow: ellipsis;
  white-space: nowrap;
}

.records__time {
  display: flex;
  align-items: center;
  gap: 4px;
  color: var(--rst-text);
  font-variant-numeric: tabular-nums;
}

.records__date {
  width: 110px;
  font-variant-numeric: tabular-nums;
}

.records__empty {
  padding: 32px 0;
  color: var(--rst-muted);
  font-size: 12px;
  text-align: center;
}

.records__foot {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 18px;
  border-top: 1px solid rgba(255, 255, 255, 0.06);
  color: var(--rst-muted);
  font-size: 10px;
}

.records__foot button {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 6px 9px;
  border: 1px solid var(--rst-border);
  border-radius: 7px;
  color: var(--rst-muted);
  font-size: 10px;
}

.records__foot button:hover:not(:disabled) {
  color: var(--rst-text);
  border-color: var(--rst-accent);
}

.records__foot button:disabled {
  opacity: 0.4;
}
</style>
