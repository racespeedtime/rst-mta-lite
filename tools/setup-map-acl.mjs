// Adds rst_ui to the existing raceACLGroup so it can start/stop mtavault map
// resources. Run this with the MTA server stopped; the server rewrites acl.xml
// on shutdown.
//
//   node tools/setup-map-acl.mjs
import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const aclPath = path.join(root, 'server', 'mods', 'deathmatch', 'acl.xml')

if (!fs.existsSync(aclPath)) {
  console.error(`acl.xml 不存在：${aclPath}`)
  process.exit(1)
}

let text = fs.readFileSync(aclPath, 'utf8')
if (text.includes('resource.rst_ui')) {
  console.log('resource.rst_ui 已经在 ACL 中，无需修改。')
  process.exit(0)
}

const marker = '<object name="resource.race"></object>'
if (!text.includes(marker)) {
  console.error('找不到 raceACLGroup 的 resource.race 标记，请手动把 resource.rst_ui 加进 raceACLGroup。')
  process.exit(1)
}

text = text.replace(marker, `${marker}\n        <object name="resource.rst_ui"></object>`)
fs.writeFileSync(aclPath, text, 'utf8')
console.log('已添加 resource.rst_ui 到 raceACLGroup。')
console.log('请确认服务器已停止后再启动，并检查服务端日志中不再出现 Access denied @ startResource。')
