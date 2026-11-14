<script setup lang="ts">
import IconInfo from '~icons/lucide/info'

defineProps<{ text: string }>()
</script>

<template>
  <transition name="toast">
    <div v-if="text" class="toast">
      <IconInfo class="icon icon--sm" />
      <span>{{ text }}</span>
    </div>
  </transition>
</template>

<style scoped>
.toast {
  position: absolute;
  left: 50%;
  top: 22px;
  transform: translateX(-50%);
  display: flex;
  align-items: center;
  gap: 7px;
  padding: 9px 15px;
  border: 1px solid var(--rst-border);
  border-radius: 999px;
  background: var(--rst-panel);
  box-shadow: 0 12px 32px rgba(0, 0, 0, 0.4);
  font-size: 12px;
  color: var(--rst-text);
  pointer-events: none;
  z-index: 50;
}

.toast-enter-active,
.toast-leave-active {
  transition: opacity 0.2s ease, transform 0.2s ease;
}

.toast-enter-from,
.toast-leave-to {
  opacity: 0;
  transform: translate(-50%, -6px);
}
</style>
