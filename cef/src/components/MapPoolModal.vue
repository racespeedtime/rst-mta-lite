<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'

import IconEye from '~icons/lucide/eye'
import IconMap from '~icons/lucide/map'
import IconSearch from '~icons/lucide/search'
import IconVote from '~icons/lucide/vote'
import IconX from '~icons/lucide/x'
import { ElDatePicker, ElOption, ElPagination, ElSelect, ElTable, ElTableColumn } from 'element-plus'
import 'element-plus/es/components/table/style/css'
import 'element-plus/es/components/pagination/style/css'
import 'element-plus/es/components/date-picker/style/css'
import 'element-plus/es/components/select/style/css'
import { emitAction } from '@/mta/bridge'
import type { MapPoolItem, MapPoolPage, MapPoolSortField } from '@/mta/protocol'
import { ui } from '@/stores/ui'

const SEARCH_DEBOUNCE_MS = 220
const PAGE_SIZES = [10, 20, 30, 50, 100]

const search = ref(ui.mapPoolSearch)
const pageSize = ref(ui.mapPoolPageSize || 30)
const dateRange = ref<[string, string] | null>(
  ui.mapPoolDateFrom && ui.mapPoolDateTo ? [ui.mapPoolDateFrom, ui.mapPoolDateTo] : null,
)
let searchTimer = 0
let lastQuery = ui.mapPoolSearch.trim()

function applyDateRange(): void {
  request(1)
}

function daysAgo(days: number): [Date, Date] {
  const end = new Date()
  const start = new Date()
  start.setDate(start.getDate() - days + 1)
  return [start, end]
}

const DATE_SHORTCUTS = [
  { text: '最近 7 天', value: () => daysAgo(7) },
  { text: '最近 30 天', value: () => daysAgo(30) },
  { text: '最近 90 天', value: () => daysAgo(90) },
  { text: '最近 1 年', value: () => daysAgo(365) },
]

// 表头默认排序状态（重新打开弹窗时保持上次的选择）
const initialSort = {
  prop: ui.mapPoolSort,
  order: (ui.mapPoolOrder === 'asc' ? 'ascending' : 'descending') as 'ascending' | 'descending',
}

interface SortChangeEvent {
  prop?: string | null
  order?: string | null
}

function onSortChange(event: SortChangeEvent): void {
  const fields: Record<string, MapPoolSortField> = {
    name: 'name',
    downloads: 'downloads',
    plays: 'plays',
    uploaded: 'uploaded',
    popularity: 'popularity',
  }
  const field = event.prop ? fields[event.prop] : undefined

  if (!event.order || !field) {
    ui.mapPoolSort = 'popularity'
    ui.mapPoolOrder = 'desc'
  } else {
    ui.mapPoolSort = field
    ui.mapPoolOrder = event.order === 'ascending' ? 'asc' : 'desc'
  }
  request(1)
}

const canVote = computed(() => ui.canStartVote && !ui.vote && !!ui.room)

function request(page: number): void {
  const requestId = ui.mapPoolRequestId + 1
  ui.mapPoolRequestId = requestId
  ui.mapPoolLoading = true
  ui.mapPoolPage = page
  ui.mapPoolSearch = search.value.trim()
  ui.mapPoolPageSize = pageSize.value
  ui.mapPoolDateFrom = dateRange.value?.[0] || ''
  ui.mapPoolDateTo = dateRange.value?.[1] || ''
  emitAction('maps:page', {
    page,
    pageSize: pageSize.value,
    search: ui.mapPoolSearch,
    sort: ui.mapPoolSort,
    order: ui.mapPoolOrder,
    dateFrom: ui.mapPoolDateFrom,
    dateTo: ui.mapPoolDateTo,
    requestId,
  })
}

function applySearch(): void {
  const keyword = search.value.trim()
  if (keyword === lastQuery) return
  lastQuery = keyword
  request(1)
}

// 实时搜索：输入停顿 220ms 自动查，不需要按搜索按钮
watch(search, () => {
  window.clearTimeout(searchTimer)
  searchTimer = window.setTimeout(applySearch, SEARCH_DEBOUNCE_MS)
})

function submitSearch(): void {
  window.clearTimeout(searchTimer)
  applySearch()
}

function go(page: number): void {
  if (!ui.mapPool) return
  request(Math.max(1, Math.min(ui.mapPool.pages, page)))
}

function changePageSize(): void {
  request(1)
}

// el-table 的 row 类型是宽泛的 DefaultRow，这里收窄成地图条目
function openDetail(row: unknown): void {
  const map = row as MapPoolItem
  const requestId = ui.mapPoolDetailRequestId + 1
  ui.mapPoolDetailRequestId = requestId
  emitAction('maps:detail', { mapId: map.id, requestId })
}

function voteFor(row: unknown): void {
  if (!canVote.value) return
  emitAction('maps:vote', { mapId: (row as MapPoolItem).id })
}

function indexMethod(index: number): number {
  return ((ui.mapPool?.page || 1) - 1) * pageSize.value + index + 1
}

function rowClassName({ row }: any): string {
  return row && row.current ? 'is-current' : ''
}

function voteTitle(): string {
  if (ui.vote) return '当前已有投票'
  if (!ui.room) return '请先进入舞台'
  if (!ui.canStartVote) {
    return ui.voteCooldown > 0 ? `投票冷却中，还需 ${ui.voteCooldown} 秒` : '当前无法发起投票'
  }
  return '发起换图投票（这张图会作为候选并标注提名者）'
}

function close(): void {
  ui.mapPoolOpen = false
}

function formatPages(pool: MapPoolPage | null): string {
  if (!pool) return ''
  return `第 ${pool.page} / ${pool.pages} 页 · 共 ${pool.total} 张`
}

onMounted(() => {
  search.value = ui.mapPoolSearch
  lastQuery = ui.mapPoolSearch.trim()
  request(ui.mapPoolPage || 1)
})

onBeforeUnmount(() => {
  window.clearTimeout(searchTimer)
})
</script>

<template>
  <div class="map-pool">
    <section class="map-pool__panel">
      <header class="map-pool__head">
        <div class="map-pool__title">
          <IconMap class="icon" />
          <div>
            <span>地图池</span>
            <small>{{ formatPages(ui.mapPool) }}</small>
          </div>
        </div>
        <button type="button" class="map-pool__close" aria-label="关闭" @click="close">
          <IconX class="icon" />
        </button>
      </header>

      <form class="map-pool__search" @submit.prevent="submitSearch">
        <IconSearch class="icon icon--sm" />
        <input
          v-model="search"
          maxlength="80"
          autocomplete="off"
          placeholder="输入即搜索：地图名 / 作者 / id"
        />
        <span class="map-pool__search-hint">
          {{ ui.mapPoolLoading ? '搜索中…' : '实时搜索' }}
        </span>
      </form>

      <div class="map-pool__filters">
        <span class="map-pool__filters-label">上传日期</span>
        <ElDatePicker
          v-model="dateRange"
          class="map-pool__date-range"
          type="daterange"
          size="small"
          unlink-panels
          range-separator="→"
          start-placeholder="开始日期"
          end-placeholder="结束日期"
          value-format="YYYY-MM-DD"
          :shortcuts="DATE_SHORTCUTS"
          :teleported="false"
          placement="bottom-start"
          @change="applyDateRange"
        />
        <span class="map-pool__filters-hint">留空 = 不限</span>
      </div>

      <div class="map-pool__list" :class="{ 'is-loading': ui.mapPoolLoading }">
        <ElTable
          class="map-pool__table"
          :data="ui.mapPool?.items || []"
          size="small"
          row-key="id"
          :empty-text="ui.mapPoolLoading && !ui.mapPool ? '加载中…' : '没有匹配的地图'"
          :row-class-name="rowClassName"
          :default-sort="initialSort"
          @sort-change="onSortChange"
          @row-click="openDetail"
        >
          <ElTableColumn type="index" label="#" width="56" :index="indexMethod" />
          <ElTableColumn prop="name" label="地图" min-width="220" sortable="custom">
            <template #default="{ row }">
              <div class="map-pool__cell">
                <strong>
                  {{ row.name }}
                  <em v-if="row.current" class="map-pool__badge">当前</em>
                </strong>
                <small>{{ row.author }}</small>
              </div>
            </template>
          </ElTableColumn>
          <ElTableColumn label="ID" min-width="120" show-overflow-tooltip>
            <template #default="{ row }">
              <span class="map-pool__muted">{{ row.id }}</span>
            </template>
          </ElTableColumn>
          <ElTableColumn prop="uploaded" label="上传" width="96" sortable="custom">
            <template #default="{ row }">
              <span class="map-pool__muted">{{ row.uploadedAt || '—' }}</span>
            </template>
          </ElTableColumn>
          <ElTableColumn prop="downloads" label="下载" width="88" sortable="custom">
            <template #default="{ row }">
              <span class="map-pool__muted">{{ row.downloads || 0 }}</span>
            </template>
          </ElTableColumn>
          <ElTableColumn prop="popularity" label="热度" width="88" sortable="custom">
            <template #default="{ row }">
              <span class="map-pool__heat">{{ row.popularity || 0 }}</span>
            </template>
          </ElTableColumn>
          <ElTableColumn label="操作" width="150">
            <template #default="{ row }">
              <span class="map-pool__actions">
                <button
                  type="button"
                  class="map-pool__action"
                  :title="voteTitle()"
                  :disabled="!canVote"
                  @click.stop="voteFor(row)"
                >
                  <IconVote class="icon icon--sm" />
                  投票
                </button>
                <span class="map-pool__action map-pool__action--hint" aria-hidden="true">
                  <IconEye class="icon icon--sm" />
                  详情
                </span>
              </span>
            </template>
          </ElTableColumn>
        </ElTable>
      </div>

      <footer class="map-pool__foot">
        <ElPagination
          :current-page="ui.mapPool?.page || 1"
          :page-size="pageSize"
          :total="ui.mapPool?.total || 0"
          :disabled="ui.mapPoolLoading"
          size="small"
          background
          layout="prev, pager, next"
          @current-change="go"
        />
        <ElSelect
          v-model="pageSize"
          class="map-pool__page-size"
          size="small"
          :teleported="false"
          placement="top"
          :disabled="ui.mapPoolLoading"
          @change="changePageSize"
        >
          <ElOption v-for="size in PAGE_SIZES" :key="size" :label="`每页 ${size} 条`" :value="size" />
        </ElSelect>
      </footer>
    </section>
  </div>
</template>

<style scoped>
.map-pool {
  position: absolute;
  inset: 0;
  display: grid;
  place-items: center;
  padding: 26px;
  background: rgba(2, 6, 12, 0.74);
  pointer-events: auto;
  z-index: 40;
}

.map-pool__panel {
  display: flex;
  flex-direction: column;
  width: min(880px, calc(100vw - 52px));
  max-height: min(82vh, 780px);
  border: 1px solid var(--rst-border);
  border-radius: 18px;
  background: var(--rst-panel);
  box-shadow: var(--rst-shadow);
  overflow: hidden;
}

.map-pool__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 16px 18px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
}

.map-pool__title {
  display: flex;
  align-items: center;
  gap: 10px;
  color: var(--rst-text);
}

.map-pool__title > .icon {
  color: var(--rst-accent);
}

.map-pool__title span {
  display: block;
  font-size: 16px;
  font-weight: 700;
}

.map-pool__title small {
  display: block;
  margin-top: 2px;
  color: var(--rst-muted);
  font-size: 10px;
}

.map-pool__close {
  display: grid;
  place-items: center;
  width: 30px;
  height: 30px;
  border-radius: 8px;
  color: var(--rst-muted);
}

.map-pool__close:hover {
  color: var(--rst-text);
  background: rgba(255, 255, 255, 0.08);
}

.map-pool__search {
  display: flex;
  align-items: center;
  gap: 8px;
  margin: 12px 18px;
  padding: 8px 10px;
  border: 1px solid var(--rst-border);
  border-radius: 9px;
  background: rgba(0, 0, 0, 0.18);
  color: var(--rst-muted);
}

.map-pool__search input {
  flex: 1;
  min-width: 0;
  border: 0;
  outline: none;
  background: transparent;
  color: var(--rst-text);
  font: inherit;
  font-size: 12px;
}

.map-pool__search-hint {
  flex: 0 0 auto;
  color: var(--rst-muted);
  font-size: 9px;
  letter-spacing: 0.04em;
  opacity: 0.75;
}

.map-pool__filters {
  display: flex;
  align-items: center;
  gap: 6px;
  margin: -2px 18px 10px;
  color: var(--rst-muted);
  font-size: 10px;
}

.map-pool__filters-label {
  flex: 0 0 auto;
}

.map-pool__date-range {
  width: 236px;
}

.map-pool__date-range :deep(.el-range-input) {
  font-size: 10px;
}

.map-pool__page-size {
  width: 118px;
}

.map-pool__filters-hint {
  margin-left: auto;
  font-size: 9px;
  opacity: 0.6;
}

.map-pool__list {
  flex: 1;
  min-height: 180px;
  overflow-y: auto;
  padding: 0 18px;
  transition: opacity 0.12s ease;
}

.map-pool__list.is-loading {
  opacity: 0.72;
}

.map-pool__table {
  width: 100%;
  background: transparent;
}

.map-pool__table :deep(th.el-table__cell) {
  padding: 6px 0;
  font-size: 9px;
  font-weight: 500;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

.map-pool__table :deep(td.el-table__cell) {
  padding: 5px 0;
  cursor: pointer;
}

.map-pool__table :deep(.cell) {
  padding: 0 6px;
}

.map-pool__table :deep(.el-table__inner-wrapper::before) {
  background-color: transparent;
}

.map-pool__table :deep(.el-table__row.is-current) {
  box-shadow: inset 2px 0 0 rgba(126, 226, 168, 0.6);
}

.map-pool__cell {
  display: flex;
  flex-direction: column;
  gap: 1px;
  min-width: 0;
}

.map-pool__cell strong {
  display: flex;
  align-items: center;
  gap: 6px;
  overflow: hidden;
  color: var(--rst-text);
  font-size: 12px;
  font-weight: 600;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.map-pool__cell small,
.map-pool__muted {
  overflow: hidden;
  color: var(--rst-muted);
  font-size: 9px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.map-pool__badge {
  flex: 0 0 auto;
  padding: 1px 5px;
  border: 1px solid rgba(126, 226, 168, 0.4);
  border-radius: 999px;
  color: var(--rst-green);
  font-size: 8px;
  font-style: normal;
  font-weight: 500;
}

.map-pool__heat {
  color: var(--rst-accent);
  font-size: 9px;
  font-variant-numeric: tabular-nums;
}

.map-pool__actions {
  display: flex;
  align-items: center;
  gap: 6px;
}

.map-pool__action {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 5px 8px;
  border: 1px solid var(--rst-border);
  border-radius: 7px;
  color: var(--rst-muted);
  font-size: 10px;
  transition: color 0.15s ease, border-color 0.15s ease, background 0.15s ease;
}

.map-pool__action:hover:not(:disabled) {
  color: var(--rst-text);
  border-color: rgba(var(--rst-accent-rgb), 0.45);
  background: rgba(var(--rst-accent-rgb), 0.1);
}

.map-pool__action:disabled {
  opacity: 0.35;
}

.map-pool__action--hint {
  border-color: transparent;
  background: transparent;
  opacity: 0.55;
  pointer-events: none;
}

.map-pool__foot {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  padding: 10px 18px;
  border-top: 1px solid rgba(255, 255, 255, 0.06);
}

.map-pool__foot :deep(.el-pagination) {
  --el-pagination-font-size: 10px;
  --el-pagination-button-height: 24px;
  --el-pagination-button-width: 24px;
  color: var(--rst-muted);
}
</style>
