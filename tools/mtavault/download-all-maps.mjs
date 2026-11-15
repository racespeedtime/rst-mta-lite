#!/usr/bin/env node
/**
 * 并发下载 mtavault DM/HDM 地图 zip，校验完整性，供手动备份。
 *
 * 只依赖 Node 内置模块：zip 结构/CRC 校验用 node:zlib 解析，不再调用 Python。
 *
 * 默认：
 *   catalog: tools/mtavault/output/mapmeta.json
 *   输出目录: <repo>/../mtavault-map-backup/mtavault-dm-hdm
 *   代理: http://127.0.0.1:7890
 *   并发: 8（1-24）
 *
 * 用法：
 *   node tools/mtavault/download-all-maps.mjs [选项]
 *
 *   --out <dir>          备份目录（默认 MAP_BACKUP_DIR 或 ../mtavault-map-backup/mtavault-dm-hdm）
 *   --catalog <file>     mapmeta.json 路径
 *   --concurrency <n>    并发数，1-24，默认 8
 *   --proxy <url|off>    代理地址，off 表示直连
 *   --max-time <秒>      单个文件下载上限，默认 1800
 *   --only-missing       只补缺失文件：已有 zip 不校验、不改动、不重下
 *   --verify             只校验已有 zip，不下载（默认只读中央目录，很快）
 *   --full               配合 --verify：逐条解压做 CRC 校验（全量，较慢）
 *   --deep               已有 zip 额外核对 manifest 里的 sha256（会读全量文件）
 *   --help
 *
 * 环境变量（保留兼容）：MAP_BACKUP_DIR / MAP_PROXY / MAP_CONCURRENCY / MAP_CATALOG
 *
 * 行为：
 * - 先写 .part，校验通过后才原子改名为 .zip；失败保留的 .part 下次会续传
 * - 源站不支持 Range 时自动关闭续传，避免每个文件白吃一次 curl (33)
 * - 失败按错误类型分类重试：网络抖动重试，404/410 与持续 5xx 记为 unavailable
 * - 已有 zip 只在确实损坏时才重命名隔离（*.zip.bad-<时间戳>），绝不删除
 * - manifest.json 用临时文件 + rename 原子写入，损坏时直接报错退出
 *
 * 不安装、不写入 Git 仓库。
 */

import { createHash } from 'node:crypto'
import { spawn } from 'node:child_process'
import {
  appendFileSync,
  closeSync,
  createReadStream,
  existsSync,
  mkdirSync,
  openSync,
  readFileSync,
  readSync,
  readdirSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs'
import { basename, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { inflateRawSync } from 'node:zlib'

const REPO = fileURLToPath(new URL('../..', import.meta.url))
const CURL = process.platform === 'win32' ? 'curl.exe' : 'curl'
const USER_AGENT = 'rst-mta-map-backup/1.0'
const ATTEMPTS = 3
const RETRYABLE_EXIT = new Set([7, 16, 18, 28, 35, 52, 55, 56, 67, 92])

// ── 配置 ────────────────────────────────────────────────────────────────

const HELP = `用法: node tools/mtavault/download-all-maps.mjs [选项]

  --out <dir>          备份目录（默认 MAP_BACKUP_DIR 或 ../mtavault-map-backup/mtavault-dm-hdm）
  --catalog <file>     mapmeta.json 路径
  --concurrency <n>    并发数，1-24，默认 8
  --proxy <url|off>    代理地址，off 表示直连
  --max-time <秒>      单个文件下载上限，默认 1800
  --only-missing       只补缺失文件：已有 zip 不校验、不改动、不重下
  --verify             只校验已有 zip，不下载
  --full               配合 --verify：逐条解压做 CRC 校验
  --deep               已有 zip 额外核对 manifest 里的 sha256（会读全量文件）
  --help

环境变量: MAP_BACKUP_DIR / MAP_PROXY / MAP_CONCURRENCY / MAP_CATALOG`

function parseArgs(argv) {
  const options = {
    out: process.env.MAP_BACKUP_DIR || join(REPO, '..', 'mtavault-map-backup', 'mtavault-dm-hdm'),
    catalog: process.env.MAP_CATALOG || join(REPO, 'tools/mtavault/output/mapmeta.json'),
    concurrency: process.env.MAP_CONCURRENCY || '8',
    proxy: (process.env.MAP_PROXY || 'http://127.0.0.1:7890').trim(),
    maxTime: 1800,
    onlyMissing: false,
    verify: false,
    full: false,
    deep: false,
    help: false,
  }

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    const next = () => {
      i += 1
      if (i >= argv.length) throw new Error(`${arg} 缺少参数`)
      return argv[i]
    }
    switch (arg) {
      case '--out': options.out = next(); break
      case '--catalog': options.catalog = next(); break
      case '--concurrency': options.concurrency = next(); break
      case '--proxy': options.proxy = next(); break
      case '--max-time': options.maxTime = next(); break
      case '--only-missing': options.onlyMissing = true; break
      case '--verify': options.verify = true; break
      case '--full': options.full = true; break
      case '--deep': options.deep = true; break
      case '--help':
      case '-h': options.help = true; break
      default: throw new Error(`未知参数 ${arg}（--help 查看用法）`)
    }
  }

  options.out = resolve(options.out)
  options.catalog = resolve(options.catalog)
  options.concurrency = Math.max(1, Math.min(24, Number.parseInt(options.concurrency, 10) || 8))
  options.maxTime = Math.max(120, Number.parseInt(options.maxTime, 10) || 1800)
  options.proxy = options.proxy && options.proxy.toLowerCase() !== 'off' ? options.proxy : ''
  return options
}

// 由 main() 赋值，供各处读取
let OPTIONS = null
let OUT = ''
let LOG = ''
let MANIFEST = ''
let PROXY = ''
let MAX_TIME = 1800

// ── 日志与通用工具 ──────────────────────────────────────────────────────

function log(line) {
  const text = `[${new Date().toISOString()}] ${line}`
  console.log(text)
  appendFileSync(LOG, `${text}\n`, 'utf8')
}

function sleep(ms) {
  return new Promise((done) => setTimeout(done, ms))
}

function slugOf(map) {
  try {
    const parts = new URL(map.sourceUrl).pathname.replace(/^\/+|\/+$/g, '').split('/')
    return parts[parts.length - 1] || ''
  } catch {
    return ''
  }
}

function hashFile(path) {
  return new Promise((done, fail) => {
    const hash = createHash('sha256')
    const stream = createReadStream(path)
    stream.on('data', (chunk) => hash.update(chunk))
    stream.on('error', fail)
    stream.on('end', () => done(hash.digest('hex')))
  })
}

// ── zip 校验（纯 Node，无 Python） ──────────────────────────────────────

const EOCD_SIG = 0x06054b50
const ZIP64_LOCATOR_SIG = 0x07064b50
const ZIP64_EOCD_SIG = 0x06064b50
const CENTRAL_SIG = 0x02014b50
const LOCAL_SIG = 0x04034b50

const CRC_TABLE = (() => {
  const table = new Int32Array(256)
  for (let n = 0; n < 256; n += 1) {
    let c = n
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
    table[n] = c
  }
  return table
})()

function crc32(buffer) {
  let c = -1
  for (let i = 0; i < buffer.length; i += 1) c = CRC_TABLE[(c ^ buffer[i]) & 0xff] ^ (c >>> 8)
  return (c ^ -1) >>> 0
}

function readAt(fd, length, position) {
  const buffer = Buffer.allocUnsafe(length)
  let offset = 0
  while (offset < length) {
    const read = readSync(fd, buffer, offset, length - offset, position + offset)
    if (read <= 0) throw new Error('文件意外结束（可能被截断）')
    offset += read
  }
  return buffer
}

function readEocd(fd, size) {
  const tailSize = Math.min(size, 66_000)
  const tailStart = size - tailSize
  const tail = readAt(fd, tailSize, tailStart)
  for (let i = tail.length - 22; i >= 0; i -= 1) {
    if (tail.readUInt32LE(i) !== EOCD_SIG) continue
    if (i + 22 + tail.readUInt16LE(i + 20) !== tail.length) continue

    let entries = tail.readUInt16LE(i + 10)
    let cdSize = tail.readUInt32LE(i + 12)
    let cdOffset = tail.readUInt32LE(i + 16)
    if (entries === 0xffff || cdSize === 0xffffffff || cdOffset === 0xffffffff) {
      const locatorPos = tailStart + i - 20
      if (locatorPos >= 0) {
        const locator = readAt(fd, 20, locatorPos)
        if (locator.readUInt32LE(0) === ZIP64_LOCATOR_SIG) {
          const zip64 = readAt(fd, 56, Number(locator.readBigUInt64LE(8)))
          if (zip64.readUInt32LE(0) === ZIP64_EOCD_SIG) {
            entries = Number(zip64.readBigUInt64LE(32))
            cdSize = Number(zip64.readBigUInt64LE(40))
            cdOffset = Number(zip64.readBigUInt64LE(48))
          }
        }
      }
    }
    return { entries, cdSize, cdOffset }
  }
  throw new Error('找不到 zip 中央目录（文件可能被截断）')
}

function readCentralEntries(fd, cdOffset, cdSize, fileSize) {
  if (cdSize <= 0 || cdOffset + cdSize > fileSize) throw new Error('中央目录越界（文件可能被截断）')
  const buffer = readAt(fd, cdSize, cdOffset)
  const entries = []
  let cursor = 0
  while (cursor + 46 <= buffer.length) {
    if (buffer.readUInt32LE(cursor) !== CENTRAL_SIG) throw new Error('中央目录结构损坏')
    const flags = buffer.readUInt16LE(cursor + 8)
    const method = buffer.readUInt16LE(cursor + 10)
    const crc = buffer.readUInt32LE(cursor + 16)
    const compSize = buffer.readUInt32LE(cursor + 20)
    const uncompSize = buffer.readUInt32LE(cursor + 24)
    const nameLength = buffer.readUInt16LE(cursor + 28)
    const extraLength = buffer.readUInt16LE(cursor + 30)
    const commentLength = buffer.readUInt16LE(cursor + 32)
    const localOffset = buffer.readUInt32LE(cursor + 42)
    const name = buffer.toString('utf8', cursor + 46, cursor + 46 + nameLength)
    entries.push({ name, flags, method, crc, compSize, uncompSize, localOffset })
    cursor += 46 + nameLength + extraLength + commentLength
  }
  if (!entries.length) throw new Error('中央目录为空')
  return entries
}

function verifyEntry(fd, entry) {
  if (entry.flags & 0x1) throw new Error(`条目已加密: ${entry.name}`)
  if (entry.compSize === 0xffffffff || entry.localOffset === 0xffffffff) {
    throw new Error(`暂不支持 zip64 条目: ${entry.name}`)
  }
  const header = readAt(fd, 30, entry.localOffset)
  if (header.readUInt32LE(0) !== LOCAL_SIG) throw new Error(`本地文件头损坏: ${entry.name}`)
  const dataStart = entry.localOffset + 30 + header.readUInt16LE(26) + header.readUInt16LE(28)
  const compressed = entry.compSize ? readAt(fd, entry.compSize, dataStart) : Buffer.alloc(0)

  let data
  if (entry.method === 0) data = compressed
  else if (entry.method === 8) data = inflateRawSync(compressed)
  else throw new Error(`不支持的压缩方式 ${entry.method}: ${entry.name}`)

  if (data.length !== entry.uncompSize) throw new Error(`解压长度不符: ${entry.name}`)
  if (crc32(data) !== entry.crc >>> 0) throw new Error(`CRC 不匹配: ${entry.name}`)
  return data.length
}

/**
 * 校验一个 zip：结构（默认）或全量 CRC（full=true）。
 * 返回 { ok, error?, entries, maps, size, bytes? }
 */
function inspectZip(file, { full = false } = {}) {
  let fd = null
  try {
    const size = statSync(file).size
    if (size === 0) return { ok: false, error: '空文件' }
    fd = openSync(file, 'r')
    const eocd = readEocd(fd, size)
    const entries = readCentralEntries(fd, eocd.cdOffset, eocd.cdSize, size)

    const names = entries.map((entry) => entry.name)
    const maps = names.filter((name) => name.toLowerCase().endsWith('.map')).length
    const hasMeta = names.some((name) => name.toLowerCase().endsWith('meta.xml'))
    if (!hasMeta) return { ok: false, error: '缺少 meta.xml', entries: entries.length, maps, size }
    if (!maps) return { ok: false, error: '缺少 .map', entries: entries.length, maps, size }

    if (!full) return { ok: true, entries: entries.length, maps, size }

    let bytes = 0
    for (const entry of entries) {
      if (entry.name.endsWith('/')) continue
      bytes += verifyEntry(fd, entry)
    }
    return { ok: true, entries: entries.length, maps, size, bytes, full: true }
  } catch (error) {
    return { ok: false, error: error.message }
  } finally {
    if (fd !== null) closeSync(fd)
  }
}

// ── manifest ────────────────────────────────────────────────────────────

const KNOWN_KEYS = ['downloaded', 'failed', 'skipped', 'unavailable']

function loadManifest() {
  if (!existsSync(MANIFEST)) {
    return { downloaded: {}, failed: {}, skipped: {}, unavailable: {} }
  }
  const text = readFileSync(MANIFEST, 'utf8')
  let parsed
  try {
    parsed = JSON.parse(text)
  } catch (error) {
    // 绝不静默降级成空对象：那会让已存在的备份被当成缺失重复下载
    throw new Error(`manifest.json 解析失败（${error.message}）；请先修复或移走 ${MANIFEST}`)
  }
  const manifest = {
    downloaded: parsed.downloaded || {},
    failed: parsed.failed || {},
    skipped: parsed.skipped || {},
    unavailable: parsed.unavailable || {},
  }
  for (const [key, value] of Object.entries(parsed)) {
    if (!KNOWN_KEYS.includes(key)) manifest[key] = value
  }
  return manifest
}

let manifest = null
let manifestDirty = false

function markDirty() {
  manifestDirty = true
}

function saveManifest(force = false) {
  if (!manifest || (!manifestDirty && !force)) return
  const tmp = `${MANIFEST}.tmp`
  writeFileSync(tmp, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8')
  renameSync(tmp, MANIFEST) // 原子替换，避免写一半留下坏 JSON
  manifestDirty = false
}

// ── 下载 ────────────────────────────────────────────────────────────────

const stats = {
  startedAt: Date.now(),
  done: 0,
  ok: 0,
  bytes: 0,
  failed: 0,
  unavailable: 0,
}
let aborted = false
let resumeSupported = null
let consecutiveNetworkErrors = 0

function curlArgs(part, url, resume) {
  const args = [
    '-L',
    '--fail',
    '--silent',
    '--show-error',
    '--http1.1',
    '--connect-timeout', '20',
    '--max-time', String(MAX_TIME),
    '--speed-limit', '256',
    '--speed-time', '90',
    '-A', USER_AGENT,
    '-o', part,
    '-w', '%{http_code}',
  ]
  if (PROXY) args.push('-x', PROXY)
  if (resume) args.push('-C', '-')
  args.push(url)
  return args
}

function runCurl(args) {
  return new Promise((done) => {
    let stdout = ''
    let stderr = ''
    let settled = false
    const child = spawn(CURL, args, { stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true })

    const timer = setTimeout(() => {
      if (settled) return
      settled = true
      child.kill()
      done({ status: null, httpCode: null, stderr: 'watchdog timeout' })
    }, (MAX_TIME + 120) * 1000)

    child.stdout.on('data', (chunk) => { stdout += chunk.toString() })
    child.stderr.on('data', (chunk) => { stderr += chunk.toString() })
    child.on('error', (error) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      done({ status: null, httpCode: null, stderr: error.message })
    })
    child.on('close', (status) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      const match = /(\d{3})\s*$/.exec(stdout.trim())
      done({ status, httpCode: match ? Number(match[1]) : null, stderr })
    })
  })
}

function classify(result) {
  if (result.status === 0) return 'ok'
  if (result.status === 33) return 'range-unsupported'
  const code = result.httpCode
  if (code === 404 || code === 410) return 'gone'
  if (code === 401 || code === 403) return 'denied'
  if (code === 429) return 'throttled'
  if (code !== null && code >= 500) return 'server'
  if (result.status !== null && RETRYABLE_EXIT.has(result.status)) return 'network'
  return 'other'
}

function markUnavailable(slug, map, reason) {
  manifest.unavailable[slug] = {
    name: map.name || 'unknown',
    reason,
    at: new Date().toISOString(),
  }
  delete manifest.failed[slug]
  markDirty()
  stats.unavailable += 1
  log(`UNAVAILABLE ${slug} ${reason}`)
}

async function downloadOne({ map, slug, dest }, position, total) {
  const url = `https://dl.mtavault.com/map/${encodeURIComponent(slug)}`
  const part = `${dest}.part`
  let resume = resumeSupported !== false && existsSync(part) && statSync(part).size > 0
  let rangeRetried = false

  log(`START ${position}/${total} ${slug}${resume ? ' resume' : ''}`)

  for (let attempt = 1; attempt <= ATTEMPTS; attempt += 1) {
    if (aborted) return false
    if (!resume && existsSync(part) && statSync(part).size === 0) rmSync(part, { force: true })

    const result = await runCurl(curlArgs(part, url, resume && resumeSupported !== false))
    const kind = classify(result)

    if (kind === 'ok') {
      const check = inspectZip(part, { full: true })
      if (check.ok) {
        renameSync(part, dest)
        const digest = await hashFile(dest)
        manifest.downloaded[slug] = {
          name: map.name,
          id: map.id,
          file: `${slug}.zip`,
          bytes: check.size,
          sha256: digest,
        }
        delete manifest.failed[slug]
        delete manifest.unavailable[slug]
        markDirty()
        saveManifest()
        stats.ok += 1
        stats.bytes += check.size
        consecutiveNetworkErrors = 0
        log(`OK ${slug} bytes=${check.size} sha256=${digest}`)
        return true
      }
      log(`INVALID ${slug} attempt=${attempt}: ${check.error}`)
      rmSync(part, { force: true })
      resume = false
      continue
    }

    if (kind === 'range-unsupported') {
      if (!rangeRetried && resume) {
        rangeRetried = true
        resumeSupported = false
        resume = false
        log(`RANGE UNSUPPORTED ${slug}; 关闭续传，从头下载`)
        attempt -= 1
        continue
      }
      log(`CURL FAIL ${slug} attempt=${attempt}: ${(result.stderr || '').trim()}`)
    } else {
      log(`CURL FAIL ${slug} attempt=${attempt} http=${result.httpCode ?? '-'} exit=${result.status ?? '-'}: ${(result.stderr || '').trim()}`)
    }

    if (kind === 'network' || result.status === null) {
      consecutiveNetworkErrors += 1
      if (consecutiveNetworkErrors >= 40) {
        aborted = true
        log('ABORT 连续 40 次网络失败，停止本轮（检查代理/网络后重跑即可续传）')
        return false
      }
    } else {
      consecutiveNetworkErrors = 0
    }

    if (kind === 'gone' || kind === 'denied') {
      markUnavailable(slug, map, `HTTP ${result.httpCode}`)
      return false
    }
    // 5xx 连续三次仍失败，记为 unavailable，避免每轮反复请求
    if (kind === 'server' && attempt >= 2) {
      markUnavailable(slug, map, `HTTP ${result.httpCode}`)
      return false
    }
    if (kind === 'throttled') {
      await sleep(20_000 + Math.floor(Math.random() * 10_000))
    } else if (attempt < ATTEMPTS) {
      await sleep(1000 * attempt + Math.floor(Math.random() * 750))
    }
    // 超时/中断可能留下半包，下一轮才谈续传
    resume = resumeSupported !== false && existsSync(part) && statSync(part).size > 0
  }

  manifest.failed[slug] = map.name || 'unknown'
  markDirty()
  saveManifest()
  stats.failed += 1
  log(`FAILED ${slug} part kept=${existsSync(part) ? statSync(part).size : 0}`)
  return false
}

async function runQueue(queue) {
  let next = 0

  const worker = async (workerId) => {
    while (!aborted) {
      const index = next
      next += 1
      if (index >= queue.length) return
      await downloadOne(queue[index], index + 1, queue.length)
      stats.done += 1
      await sleep(120)
    }
  }

  const ticker = setInterval(() => {
    saveManifest()
    const elapsed = Math.max((Date.now() - stats.startedAt) / 1000, 1)
    const ratePerMin = (stats.ok / elapsed) * 60
    const remaining = queue.length - stats.done
    log(
      `PROGRESS ${stats.done}/${queue.length} ok=${stats.ok} fail=${stats.failed} unavailable=${stats.unavailable}` +
        ` MB=${(stats.bytes / 1024 / 1024).toFixed(1)} filesPerMin=${ratePerMin.toFixed(1)}` +
        ` etaMin=${ratePerMin > 0 ? Math.round(remaining / ratePerMin) : -1}`,
    )
  }, 30_000)

  try {
    await Promise.all(
      Array.from({ length: Math.min(OPTIONS.concurrency, Math.max(1, queue.length)) }, (_, i) => worker(i + 1)),
    )
  } finally {
    clearInterval(ticker)
  }
}

// ── 队列构建与主流程 ────────────────────────────────────────────────────

function quarantine(file, reason) {
  const target = `${file}.bad-${new Date().toISOString().replace(/[:.]/g, '-')}`
  try {
    renameSync(file, target)
    log(`QUARANTINE ${basename(file)} -> ${basename(target)} (${reason})`)
    return true
  } catch (error) {
    log(`QUARANTINE FAILED ${basename(file)}: ${error.message}`)
    return false
  }
}

function rememberExisting(slug, map) {
  if (!manifest.downloaded[slug] && !manifest.skipped[slug]) {
    manifest.downloaded[slug] = { name: map.name, id: map.id, checked: true }
    markDirty()
  }
}

function verifyExisting() {
  const files = readdirSync(OUT)
    .filter((name) => name.toLowerCase().endsWith('.zip'))
    .sort()
  log(`VERIFY start files=${files.length} full=${OPTIONS.full}`)
  let bad = 0
  for (let i = 0; i < files.length; i += 1) {
    const result = inspectZip(join(OUT, files[i]), { full: OPTIONS.full })
    if (!result.ok) {
      bad += 1
      log(`VERIFY BAD ${files[i]}: ${result.error}`)
    } else if ((i + 1) % 500 === 0) {
      log(`VERIFY ${i + 1}/${files.length}`)
    }
  }
  log(`VERIFY DONE files=${files.length} bad=${bad}`)
  process.exitCode = bad ? 1 : 0
}

async function main() {
  OPTIONS = parseArgs(process.argv.slice(2))
  if (OPTIONS.help) {
    console.log(HELP)
    return
  }

  OUT = OPTIONS.out
  PROXY = OPTIONS.proxy
  MAX_TIME = OPTIONS.maxTime
  LOG = join(OUT, 'download.log')
  MANIFEST = join(OUT, 'manifest.json')

  if (!existsSync(OUT)) mkdirSync(OUT, { recursive: true })

  if (OPTIONS.verify) {
    log(`verify out=${OUT} full=${OPTIONS.full}`)
    verifyExisting()
    return
  }

  const catalog = JSON.parse(readFileSync(OPTIONS.catalog, 'utf8'))
  const maps = Array.isArray(catalog.maps) ? catalog.maps : []
  manifest = loadManifest()

  log(
    `catalog maps=${maps.length} out=${OUT} proxy=${PROXY || 'off'} concurrency=${OPTIONS.concurrency}` +
      ` maxTime=${MAX_TIME}s onlyMissing=${OPTIONS.onlyMissing}`,
  )

  const queue = []
  let existing = 0

  for (const map of maps) {
    const slug = slugOf(map)
    if (!slug) {
      manifest.failed[String(map.id || map.name)] = 'missing sourceUrl slug'
      markDirty()
      continue
    }

    const dest = join(OUT, `${slug}.zip`)
    if (existsSync(dest)) {
      if (OPTIONS.onlyMissing) {
        existing += 1
        rememberExisting(slug, map)
        continue
      }
      const recorded = manifest.downloaded[slug]
      const sizeMatches = !recorded || !recorded.bytes || recorded.bytes === statSync(dest).size
      const check = inspectZip(dest, { full: !sizeMatches })
      let problem = check.ok ? '' : check.error
      if (!problem && OPTIONS.deep && recorded && recorded.sha256) {
        if ((await hashFile(dest)) !== recorded.sha256) problem = 'sha256 与 manifest 不符'
      }
      if (!problem) {
        existing += 1
        rememberExisting(slug, map)
        continue
      }
      log(`INVALID EXISTING ${slug}.zip: ${problem}`)
      if (!quarantine(dest, problem)) {
        manifest.failed[slug] = map.name || 'unknown'
        markDirty()
        continue
      }
    }

    if (manifest.downloaded[slug] || manifest.skipped[slug]) {
      log(`MANIFEST STALE ${slug}, 文件缺失，重新下载`)
      delete manifest.downloaded[slug]
      delete manifest.skipped[slug]
      markDirty()
    }
    queue.push({ map, slug, dest })
  }

  saveManifest(true)
  log(
    `queue=${queue.length} existing=${existing}` +
      ` downloaded=${Object.keys(manifest.downloaded).length} skipped=${Object.keys(manifest.skipped).length}`,
  )
  if (!queue.length) {
    log('DONE 没有需要下载的文件')
    return
  }

  process.on('SIGINT', () => {
    saveManifest(true)
    log('INTERRUPTED 已保存 manifest，重跑会继续')
    process.exit(130)
  })

  await runQueue(queue)

  saveManifest(true)
  log(
    `DONE downloaded=${Object.keys(manifest.downloaded).length} skipped=${Object.keys(manifest.skipped).length}` +
      ` failed=${Object.keys(manifest.failed).length} unavailable=${Object.keys(manifest.unavailable).length}` +
      ` runOk=${stats.ok} runFail=${stats.failed}`,
  )
  if (Object.keys(manifest.unavailable).length) {
    log(`UNAVAILABLE slugs: ${Object.keys(manifest.unavailable).join(',')}`)
  }
}

main().catch((error) => {
  const text = `[${new Date().toISOString()}] FATAL ${error.stack || error.message}`
  console.error(text)
  try {
    appendFileSync(LOG, `${text}\n`, 'utf8')
  } catch {
    // 目录还没建好时忽略
  }
  process.exitCode = 1
})
