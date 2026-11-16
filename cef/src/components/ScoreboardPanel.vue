<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'

import IconUsers from '~icons/lucide/users'
import { ElEmpty, ElTable, ElTableColumn, ElTag } from 'element-plus'
import 'element-plus/es/components/table/style/css'
import 'element-plus/es/components/tag/style/css'
import 'element-plus/es/components/empty/style/css'
import { onBridge } from '@/mta/bridge'
import type { ScoreboardPlayer } from '@/mta/protocol'
import { ui } from '@/stores/ui'

type TagType = 'primary' | 'success' | 'info' | 'warning' | 'danger'

const tableRef = ref<{ $el?: HTMLElement } | null>(null)
const maxHeight = ref(520)
let offScroll: (() => void) | undefined

const players = computed(() => ui.scoreboard?.players || [])
const count = computed(() => ui.scoreboard?.count ?? players.value.length)

function updateMaxHeight(): void {
  maxHeight.value = Math.max(180, Math.min(620, Math.floor(window.innerHeight * 0.66) - 44))
}

function onScroll(payload: { delta: number }): void {
  const root = tableRef.value?.$el
  const wrap =
    root?.querySelector<HTMLElement>('.el-scrollbar__wrap') ??
    root?.querySelector<HTMLElement>('.el-table__body-wrapper')
  if (!wrap) return
  wrap.scrollTop -= Math.sign(payload.delta) * 48
}

function statusType(key: string): TagType {
  if (key === 'alive') return 'success'
  if (key === 'dead' || key === 'out') return 'danger'
  if (key === 'spectate') return 'info'
  if (key === 'ready' || key === 'vote') return 'warning'
  if (key === 'finished') return 'primary'
  return 'info'
}

function rowClassName({ row }: { row: ScoreboardPlayer }): string {
  return row.me ? 'scoreboard__row--me' : ''
}

onMounted(() => {
  updateMaxHeight()
  window.addEventListener('resize', updateMaxHeight)
  offScroll = onBridge('scoreboardScroll', onScroll)
})

onUnmounted(() => {
  window.removeEventListener('resize', updateMaxHeight)
  offScroll?.()
})
</script>

<template>
  <aside class="scoreboard" aria-label="全服玩家列表">
    <header class="scoreboard__head">
      <span class="scoreboard__title">
        <IconUsers class="icon icon--sm" />
        全服玩家
      </span>
      <span class="scoreboard__meta">{{ count }} 人 · 按住 Tab 查看</span>
    </header>

    <ElTable
      ref="tableRef"
      class="scoreboard__table"
      :data="players"
      size="small"
      row-key="id"
      :max-height="maxHeight"
      :row-class-name="rowClassName"
    >
      <ElTableColumn prop="id" label="ID" width="64" />
      <ElTableColumn prop="name" label="昵称" min-width="200" show-overflow-tooltip>
        <template #default="{ row }">
          <span class="scoreboard__name">{{ row.name }}</span>
        </template>
      </ElTableColumn>
      <ElTableColumn label="状态" width="120">
        <template #default="{ row }">
          <ElTag :type="statusType(row.statusKey)" effect="light" size="small" round>
            {{ row.status }}
          </ElTag>
        </template>
      </ElTableColumn>
      <ElTableColumn label="FPS" width="82" align="right">
        <template #default="{ row }">
          <span class="scoreboard__num">{{ row.fps || '--' }}</span>
        </template>
      </ElTableColumn>
      <ElTableColumn label="Ping" width="100" align="right">
        <template #default="{ row }">
          <span class="scoreboard__num">{{ row.ping }} ms</span>
        </template>
      </ElTableColumn>

      <template #empty>
        <ElEmpty description="正在获取玩家列表…" :image-size="40" />
      </template>
    </ElTable>
  </aside>
</template>

<style scoped>
.scoreboard {
  position: absolute;
  top: 50%;
  left: 50%;
  width: min(720px, calc(100vw - 64px));
  max-height: min(66vh, 620px);
  transform: translate(-50%, -50%);
  border: 1px solid var(--rst-border);
  border-radius: 12px;
  background: rgba(8, 15, 25, 0.82);
  box-shadow: var(--rst-shadow);
  overflow: hidden;
  pointer-events: none;
  z-index: 35;
}

.scoreboard__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 16px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.07);
}

.scoreboard__title {
  display: flex;
  align-items: center;
  gap: 7px;
  color: var(--rst-text);
  font-size: 14px;
  font-weight: 700;
}

.scoreboard__title .icon {
  color: var(--rst-accent);
}

.scoreboard__meta {
  color: var(--rst-muted);
  font-size: 9px;
}

.scoreboard :deep(.el-table) {
  --el-table-bg-color: transparent;
  --el-table-tr-bg-color: transparent;
  --el-table-header-bg-color: rgba(8, 15, 25, 0.78);
  --el-table-row-hover-bg-color: rgba(var(--rst-accent-rgb), 0.06);
  --el-table-border-color: transparent;
  --el-table-header-text-color: var(--rst-muted);
  --el-table-text-color: var(--rst-muted);
  font-size: 11px;
}

.scoreboard :deep(.el-table__inner-wrapper::before) {
  display: none;
}

.scoreboard :deep(.el-table th.el-table__cell) {
  padding: 8px 10px;
  background: rgba(8, 15, 25, 0.78);
  color: var(--rst-muted);
  font-size: 9px;
  font-weight: 500;
  letter-spacing: 0.08em;
}

.scoreboard :deep(.el-table td.el-table__cell) {
  padding: 8px 10px;
  border-top: 1px solid rgba(255, 255, 255, 0.045);
  border-bottom: 0;
  color: var(--rst-muted);
  font-size: 11px;
}

.scoreboard :deep(.el-table .cell) {
  padding: 0;
  line-height: 1.4;
}

.scoreboard :deep(.el-table__row--me > td.el-table__cell) {
  background: rgba(var(--rst-accent-rgb), 0.1);
}

.scoreboard :deep(.el-tag) {
  height: 18px;
  padding: 0 6px;
  border: 0;
  font-size: 9px;
}

.scoreboard :deep(.el-empty) {
  padding: 24px 0;
}

.scoreboard :deep(.el-empty__description p) {
  margin: 0;
  color: var(--rst-muted);
  font-size: 11px;
}

.scoreboard :deep(.el-scrollbar__bar) {
  opacity: 0;
}

.scoreboard__name {
  overflow: hidden;
  color: var(--rst-text);
  text-overflow: ellipsis;
  white-space: nowrap;
}

.scoreboard__num {
  color: var(--rst-muted);
  font-variant-numeric: tabular-nums;
}
</style>
