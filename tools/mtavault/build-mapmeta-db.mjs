#!/usr/bin/env node
/**
 * 用 mtavault catalog（tools/mtavault/output/mapmeta.json）更新运行时地图元数据库。
 *
 * 用法：
 *   node tools/mtavault/build-mapmeta-db.mjs
 *   node tools/mtavault/build-mapmeta-db.mjs --catalog tools/mtavault/output/mapmeta.json
 *   node tools/mtavault/build-mapmeta-db.mjs --db server/mods/deathmatch/databases/global/rst_ui_mapmeta.db
 *
 * 行为：
 * - 只按 mtavault_id upsert，不删除任何行；手工维护的第三方地图行会保留
 * - 保留已有的 resource 映射（第三方地图手动绑定的 map id 不会被覆盖）
 * - 数据库不存在时自动从 seed 复制一份再更新
 * - 建议停服后运行，避免 SQLite 写入竞争
 */

import { copyFile, readFile, stat } from 'node:fs/promises'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { DatabaseSync } from 'node:sqlite'

const REPO_ROOT = fileURLToPath(new URL('../..', import.meta.url))
const DEFAULT_CATALOG = join(REPO_ROOT, 'tools/mtavault/output/mapmeta.json')
const DEFAULT_DB = join(REPO_ROOT, 'server/mods/deathmatch/databases/global/rst_ui_mapmeta.db')
const DEFAULT_SEED = join(REPO_ROOT, 'tools/mtavault/seed/rst_ui_mapmeta.db')

function parseArgs(argv) {
  const options = {
    catalog: DEFAULT_CATALOG,
    db: DEFAULT_DB,
    seed: DEFAULT_SEED,
  }
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    const next = () => {
      i += 1
      if (i >= argv.length) throw new Error(`${arg} 缺少参数`)
      return argv[i]
    }
    if (arg === '--catalog') options.catalog = resolve(process.cwd(), next())
    else if (arg === '--db') options.db = resolve(process.cwd(), next())
    else if (arg === '--seed') options.seed = resolve(process.cwd(), next())
    else if (arg === '--help' || arg === '-h') options.help = true
    else throw new Error(`未知参数：${arg}`)
  }
  return options
}

function normalize(value) {
  return String(value ?? '').toLowerCase().replace(/[^a-z0-9]/g, '')
}

function isoNow() {
  return Math.floor(Date.now() / 1000)
}

async function exists(path) {
  return stat(path).then(() => true).catch(() => false)
}

function videoUrl(videoUrl) {
  if (!videoUrl) return null
  if (/^https?:\/\//i.test(videoUrl)) return videoUrl
  return `https://www.youtube.com/watch?v=${videoUrl}`
}

function mapType(tags) {
  return Array.isArray(tags) && tags.includes('HDM') ? 'HDM' : 'DM'
}

async function main() {
  const options = parseArgs(process.argv.slice(2))
  if (options.help) {
    console.log('node tools/mtavault/build-mapmeta-db.mjs [--catalog file] [--db file] [--seed file]')
    return
  }

  const catalog = JSON.parse(await readFile(options.catalog, 'utf8'))
  if (!Array.isArray(catalog.maps)) {
    throw new Error(`catalog 格式不对，缺少 maps: ${options.catalog}`)
  }

  if (!(await exists(options.db)) && (await exists(options.seed))) {
    await copyFile(options.seed, options.db)
    console.log(`[mapmeta-db] 从 seed 初始化 ${options.db}`)
  }

  const db = new DatabaseSync(options.db)
  db.exec(`
    CREATE TABLE IF NOT EXISTS map_meta (
      mtavault_id TEXT PRIMARY KEY,
      resource TEXT,
      name TEXT,
      name_norm TEXT,
      authors TEXT,
      author_norm TEXT,
      file_name TEXT,
      file_name_norm TEXT,
      cover TEXT,
      youtube TEXT,
      source_url TEXT,
      uploaded_at TEXT,
      downloads INTEGER,
      file_size INTEGER,
      tags TEXT,
      map_type TEXT,
      updated_at INTEGER,
      difficulty TEXT
    )
  `)

  const upsert = db.prepare(`
    INSERT INTO map_meta (
      mtavault_id, resource, name, name_norm, authors, author_norm,
      file_name, file_name_norm, cover, youtube, source_url, uploaded_at,
      downloads, file_size, tags, map_type, updated_at, difficulty
    ) VALUES (?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(mtavault_id) DO UPDATE SET
      name = excluded.name,
      name_norm = excluded.name_norm,
      authors = excluded.authors,
      author_norm = excluded.author_norm,
      file_name = excluded.file_name,
      file_name_norm = excluded.file_name_norm,
      cover = excluded.cover,
      youtube = excluded.youtube,
      source_url = excluded.source_url,
      uploaded_at = excluded.uploaded_at,
      downloads = excluded.downloads,
      file_size = excluded.file_size,
      tags = excluded.tags,
      map_type = excluded.map_type,
      updated_at = excluded.updated_at,
      difficulty = excluded.difficulty,
      resource = COALESCE(map_meta.resource, excluded.resource)
  `)

  let written = 0
  const seen = new Set()
  db.exec('BEGIN')
  try {
    for (const map of catalog.maps) {
      if (!map?.id || !map?.name) continue
      if (seen.has(map.id)) continue
      seen.add(map.id)

      const authors = Array.isArray(map.authors) ? map.authors.join(', ') : String(map.authors || '')
      const tags = Array.isArray(map.tags) ? map.tags : []
      upsert.run(
        map.id,
        map.name,
        normalize(map.name),
        authors,
        normalize(authors),
        map.fileName || '',
        normalize(map.fileName || ''),
        map.coverUrl || '',
        videoUrl(map.videoUrl),
        map.sourceUrl || '',
        map.uploadedAt || '',
        Number(map.popularity) || 0,
        Number(map.fileSize) || 0,
        JSON.stringify([tags]),
        mapType(tags),
        isoNow(),
        map.difficulty || '',
      )
      written += 1
    }
    db.exec('COMMIT')
  } catch (error) {
    db.exec('ROLLBACK')
    throw error
  } finally {
    db.close()
  }

  console.log(`[mapmeta-db] ${options.catalog} -> ${options.db}`)
  console.log(`[mapmeta-db] upsert ${written} 张地图，其它行保持不变`)
}

main().catch((error) => {
  console.error(`[mapmeta-db] failed: ${error.stack || error.message}`)
  process.exitCode = 1
})
