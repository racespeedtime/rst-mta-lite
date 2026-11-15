#!/usr/bin/env node
/**
 * 把仓库里的只读 mtavault 元数据 seed DB 安装到 MTA 运行目录。
 *
 * 用法：
 *   node tools/mtavault/install-mapmeta-db.mjs
 *   node tools/mtavault/install-mapmeta-db.mjs --force
 *
 * 默认目标：
 *   server/mods/deathmatch/databases/global/rst_ui_mapmeta.db
 */

import { copyFile, mkdir, stat } from 'node:fs/promises'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const REPO_ROOT = fileURLToPath(new URL('../..', import.meta.url))
const SOURCE = join(REPO_ROOT, 'tools/mtavault/seed/rst_ui_mapmeta.db')

function parseArgs(argv) {
  const options = {
    dest: join(
      REPO_ROOT,
      'server/mods/deathmatch/databases/global/rst_ui_mapmeta.db',
    ),
    force: false,
  }
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--force') options.force = true
    if (argv[i] === '--dest') options.dest = resolve(argv[++i] || '')
  }
  return options
}

async function main() {
  const options = parseArgs(process.argv.slice(2))
  const exists = await stat(options.dest).then(() => true).catch(() => false)
  if (exists && !options.force) {
    console.log(`[mapmeta] target already exists: ${options.dest}`)
    console.log('[mapmeta] use --force to overwrite')
    return
  }
  await mkdir(dirname(options.dest), { recursive: true })
  await copyFile(SOURCE, options.dest)
  console.log(`[mapmeta] installed ${SOURCE} -> ${options.dest}`)
}

main().catch((error) => {
  console.error(`[mapmeta] failed: ${error.stack || error.message}`)
  process.exitCode = 1
})
