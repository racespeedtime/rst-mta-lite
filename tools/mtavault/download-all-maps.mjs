#!/usr/bin/env node
/**
 * 顺序下载 mtavault DM/HDM 地图 zip，校验 zip 完整性，供手动备份。
 *
 * 默认：
 *   catalog: server/.../rst_ui/mapmeta-catalog.json
 *   输出目录: D:\Work\rst-mta-map-backup\mtavault-dm-hdm
 *   代理: http://127.0.0.1:7890
 *
 * 不并行、不安装、不写入 Git 仓库。
 */

import { createHash } from 'node:crypto'
import { spawnSync } from 'node:child_process'
import { copyFileSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync, appendFileSync } from 'node:fs'
import { join, resolve } from 'node:path'

const REPO = 'D:/Work/rst-mta-lite'
const CATALOG = join(REPO, 'server/mods/deathmatch/resources/[rst]/rst_ui/mapmeta-catalog.json')
const CACHE = join(REPO, 'server/mods/deathmatch/map-cache')
const OUT = resolve(process.env.MAP_BACKUP_DIR || 'D:/Work/rst-mta-map-backup/mtavault-dm-hdm')
const PROXY = process.env.MAP_PROXY || 'http://127.0.0.1:7890'
const PYTHON = process.env.PYTHON || 'C:/Users/yjl/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/python/python.exe'
const LOG = join(OUT, 'download.log')
const MANIFEST = join(OUT, 'manifest.json')

const validationCode = String.raw`
import sys, zipfile, json, os
try:
    z = zipfile.ZipFile(sys.argv[1])
    bad = z.testzip()
    names = z.namelist()
    meta = [n for n in names if n.lower().endswith('meta.xml')]
    maps = [n for n in names if n.lower().endswith('.map')]
    print(json.dumps({
        'ok': bad is None and bool(meta) and bool(maps),
        'bad': bad,
        'meta': meta[:1],
        'maps': len(maps),
        'entries': len(names),
        'size': os.path.getsize(sys.argv[1]),
    }))
except Exception as e:
    print(json.dumps({'ok': False, 'error': str(e)}))
`

function log(line) {
  const text = `[${new Date().toISOString()}] ${line}`
  console.log(text)
  appendFileSync(LOG, `${text}\n`, 'utf8')
}

function validate(path) {
  if (!existsSync(path) || statSync(path).size === 0) {
    return { ok: false, error: 'missing/empty' }
  }
  const result = spawnSync(PYTHON, ['-c', validationCode, path], {
    encoding: 'utf8',
    timeout: 120000,
  })
  if (result.status !== 0) {
    return { ok: false, error: result.stderr || 'validator failed' }
  }
  try {
    return JSON.parse(result.stdout.trim())
  } catch (error) {
    return { ok: false, error: `bad validator output: ${error.message}` }
  }
}

function hashFile(path) {
  const hash = createHash('sha256')
  hash.update(readFileSync(path))
  return hash.digest('hex')
}

function slugOf(map) {
  try {
    const parts = new URL(map.sourceUrl).pathname.replace(/^\/+|\/+$/g, '').split('/')
    return parts[parts.length - 1] || ''
  } catch {
    return ''
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function loadJson(path, fallback) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'))
  } catch {
    return fallback
  }
}

async function main() {
  if (!existsSync(OUT)) {
    mkdirSync(OUT, { recursive: true })
  }
  const catalog = JSON.parse(readFileSync(CATALOG, 'utf8'))
  const maps = Array.isArray(catalog.maps) ? catalog.maps : []
  const manifest = loadJson(MANIFEST, { downloaded: {}, failed: {}, skipped: {} })

  log(`catalog maps=${maps.length} out=${OUT} proxy=${PROXY}`)

  // 现有 3 个缓存包：先校验，再复制到备份目录
  const cached = [
    ['silent-hill.zip', 'silent-hill'],
    ['a-new-dawn.zip', 'a-new-dawn'],
    ['descendants-skills-v.zip', 'descendants-skills-v'],
  ]
  for (const [file, slug] of cached) {
    const src = join(CACHE, file)
    const dst = join(OUT, `${slug}.zip`)
    if (!existsSync(src)) continue
    if (existsSync(dst) && validate(dst).ok) {
      manifest.skipped[slug] = true
      continue
    }
    const check = validate(src)
    if (!check.ok) {
      log(`CACHE INVALID ${file}: ${JSON.stringify(check)}`)
      continue
    }
    copyFileSync(src, dst)
    manifest.skipped[slug] = true
    log(`CACHE COPY ${file} -> ${slug}.zip`)
  }

  const queue = []
  for (const map of maps) {
    const slug = slugOf(map)
    if (!slug) {
      manifest.failed[String(map.id || map.name)] = 'missing sourceUrl slug'
      continue
    }
    const dest = join(OUT, `${slug}.zip`)
    if (manifest.downloaded[slug] || manifest.skipped[slug] || (existsSync(dest) && validate(dest).ok)) {
      if (!manifest.downloaded[slug] && !manifest.skipped[slug]) {
        manifest.downloaded[slug] = { name: map.name, checked: true }
      }
      continue
    }
    if (existsSync(dest)) {
      log(`INVALID EXISTING ${slug}.zip, redownload`)
      rmSync(dest, { force: true })
    }
    queue.push({ map, slug, dest })
  }

  writeFileSync(MANIFEST, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8')
  log(`queue=${queue.length} already=${Object.keys(manifest.downloaded).length + Object.keys(manifest.skipped).length}`)

  let done = 0
  for (const item of queue) {
    const { map, slug, dest } = item
    const part = `${dest}.part`
    const url = `https://dl.mtavault.com/map/${encodeURIComponent(slug)}`
    let ok = false

    for (let attempt = 1; attempt <= 3 && !ok; attempt += 1) {
      rmSync(part, { force: true })
      log(`GET ${done + 1}/${queue.length} ${slug} attempt=${attempt}`)
      const result = spawnSync('curl.exe', [
        '-L',
        '--fail',
        '--silent',
        '--show-error',
        '--retry', '2',
        '--retry-delay', '2',
        '--max-time', '300',
        '-x', PROXY,
        '-A', 'rst-mta-map-backup/1.0',
        '-o', part,
        url,
      ], { encoding: 'utf8', timeout: 360000 })

      if (result.error) {
        log(`CURL ERROR ${slug}: ${result.error.message}`)
      } else if (result.status !== 0) {
        log(`CURL FAIL ${slug}: ${(result.stderr || '').trim()}`)
      } else {
        const check = validate(part)
        if (check.ok) {
          renameSync(part, dest)
          const digest = hashFile(dest)
          manifest.downloaded[slug] = {
            name: map.name,
            id: map.id,
            file: `${slug}.zip`,
            bytes: check.size,
            sha256: digest,
          }
          delete manifest.failed[slug]
          writeFileSync(MANIFEST, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8')
          log(`OK ${slug} bytes=${check.size} sha256=${digest}`)
          ok = true
        } else {
          log(`INVALID ${slug}: ${JSON.stringify(check)}`)
          rmSync(part, { force: true })
        }
      }
      if (!ok) await sleep(1500)
    }

    if (!ok) {
      manifest.failed[slug] = map.name || 'unknown'
      writeFileSync(MANIFEST, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8')
      log(`FAILED ${slug}`)
    }
    done += 1
    if (done % 25 === 0) {
      writeFileSync(MANIFEST, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8')
    }
    await sleep(120)
  }

  writeFileSync(MANIFEST, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8')
  log(`DONE downloaded=${Object.keys(manifest.downloaded).length} skipped=${Object.keys(manifest.skipped).length} failed=${Object.keys(manifest.failed).length}`)
}

main().catch((error) => {
  log(`FATAL ${error.stack || error.message}`)
  process.exitCode = 1
})
