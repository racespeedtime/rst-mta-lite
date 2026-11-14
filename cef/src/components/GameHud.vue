<script setup lang="ts">
import { computed } from 'vue'

import IconClock from '~icons/lucide/clock'
import IconCircleQuestionMark from '~icons/lucide/circle-question-mark'
import IconEye from '~icons/lucide/eye'
import IconFlag from '~icons/lucide/flag'
import IconGhost from '~icons/lucide/ghost'
import IconKeyboard from '~icons/lucide/keyboard'
import IconMap from '~icons/lucide/map'
import IconPenLine from '~icons/lucide/pen-line'
import IconRewind from '~icons/lucide/rewind'
import IconUser from '~icons/lucide/user'
import IconUsers from '~icons/lucide/users'
import IconVote from '~icons/lucide/vote'
import IconWaypoints from '~icons/lucide/waypoints'
import { ui } from '@/stores/ui'
import { formatTime } from '@/utils/format'

const spectating = computed(() => ui.mode === 'spectating')
const modeLabel = computed(() => (spectating.value ? '观战' : '比赛中'))
const gameModeLabel = computed(() => (ui.gameMode === 'competitive' ? '竞技' : '训练'))
const roundTime = computed(() => (ui.room ? formatTime(ui.room.timeLeft) : '--:--'))
</script>

<template>
  <div class="hud">
    <div class="hud__top">
      <div class="hud__brand">
        <span class="hud__dot" />
        <span class="hud__brand-name">RST MTA LITE</span>
      </div>
      <div class="hud__player">
        <span class="hud__avatar"><IconUser class="icon" /></span>
        <div class="hud__player-main">
          <strong>{{ ui.playerName }}</strong>
          <span>{{ ui.guest ? '游客' : '已登录' }} · {{ ui.serverName }}</span>
        </div>
        <span v-if="ui.guest" class="hud__tag"><IconGhost class="icon icon--sm" />GUEST</span>
      </div>
    </div>

    <section v-if="ui.room" class="room">
      <div class="room__head">
        <IconFlag class="icon room__flag" />
        <span class="room__name">{{ ui.room.name }}</span>
        <span class="room__game-mode" :class="{ 'room__game-mode--competitive': ui.gameMode === 'competitive' }">
          {{ gameModeLabel }}
        </span>
        <span class="room__mode" :class="{ 'room__mode--spectate': spectating }">{{ modeLabel }}</span>
      </div>

      <dl class="room__rows">
        <div>
          <dt><IconMap class="icon icon--sm" />赛道</dt>
          <dd>{{ ui.room.mapName }}</dd>
        </div>
        <div>
          <dt><IconClock class="icon icon--sm" />剩余</dt>
          <dd>{{ roundTime }}</dd>
        </div>
        <div>
          <dt><IconUsers class="icon icon--sm" />玩家</dt>
          <dd>{{ ui.room.players }}</dd>
        </div>
        <div>
          <dt><IconEye class="icon icon--sm" />观战</dt>
          <dd>{{ ui.room.spectators }}</dd>
        </div>
      </dl>

      <p v-if="ui.vote?.active" class="room__vote">
        <IconVote class="icon icon--sm" />
        换图投票 · {{ formatTime(ui.vote.timeLeft) }}
      </p>
      <p v-else-if="ui.modeVote?.active" class="room__vote">
        <IconVote class="icon icon--sm" />
        模式投票 · {{ formatTime(ui.modeVote.timeLeft) }}
      </p>
    </section>

    <div v-if="spectating" class="spectate">
      <IconEye class="icon icon--sm" />
      <span>观战中<span v-if="ui.spectateName"> · {{ ui.spectateName }}</span></span>
      <span class="spectate__hint">左键下一位 · 右键上一位</span>
    </div>

    <div class="hud__hints">
      <span><IconCircleQuestionMark class="icon icon--sm" />F1 帮助</span>
      <span><IconKeyboard class="icon icon--sm" />F2 菜单</span>
      <span v-if="!spectating"><IconRewind class="icon icon--sm" />长按 Y 回放<span v-if="ui.lives !== null"> · {{ ui.lives }} 命</span></span>
    </div>

    <div v-if="ui.room" class="track">
      <p class="track__label">
        <IconWaypoints class="icon icon--sm" />
        当前赛道
      </p>
      <p class="track__map">
        <IconMap class="icon" />
        <span>{{ ui.room.mapName }}</span>
      </p>
      <p class="track__author">
        <IconPenLine class="icon icon--sm" />
        <span>作者 · {{ ui.room.author }}</span>
      </p>
    </div>
  </div>
</template>

<style scoped>
.hud {
  position: absolute;
  inset: 0;
  pointer-events: none;
  font-size: 13px;
}

.hud__top {
  position: absolute;
  top: 20px;
  left: 24px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.hud__brand {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  width: fit-content;
  padding: 6px 12px;
  border: 1px solid var(--rst-border);
  border-radius: 999px;
  background: var(--rst-panel-soft);
}

.hud__dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: var(--rst-accent);
  box-shadow: 0 0 9px var(--rst-accent);
}

.hud__brand-name {
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.18em;
}

.hud__player {
  display: flex;
  align-items: center;
  gap: 9px;
  padding: 7px 12px 7px 8px;
  width: fit-content;
  border: 1px solid var(--rst-border);
  border-radius: 12px;
  background: linear-gradient(160deg, rgba(17, 28, 44, 0.85), rgba(8, 13, 21, 0.85));
}

.hud__avatar {
  display: grid;
  place-items: center;
  width: 30px;
  height: 30px;
  border-radius: 9px;
  background: rgba(88, 200, 255, 0.12);
  border: 1px solid rgba(88, 200, 255, 0.2);
  color: var(--rst-accent);
}

.hud__player-main {
  display: flex;
  flex-direction: column;
  gap: 1px;
}

.hud__player-main strong {
  font-size: 14px;
  font-weight: 600;
}

.hud__player-main span {
  font-size: 10px;
  color: var(--rst-muted);
}

.hud__tag {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 2px 7px;
  border-radius: 999px;
  border: 1px solid rgba(139, 124, 255, 0.3);
  color: #b8aeff;
  font-size: 9px;
  letter-spacing: 0.08em;
}

.room {
  position: absolute;
  top: 20px;
  right: 24px;
  width: 286px;
  padding: 14px 16px;
  border: 1px solid var(--rst-border);
  border-radius: 14px;
  background: var(--rst-panel);
  box-shadow: 0 18px 44px rgba(0, 0, 0, 0.3);
}

.room__head {
  display: flex;
  align-items: center;
  gap: 7px;
}

.room__flag {
  color: var(--rst-accent);
}

.room__name {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 12px;
  font-weight: 600;
}

.room__game-mode {
  padding: 2px 6px;
  border-radius: 999px;
  font-size: 9px;
  color: var(--rst-muted);
  background: rgba(147, 164, 189, 0.1);
}

.room__game-mode--competitive {
  color: var(--rst-gold);
  background: rgba(255, 212, 121, 0.12);
}

.room__mode {
  padding: 2px 8px;
  border-radius: 999px;
  font-size: 10px;
  color: var(--rst-green);
  background: rgba(126, 226, 168, 0.12);
}

.room__mode--spectate {
  color: var(--rst-gold);
  background: rgba(255, 212, 121, 0.12);
}

.room__rows {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px 12px;
  margin: 14px 0 0;
}

.room__rows dt {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 10px;
  letter-spacing: 0.06em;
  color: var(--rst-muted);
}

.room__rows dd {
  margin: 3px 0 0;
  font-size: 12px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.room__vote {
  display: flex;
  align-items: center;
  gap: 5px;
  margin: 12px 0 0;
  padding-top: 10px;
  border-top: 1px solid var(--rst-border);
  font-size: 11px;
  color: var(--rst-gold);
}

.spectate {
  position: absolute;
  top: 78px;
  left: 50%;
  transform: translateX(-50%);
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 6px 14px;
  border: 1px solid rgba(255, 212, 121, 0.3);
  border-radius: 999px;
  background: rgba(40, 32, 12, 0.72);
  color: var(--rst-gold);
  font-size: 11px;
  letter-spacing: 0.04em;
  white-space: nowrap;
}

.spectate__hint {
  margin-left: 4px;
  padding-left: 9px;
  border-left: 1px solid rgba(255, 212, 121, 0.25);
  color: var(--rst-muted);
  font-size: 10px;
  letter-spacing: 0.03em;
}

.hud__hints {
  position: absolute;
  right: 24px;
  bottom: 166px;
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 6px;
}

.hud__hints span {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 6px 10px;
  border: 1px solid var(--rst-border);
  border-radius: 8px;
  background: var(--rst-panel-soft);
  font-size: 10px;
  letter-spacing: 0.04em;
  color: var(--rst-muted);
}

.track {
  position: absolute;
  right: 24px;
  bottom: 52px;
  width: 286px;
  padding: 12px 15px 13px;
  border: 1px solid var(--rst-border);
  border-radius: 14px;
  background:
    linear-gradient(160deg, rgba(23, 38, 58, 0.9), rgba(8, 13, 22, 0.94));
  box-shadow: 0 18px 44px rgba(0, 0, 0, 0.34);
}

.track__label {
  display: flex;
  align-items: center;
  gap: 5px;
  margin: 0;
  font-size: 9px;
  letter-spacing: 0.16em;
  color: var(--rst-muted);
}

.track__map {
  display: flex;
  align-items: center;
  gap: 7px;
  margin: 7px 0 3px;
  font-size: 14px;
  font-weight: 600;
  color: var(--rst-text);
}

.track__map .icon {
  color: var(--rst-accent);
}

.track__author {
  display: flex;
  align-items: center;
  gap: 5px;
  margin: 0;
  font-size: 10px;
  color: var(--rst-muted);
}
</style>
