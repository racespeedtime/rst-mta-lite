// 把 rst_ui 接进 raceACLGroup，并补上按需装载地图需要的函数权限。
// 服务器停止时 MTA 会重写 acl.xml，所以务必先关服再运行。
//
//   node tools/setup-map-acl.mjs
//   node tools/setup-map-acl.mjs --check   # 只检查，不写入
import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const aclPath = path.join(root, 'server', 'mods', 'deathmatch', 'acl.xml')
const checkOnly = process.argv.includes('--check')

const REQUIRED_RIGHTS = [
  'function.startResource',
  'function.stopResource',
  'function.restartResource',
  'function.createResource',
  'function.deleteResource',
  'function.refreshResources',
  'function.xmlLoadFile',
]

if (!fs.existsSync(aclPath)) {
  console.error(`acl.xml 不存在：${aclPath}`)
  process.exit(1)
}

let text = fs.readFileSync(aclPath, 'utf8')
const changes = []

// ── 1) raceACLGroup 里的 resource.rst_ui ────────────────────────────────

const groupMatch = /<group name="raceACLGroup">([\s\S]*?)<\/group>/.exec(text)
if (!groupMatch) {
  console.error('找不到 raceACLGroup，请手动把 resource.rst_ui 加进去。')
  process.exit(1)
}

if (!/resource\.rst_ui/.test(groupMatch[1])) {
  const marker = /<object name="resource\.race"><\/object>/
  if (!marker.test(groupMatch[1])) {
    console.error('raceACLGroup 里找不到 resource.race，请手动把 resource.rst_ui 加进去。')
    process.exit(1)
  }
  const patchedGroup = groupMatch[1].replace(
    marker,
    (line) => `${line}\n        <object name="resource.rst_ui"></object>`,
  )
  text = text.replace(groupMatch[0], `<group name="raceACLGroup">${patchedGroup}</group>`)
  changes.push('raceACLGroup += resource.rst_ui')
}

// ── 2) raceACL 里的函数权限 ─────────────────────────────────────────────

const aclMatch = /(\n    <acl name="raceACL">)([\s\S]*?)(\n    <\/acl>)/.exec(text)
if (!aclMatch) {
  console.error('找不到 raceACL 定义，请手动补上：' + REQUIRED_RIGHTS.join(', '))
  process.exit(1)
}

const body = aclMatch[2]
const missing = REQUIRED_RIGHTS.filter((right) => !new RegExp(`name="${right.replace(/\./g, '\\.')}"`).test(body))
if (missing.length) {
  const inserted = missing.map((right) => `        <right name="${right}" access="true"></right>`).join('\n')
  text = text.replace(aclMatch[0], `${aclMatch[1]}\n${inserted}${aclMatch[2]}${aclMatch[3]}`)
  changes.push(...missing.map((right) => `raceACL += ${right}`))
}

// ── 结果 ────────────────────────────────────────────────────────────────

if (!changes.length) {
  console.log('ACL 已经配置好，无需修改。')
  process.exit(0)
}

if (checkOnly) {
  console.log('需要修改：')
  for (const change of changes) console.log(`  - ${change}`)
  process.exit(1)
}

fs.writeFileSync(aclPath, text, 'utf8')
console.log('已更新 acl.xml：')
for (const change of changes) console.log(`  - ${change}`)
console.log('重新开服后检查日志里不再出现 Access denied（createResource / refreshResources）。')
