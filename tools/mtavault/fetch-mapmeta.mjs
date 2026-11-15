#!/usr/bin/env node
/**
 * mtavault 全量 DM / HDM 展示元数据抓取。
 *
 * 只抓元数据，不下载地图本体，也不下载封面：
 *   node tools/mtavault/fetch-mapmeta.mjs
 *
 * 输出（开发用，不在运行时资源目录）：
 *   tools/mtavault/output/mapmeta.json
 *
 * 服务端运行时只读 SQLite seed 安装出来的 rst_ui_mapmeta.db。
 * JSON 只作为抓取/检查中间结果，不参与服务器启动。
 */

import { execFile } from 'node:child_process'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { promisify } from 'node:util'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

const execFileAsync = promisify(execFile)
const REPO_ROOT = fileURLToPath(new URL('../..', import.meta.url))
const FETCH_SCRIPT = join(REPO_ROOT, 'tools/mtavault/fetch-dm-maps.mjs')
const OUTPUT_DIR = join(REPO_ROOT, 'tools/mtavault/output')
const CATALOG_PATH = join(OUTPUT_DIR, 'mapmeta.json')

async function fetchTag(tag) {
  const out = join(OUTPUT_DIR, `${tag.toLowerCase()}-maps.json`)
  const { stdout } = await execFileAsync(process.execPath, [
    FETCH_SCRIPT,
    '--tag',
    tag,
    '--out',
    out,
  ], {
    cwd: REPO_ROOT,
    maxBuffer: 8 * 1024 * 1024,
  })
  const lastLine = stdout.trim().split(/\r?\n/).pop()
  console.log(`[mapmeta] ${tag}: ${lastLine}`)
  return JSON.parse(await readFile(out, 'utf8'))
}

async function main() {
  await mkdir(OUTPUT_DIR, { recursive: true })

  const [dm, hdm] = await Promise.all([fetchTag('DM'), fetchTag('HDM')])
  const byId = new Map()
  for (const map of [...dm.maps, ...hdm.maps]) {
    if (map?.id) byId.set(map.id, map)
  }

  const maps = [...byId.values()].sort((a, b) => (b.popularity || 0) - (a.popularity || 0))
  const catalog = {
    source: 'mtavault',
    apiBase: 'https://api.mtavault.com',
    fetchedAt: new Date().toISOString(),
    filter: { types: ['DM', 'HDM'] },
    count: maps.length,
    maps,
  }

  await mkdir(OUTPUT_DIR, { recursive: true })
  await writeFile(CATALOG_PATH, `${JSON.stringify(catalog)}\n`, 'utf8')
  console.log(`[mapmeta] wrote ${maps.length} DM/HDM maps to ${CATALOG_PATH}`)
}

main().catch((error) => {
  console.error(`[mapmeta] failed: ${error.stack || error.message}`)
  process.exitCode = 1
})
