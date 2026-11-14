<script setup lang="ts">
import { computed } from 'vue'

import IconHeart from '~icons/lucide/heart'
import IconTrophy from '~icons/lucide/trophy'
import type { CompetitionPlayer, TeamScore } from '@/mta/protocol'
import { ui } from '@/stores/ui'

interface TeamGroup {
  team: TeamScore | null
  players: CompetitionPlayer[]
}

const groups = computed<TeamGroup[]>(() => {
  const competition = ui.competition
  if (!competition) return []
  if (competition.format === 'team' && competition.teams) {
    return competition.teams.map((team) => ({
      team,
      players: competition.players.filter((player) => player.team === team.id),
    }))
  }
  return [{ team: null, players: competition.players }]
})

function progressLabel(player: CompetitionPlayer): string {
  if (player.finished) return '完赛'
  if (player.progress !== undefined && player.progress !== null) return `${player.progress}%`
  if (player.distance !== undefined && player.distance !== null) return `${player.distance}m`
  return '--'
}
</script>

<template>
  <aside v-if="ui.competition" class="competition">
    <header class="competition__head">
      <span class="competition__title">
        <IconTrophy class="icon icon--sm" />
        {{ ui.competition.format === 'team' ? '团队排行' : '竞技排行' }}
      </span>
      <span class="competition__alive">
        存活 <strong>{{ ui.competition.alive }}</strong> / {{ ui.competition.total }}
      </span>
    </header>

    <div class="competition__body">
      <section
        v-for="group in groups"
        :key="group.team?.id || 'solo'"
        class="competition__group"
        :class="group.team ? `competition__group--${group.team.id}` : ''"
      >
        <div v-if="group.team" class="competition__team-head">
          <span>{{ group.team.name }}</span>
          <strong>{{ group.team.score }} 分</strong>
        </div>

        <ol class="competition__list">
          <li
            v-for="player in group.players"
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
              {{ progressLabel(player) }}
            </span>
            <span v-if="player.alive" class="competition__lives">
              <IconHeart class="icon icon--sm" />
              {{ player.lives }}
            </span>
            <span v-else class="competition__out">淘汰</span>
            <span v-if="player.points" class="competition__points">+{{ player.points }}</span>
          </li>
        </ol>
      </section>
    </div>

    <p class="competition__foot">
      {{
        ui.competition.format === 'team'
          ? '按冲线名次计分，红蓝总分高者胜'
          : ui.competition.ranking === 'finish'
            ? '按冲线顺序 / 终点进度排序'
            : '按远离起点进度估算'
      }}
    </p>
  </aside>
</template>

<style scoped>
.competition {
  position: absolute;
  right: 24px;
  top: 50%;
  transform: translateY(-50%);
  width: 260px;
  max-height: 420px;
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

.competition__body {
  display: flex;
  flex-direction: column;
  gap: 9px;
  margin-top: 8px;
  overflow-y: auto;
}

.competition__group {
  min-width: 0;
}

.competition__group--red .competition__team-head {
  color: #ff9b9b;
  border-color: rgba(255, 110, 110, 0.35);
}

.competition__group--blue .competition__team-head {
  color: #9cc9ff;
  border-color: rgba(100, 170, 255, 0.35);
}

.competition__team-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 4px 7px;
  margin-bottom: 4px;
  border-left: 2px solid currentColor;
  font-size: 10px;
}

.competition__team-head strong {
  font-size: 12px;
  color: var(--rst-text);
}

.competition__list {
  display: flex;
  flex-direction: column;
  gap: 3px;
  margin: 0;
  padding: 0;
  list-style: none;
}

.competition__row {
  display: grid;
  grid-template-columns: 20px minmax(0, 1fr) auto auto auto;
  align-items: center;
  gap: 5px;
  padding: 5px 6px;
  border-radius: 6px;
  font-size: 10px;
  color: var(--rst-muted);
}

.competition__row--top {
  color: var(--rst-text);
}

.competition__row--me {
  background: rgba(88, 200, 255, 0.08);
}

.competition__row--out {
  opacity: 0.5;
}

.competition__rank {
  color: var(--rst-accent);
  font-variant-numeric: tabular-nums;
}

.competition__name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.competition__distance,
.competition__lives,
.competition__points {
  font-variant-numeric: tabular-nums;
  font-size: 9px;
}

.competition__points {
  color: #ffd167;
}

.competition__out {
  color: #ff9b9b;
  font-size: 9px;
}

.competition__foot {
  margin: 8px 0 0;
  padding-top: 7px;
  border-top: 1px solid var(--rst-border);
  color: var(--rst-muted);
  font-size: 9px;
}
</style>
