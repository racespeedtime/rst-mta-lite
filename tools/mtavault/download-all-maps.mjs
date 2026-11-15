#!/usr/bin/env node
/**
 * 并发下载 mtavault DM/HDM 地图 zip，校验 zip 完整性，供手动备份。
 *
 * 默认：
 *   catalog: tools/mtavault/output/mapmeta.json
 *   输出目录: <repo>/../mtavault-map-backup/mtavault-dm-hdm
 *   代理: http://127.0.0.1:7890
 *   并发: 4
 *
 * 环境变量：
 *   MAP_BACKUP_DIR   输出目录
 *   MAP_PROXY        代理；设为 off 可禁用
 *   MAP_CONCURRENCY  并发数，默认 4，范围 1-16
 *   PYTHON           Python 3 可执行文件，用于 zip 校验
 *
 * 不安装、不写入 Git 仓库。
 */

import { createHash } from 'node:crypto'
import { spawn, spawnSync } from 'node:child_process'
import {
  appendFileSync,
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs'
import { join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const REPO = fileURLToPath(new URL('../..', import.meta.url))
const CATALOG = join(REPO, 'tools/mtavault/output/mapmeta.json')
const CACHE = join(REPO, 'server/mods/deathmatch/map-cache')
const OUT = resolve(process.env.MAP_BACKUP_DIR || join(REPO, '..', 'mtavault-map-backup', 'mtavault-dm-hdm'))
const PROXY = (process.env.MAP_PROXY || 'http://127.0.0.1:7890').trim()
const PYTHON = process.env.PYTHON || (process.platform === 'win32' ? 'python' : 'python3')
const CURL = process.platform === 'win32' ? 'curl.exe' : 'curl'
const CONCURRENCY = Math.max(
  1,
  Math.min(16, Number.parseInt(process.env.MAP_CONCURRENCY || '4', 10) || 4),
)
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

function saveManifest(manifest) {
  writeFileSync(MANIFEST, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8')
}

function curlArgs(part, url, resume) {
  const args = [
    '-L',
    '--fail',
    '--silent',
    '--show-error',
    '--retry', '2',
    '--retry-delay', '2',
    '--connect-timeout', '20',
    '--max-time', '600',
    '--speed-limit', '1024',
    '--speed-time', '60',
    '-A', 'rst-mta-map-backup/1.0',
    '-o', part,
  ]
  if (PROXY && PROXY.toLowerCase() !== 'off') {
    args.push('-x', PROXY)
  }
  if (resume) {
    args.push('-C', '-')
  }
  args.push(url)
  return args
}

function runCurl(args, timeoutMs = 660000) {
  return new Promise((resolve) => {
    let stderr = ''
    let settled = false
    const child = spawn(CURL, args, {
      stdio: ['ignore', 'ignore', 'pipe'],
      windowsHide: true,
    })

    const timer = setTimeout(() => {
      if (!settled) {
        settled = true
        child.kill()
        resolve({ error: new Error('curl timeout'), status: null, stderr })
      }
    }, timeoutMs)

    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString()
    })
    child.on('error', (error) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      resolve({ error, status: null, stderr })
    })
    child.on('close', (status) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      resolve({ error: null, status, stderr })
    })
  })
}

async function downloadOne(item, position, total, manifest) {
  const { map, slug, dest } = item
  const part = `${dest}.part`
  const url = `https://dl.mtavault.com/map/${encodeURIComponent(slug)}`
  let resume = existsSync(part) && statSync(part).size > 0
  let rangeRetried = false

  log(`START ${position}/${total} ${slug}${resume ? ' resume' : ''}`)

  for (let attempt = 1; attempt <= 3; attempt += 1) {
    if (existsSync(part) && statSync(part).size === 0) {
      rmSync(part, { force: true })
      resume = false
    } else if (!resume && existsSync(part)) {
      resume = true
    }

    const result = await runCurl(curlArgs(part, url, resume))

    if (result.error) {
      log(`CURL ERROR ${slug} attempt=${attempt}: ${result.error.message}`)
    } else if (result.status === 33 && resume && !rangeRetried) {
      // 源站不支持 Range，丢掉半包后从头下载
      log(`RANGE UNSUPPORTED ${slug}; restarting from zero`)
      rangeRetried = true
      rmSync(part, { force: true })
      resume = false
      attempt -= 1
      continue
    } else if (result.status !== 0) {
      log(`CURL FAIL ${slug} attempt=${attempt}: ${(result.stderr || '').trim()}`)
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
        saveManifest(manifest)
        log(`OK ${slug} bytes=${check.size} sha256=${digest}`)
        return true
      }

      log(`INVALID ${slug} attempt=${attempt}: ${JSON.stringify(check)}`)
      rmSync(part, { force: true })
      resume = false
    }

    if (attempt < 3) {
      await sleep(1000 * attempt + Math.floor(Math.random() * 750))
    }
  }

  manifest.failed[slug] = map.name || 'unknown'
  saveManifest(manifest)
  log(`FAILED ${slug} part kept=${existsSync(part) ? statSync(part).size : 0}`)
  return false
}

async function main() {
  if (!existsSync(OUT)) {
    mkdirSync(OUT, { recursive: true })
  }
  const catalog = JSON.parse(readFileSync(CATALOG, 'utf8'))
  const maps = Array.isArray(catalog.maps) ? catalog.maps : []
  const manifest = loadJson(MANIFEST, { downloaded: {}, failed: {}, skipped: {} })

  log(`catalog maps=${maps.length} out=${OUT} proxy=${PROXY} concurrency=${CONCURRENCY}`)

  // 现有缓存包：先校验，再复制到备份目录
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

  saveManifest(manifest)
  log(`queue=${queue.length} already=${Object.keys(manifest.downloaded).length + Object.keys(manifest.skipped).length}`)

  let next = 0
  let done = 0

  async function worker(workerId) {
    while (true) {
      const index = next
      next += 1
      if (index >= queue.length) return

      const item = queue[index]
      await downloadOne(item, index + 1, queue.length, manifest)
      done += 1
      if (done % 10 === 0) {
        saveManifest(manifest)
        log(`PROGRESS ${done}/${queue.length} worker=${workerId}`)
      }
      await sleep(150)
    }
  }

  await Promise.all(
    Array.from({ length: Math.min(CONCURRENCY, Math.max(1, queue.length)) }, (_, i) => worker(i + 1)),
  )

  saveManifest(manifest)
  log(`DONE downloaded=${Object.keys(manifest.downloaded).length} skipped=${Object.keys(manifest.skipped).length} failed=${Object.keys(manifest.failed).length}`)
}

main().catch((error) => {
  log(`FATAL ${error.stack || error.message}`)
  process.exitCode = 1
})
