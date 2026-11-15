<script setup lang="ts">
import IconInfo from '~icons/lucide/info'

interface ToastItem {
  id: number
  text: string
}

defineProps<{ items: ToastItem[] }>()
</script>

<template>
  <TransitionGroup name="toast-stack" tag="div" class="toast-stack">
    <div v-for="item in items" :key="item.id" class="toast">
      <IconInfo class="icon icon--sm" />
      <span>{{ item.text }}</span>
    </div>
  </TransitionGroup>
</template>

<style scoped>
.toast-stack {
  position: absolute;
  top: 112px;
  left: 50%;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  width: min(560px, calc(100vw - 48px));
  transform: translateX(-50%);
  pointer-events: none;
  z-index: 50;
}

.toast {
  display: flex;
  align-items: center;
  gap: 7px;
  max-width: 100%;
  padding: 9px 15px;
  border: 1px solid var(--rst-border);
  border-radius: 999px;
  background: var(--rst-panel);
  box-shadow: 0 12px 32px rgba(0, 0, 0, 0.28);
  color: var(--rst-text);
  font-size: 12px;
  line-height: 1.35;
  text-align: left;
  overflow-wrap: anywhere;
}

.toast .icon {
  color: var(--rst-accent);
}

.toast-stack-enter-active,
.toast-stack-leave-active {
  transition: opacity 0.22s ease, transform 0.22s ease;
}

.toast-stack-enter-from {
  opacity: 0;
  transform: translateY(-10px) scale(0.98);
}

.toast-stack-leave-to {
  opacity: 0;
  transform: translateY(-6px) scale(0.98);
}

.toast-stack-move {
  transition: transform 0.22s ease;
}

@media (prefers-reduced-motion: reduce) {
  .toast-stack-enter-active,
  .toast-stack-leave-active,
  .toast-stack-move {
    transition-duration: 0.01ms;
  }
}
</style>
