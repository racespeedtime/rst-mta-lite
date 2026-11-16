<script setup lang="ts">
import { onMounted, ref } from 'vue'

import IconTimer from '~icons/lucide/timer'
import IconTrophy from '~icons/lucide/trophy'
import IconX from '~icons/lucide/x'
import { ElOption, ElPagination, ElSelect, ElTable, ElTableColumn } from 'element-plus'
import 'element-plus/es/components/table/style/css'
import 'element-plus/es/components/pagination/style/css'
import 'element-plus/es/components/select/style/css'
import { emitAction } from '@/mta/bridge'
import type { MapRecordsPage } from '@/mta/protocol'
import { ui } from '@/stores/ui'
import { formatMs } from '@/utils/format'

const PAGE_SIZES = [10, 20, 50, 100]

const pageSize = ref(ui.recordsPageSize || 20)

function request(page: number): void {
  const requestId = ui.recordsRequestId + 1
  ui.recordsRequestId = requestId
  ui.recordsLoading = true
  ui.recordsPageSize = pageSize.value
  emitAction('records:page', {
    page,
    pageSize: pageSize.value,
    requestId,
  })
}

function go(page: number): void {
  if (!ui.records) return
  request(Math.max(1, Math.min(ui.records.pages, page)))
}

function changePageSize(): void {
  request(1)
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
        <ElTable
          class="records__table"
          :data="ui.records?.items || []"
          size="small"
          row-key="rank"
          :empty-text="ui.recordsLoading ? '加载中…' : '这张地图还没有完赛记录'"
        >
          <ElTableColumn prop="rank" label="#" width="56" />
          <ElTableColumn prop="name" label="玩家" min-width="160" show-overflow-tooltip />
          <ElTableColumn label="最佳成绩" width="150">
            <template #default="{ row }">
              <span class="records__time">
                <IconTimer class="icon icon--sm" />
                {{ formatMs(row.bestMs) }}
              </span>
            </template>
          </ElTableColumn>
          <ElTableColumn label="日期" width="120">
            <template #default="{ row }">{{ formatDate(row.updatedAt) }}</template>
          </ElTableColumn>
        </ElTable>
      </div>

      <footer class="records__foot">
        <ElPagination
          :current-page="ui.records?.page || 1"
          :page-size="pageSize"
          :total="ui.records?.total || 0"
          :disabled="ui.recordsLoading"
          size="small"
          background
          layout="prev, pager, next"
          @current-change="go"
        />
        <ElSelect
          v-model="pageSize"
          class="records__page-size"
          size="small"
          :teleported="false"
          placement="top"
          :disabled="ui.recordsLoading"
          @change="changePageSize"
        >
          <ElOption v-for="size in PAGE_SIZES" :key="size" :label="`每页 ${size} 条`" :value="size" />
        </ElSelect>
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
  background: rgba(2, 6, 12, 0.74);
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
  background: transparent;
}

.records__table :deep(th.el-table__cell) {
  padding: 6px 0;
  font-size: 9px;
  font-weight: 500;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

.records__table :deep(td.el-table__cell) {
  padding: 7px 0;
  font-size: 11px;
}

.records__table :deep(.cell) {
  padding: 0 6px;
}

.records__table :deep(.el-table__inner-wrapper::before) {
  background-color: transparent;
}

.records__table :deep(.el-table__empty-block) {
  min-height: 140px;
}

.records__time {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  color: var(--rst-text);
  font-variant-numeric: tabular-nums;
}

.records__foot {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  padding: 10px 18px;
  border-top: 1px solid rgba(255, 255, 255, 0.06);
}

.records__page-size {
  width: 118px;
}

.records__foot :deep(.el-pagination) {
  --el-pagination-font-size: 10px;
  --el-pagination-button-height: 24px;
  --el-pagination-button-width: 24px;
  color: var(--rst-muted);
}
</style>
