<script setup lang="ts">
import IconHeart from '~icons/lucide/heart'
import IconTrophy from '~icons/lucide/trophy'
import { ui } from '@/stores/ui'
</script>

<template>
  <aside v-if="ui.competition" class="competition">
    <header class="competition__head">
      <span class="competition__title">
        <IconTrophy class="icon icon--sm" />
        竞技排行
      </span>
      <span class="competition__alive">
        存活 <strong>{{ ui.competition.alive }}</strong> / {{ ui.competition.total }}
      </span>
    </header>

    <ol class="competition__list">
      <li
        v-for="player in ui.competition.players"
        :key="player.name + player.rank"
        class="competition__row"
        :class="{
          'competition__row--me': player.me,
          'competition__row--out': !player.alive,
          'competition__row--top': player.rank <= 3 && player.alive,
        }"
      >
        <span class="competition__rank">{{ player.rank }}</span>
        <span class="competition__name">{{ player.name }}</span>
        <span v-if="player.alive" class="competition__distance">
          {{ player.distance === undefined || player.distance === null ? '--' : `${player.distance}m` }}
        </span>
        <span v-if="player.alive" class="competition__lives">
          <IconHeart class="icon icon--sm" />
          {{ player.lives }}
        </span>
        <span v-else class="competition__out">淘汰</span>
      </li>
    </ol>

    <p class="competition__foot">
      {{ ui.competition.finish ? '按到终点距离排序 · rewind 消耗 1 命' : '未配置终点 · 按命数排序' }}
    </p>
  </aside>
</template>

<style scoped>
.competition {
  position: absolute;
  right: 24px;
  top: 50%;
  transform: translateY(-50%);
  width: 236px;
  max-height: 360px;
  display: flex;
  flex-direction: column;
  padding: 12px 12px 10px;
  border: 1px solid var(--rst-border);
  border-radius: 14px;
  background: linear-gradient(160deg, rgba(19, 31, 48, 0.9), rgba(7, 11, 19, 0.92));
  box-shadow: var(--rst-shadow);
  backdrop-filter: blur(14px);
}

.competition__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding-bottom: 8px;
  border-bottom: 1px solid rgba(140, 180, 255, 0.1);
}

.competition__title {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 11px;
  font-weight: 600;
  color: var(--rst-gold);
}

.competition__alive {
  font-size: 9px;
  color: var(--rst-muted);
}

.competition__alive strong {
  color: var(--rst-green);
  font-size: 11px;
}

.competition__list {
  margin: 6px 0 0;
  padding: 0;
  list-style: none;
  overflow-y: auto;
}

.competition__list::-webkit-scrollbar {
  width: 4px;
}

.competition__list::-webkit-scrollbar-thumb {
  border-radius: 2px;
  background: rgba(140, 180, 255, 0.22);
}

.competition__row {
  display: flex;
  align-items: center;
  gap: 7px;
  padding: 5px 4px;
  border-radius: 6px;
  font-size: 11px;
}

.competition__row--me {
  background: rgba(88, 200, 255, 0.1);
}

.competition__row--out {
  opacity: 0.55;
}

.competition__row--top .competition__rank {
  color: var(--rst-gold);
}

.competition__rank {
  width: 18px;
  text-align: center;
  font-size: 9px;
  color: var(--rst-muted);
  font-variant-numeric: tabular-nums;
}

.competition__name {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.competition__distance {
  width: 44px;
  text-align: right;
  font-size: 9px;
  color: var(--rst-muted);
  font-variant-numeric: tabular-nums;
}

.competition__lives {
  display: inline-flex;
  align-items: center;
  gap: 3px;
  color: #7ee2a8;
  font-size: 10px;
  font-variant-numeric: tabular-nums;
}

.competition__out {
  color: rgba(248, 113, 113, 0.85);
  font-size: 9px;
  letter-spacing: 0.06em;
}

.competition__foot {
  margin: 8px 0 0;
  padding-top: 7px;
  border-top: 1px solid rgba(140, 180, 255, 0.08);
  font-size: 9px;
  color: var(--rst-muted);
  text-align: center;
}
</style>
