<script setup lang="ts">
import IconGitCommitHorizontal from '~icons/lucide/git-commit-horizontal'
import { buildInfo } from '@/build-info'

const title = `构建时间：${buildInfo.time}`
</script>

<template>
  <div class="build" :title="title">
    <IconGitCommitHorizontal class="icon icon--sm" />
    <span class="build__label">构建</span>
    <span class="build__date">{{ buildInfo.date }}</span>
    <span class="build__dot">·</span>
    <span class="build__hash">{{ buildInfo.hash }}</span>
  </div>
</template>

<style scoped>
.build {
  position: absolute;
  right: 24px;
  bottom: 18px;
  display: inline-flex;
  align-items: center;
  gap: 5px;
  height: 22px;
  padding: 0 8px;
  border: 1px solid rgba(140, 180, 255, 0.08);
  border-radius: 6px;
  background: rgba(6, 11, 19, 0.45);
  color: var(--rst-muted);
  font-size: 9px;
  letter-spacing: 0.08em;
  font-variant-numeric: tabular-nums;
  pointer-events: none;
  user-select: none;
}

.build .icon {
  color: var(--rst-muted);
}

.build__label {
  font-weight: 600;
  letter-spacing: 0.14em;
}

.build__hash {
  color: var(--rst-muted);
}

.build__dot {
  opacity: 0.5;
}
</style>
