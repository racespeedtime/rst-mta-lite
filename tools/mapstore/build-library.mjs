// 把地图 zip 展开成「按需地图库」，供 rst_ui 在换图时复制进运行槽位。
//
// 为什么需要这一步：
//   MTA 启动时会加载 resources/ 下的每个 resource，并对 meta.xml 里声明的
//   每个文件算 MD5（CResource::GenerateChecksums），zip resource 还会先整包
//   解压到 resource-cache/unzipped。4486 张地图 = 约 26 GB，每次开服都要
//   读一遍，所以地图不能作为 4486 个 resource 摆在 resources/ 里。
//
// 本脚本把 zip 解到单个数据 resource：
//   server/mods/deathmatch/resources/[rst]/maplib/maps/<map-id>/
//   server/mods/deathmatch/resources/[rst]/maplib/index.json
// maplib 的 meta.xml 不声明任何文件，MTA 启动时只读它的 meta，不会扫描/哈希
// 这 26 GB 内容。
//
// 同时校验每张图的 meta.xml 引用（<map>/<file>/<script>/<config>/<html>），
// 引用缺失文件的图会标记 valid=false，不进地图池——否则运行期装载会失败。
//
//   node tools/mapstore/build-library.mjs --zips server/mods/deathmatch/map-cache/zips
//   node tools/mapstore/build-library.mjs --zips server/mods/deathmatch/resources --move-zips server/mods/deathmatch/map-cache/zips
//   node tools/mapstore/build-library.mjs --only a-new-dawn,silent-hill --force
//
// 参数：
//   --zips <dir>        zip 所在目录（默认 server/mods/deathmatch/map-cache/zips）
//   --out <dir>         地图库目录（默认 server/mods/deathmatch/resources/[rst]/maplib）
//   --only <a,b>        只处理指定地图 id
//   --limit <n>         只处理前 n 张（调试用）
//   --force             已存在的展开目录也重新解压
//   --move-zips <dir>   展开成功后把 zip 移动到该目录（迁移用；同盘是改名，很快）
//   --delete-zips       展开成功后删除源 zip（危险，默认关闭）
//
// 失败/无效地图写进 <out>/build-report.json；修好后重跑即可补上，已展开的图会跳过。

import {
  closeSync,
  existsSync,
  mkdirSync,
  openSync,
  readFileSync,
  readSync,
  readdirSync,
  renameSync,
  rmSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs'
import { inflateRawSync } from 'node:zlib'
import path from 'node:path'

const REPO = process.cwd()
const DEFAULT_ZIPS = path.join(REPO, 'server', 'mods', 'deathmatch', 'map-cache', 'zips')
const DEFAULT_OUT = path.join(REPO, 'server', 'mods', 'deathmatch', 'resources', '[rst]', 'maplib')

// ── 参数 ────────────────────────────────────────────────────────────────

function parseArgs(argv) {
  const options = {
    zips: process.env.MAP_ZIP_DIR || DEFAULT_ZIPS,
    out: DEFAULT_OUT,
    only: [],
    limit: 0,
    force: false,
    moveZips: '',
    deleteZips: false,
  }

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    const next = () => {
      i += 1
      if (i >= argv.length) throw new Error(`${arg} 缺少参数`)
      return argv[i]
    }
    if (arg === '--zips') options.zips = path.resolve(next())
    else if (arg === '--out') options.out = path.resolve(next())
    else if (arg === '--only') options.only = next().split(',').map((v) => v.trim()).filter(Boolean)
    else if (arg === '--limit') options.limit = Number(next()) || 0
    else if (arg === '--force') options.force = true
    else if (arg === '--move-zips') options.moveZips = path.resolve(next())
    else if (arg === '--delete-zips') options.deleteZips = true
    else if (arg === '--help' || arg === '-h') {
      console.log(readFileSync(new URL(import.meta.url), 'utf8').split('\n').slice(0, 36).join('\n'))
      process.exit(0)
    } else {
      throw new Error(`未知参数：${arg}`)
    }
  }

  return options
}

const options = parseArgs(process.argv.slice(2))
const MAPS_DIR = path.join(options.out, 'maps')
const INDEX_PATH = path.join(options.out, 'index.json')
const REPORT_PATH = path.join(options.out, 'build-report.json')

// ── zip 读取（只依赖 node:zlib，与 tools/mtavault/download-all-maps.mjs 同源） ──

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

function readEntry(fd, entry) {
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
  return data
}

// ── meta.xml 解析与校验 ─────────────────────────────────────────────────

function attributesFrom(text) {
  const attributes = {}
  // MTA 的地图 meta 里单引号属性很常见：name='[DM] xxx'
  for (const match of text.matchAll(/([A-Za-z_][\w.-]*)\s*=\s*("([^"]*)"|'([^']*)')/g)) {
    attributes[match[1].toLowerCase()] = match[3] !== undefined ? match[3] : match[4]
  }
  return attributes
}

function attributesOf(text, tagName) {
  const tag = new RegExp(`<${tagName}\\b([^>]*)>`, 'i').exec(text)
  return tag ? attributesFrom(tag[1]) : {}
}

function allTagsOf(text, tagName) {
  return [...text.matchAll(new RegExp(`<${tagName}\\b([^>]*)>`, 'gi'))].map((match) => attributesFrom(match[1]))
}

function decodeEntities(text) {
  return String(text || '')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&')
}

function wildcardToRegExp(pattern) {
  const escaped = pattern.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*').replace(/\?/g, '.')
  return new RegExp(`^${escaped}$`, 'i')
}

// meta.xml 里 src 可能带通配符或前导斜杠，按 Windows 规则（大小写不敏感）匹配展开后的文件
function matchesAny(files, src) {
  const normalized = src.replace(/\\/g, '/').replace(/^\/+/, '')
  if (normalized.includes('*') || normalized.includes('?')) {
    const regex = wildcardToRegExp(normalized)
    return files.some((file) => regex.test(file))
  }
  const lower = normalized.toLowerCase()
  return files.some((file) => file.toLowerCase() === lower)
}

const REFERENCE_TAGS = ['map', 'file', 'script', 'config', 'html']

function inspectMeta(metaText, files) {
  const missing = []
  for (const tag of REFERENCE_TAGS) {
    for (const attributes of allTagsOf(metaText, tag)) {
      const src = decodeEntities((attributes.src || '').trim())
      if (!src) {
        if (tag === 'map') missing.push('<map> 缺少 src')
        continue
      }
      if (!matchesAny(files, src)) missing.push(`${tag}: ${src}`)
    }
  }

  const info = attributesOf(metaText, 'info')
  const mapTag = attributesOf(metaText, 'map')
  let mapSrc = decodeEntities(mapTag.src || '').replace(/\\/g, '/').trim()
  if (mapSrc.includes('*') || mapSrc.includes('?')) {
    const regex = wildcardToRegExp(mapSrc)
    mapSrc = files.find((file) => regex.test(file)) || ''
  }
  if (mapSrc) {
    mapSrc = files.find((file) => file.toLowerCase() === mapSrc.toLowerCase()) || mapSrc
  }

  return {
    name: decodeEntities(info.name || '').trim(),
    author: decodeEntities(info.author || '').trim(),
    map: mapSrc,
    dimension: Number(mapTag.dimension) || 0,
    missing,
    valid: missing.length === 0 && mapSrc !== '',
  }
}

// ── 展开一张地图 ────────────────────────────────────────────────────────

function isJunkEntry(name) {
  const lower = name.toLowerCase()
  return (
    name.endsWith('/') ||
    lower.startsWith('__macosx/') ||
    lower.endsWith('/.ds_store') ||
    lower === '.ds_store' ||
    lower.endsWith('/thumbs.db') ||
    lower === 'thumbs.db'
  )
}

function safeRelative(name) {
  const cleaned = name.replace(/\\/g, '/').replace(/^\/+/, '')
  if (!cleaned || cleaned.split('/').includes('..') || /^[A-Za-z]:/.test(cleaned)) {
    throw new Error(`非法路径: ${name}`)
  }
  return cleaned
}

function extractZip(zipPath, targetDir) {
  const size = statSync(zipPath).size
  if (size === 0) throw new Error('空文件')
  const fd = openSync(zipPath, 'r')
  try {
    const eocd = readEocd(fd, size)
    const entries = readCentralEntries(fd, eocd.cdOffset, eocd.cdSize, size).filter(
      (entry) => !isJunkEntry(entry.name),
    )

    // 允许 zip 里多套一层目录，例如 map-name/meta.xml
    const names = entries.map((entry) => safeRelative(entry.name))
    let prefix = ''
    if (!names.includes('meta.xml')) {
      const meta = names.find((name) => name.toLowerCase().endsWith('/meta.xml'))
      if (!meta) throw new Error('zip 里没有 meta.xml')
      prefix = meta.slice(0, -'meta.xml'.length)
    }

    const files = []
    let bytes = 0
    for (const entry of entries) {
      const relative = safeRelative(entry.name)
      if (prefix && !relative.startsWith(prefix)) continue
      const inner = prefix ? relative.slice(prefix.length) : relative
      if (!inner) continue
      const data = readEntry(fd, entry)
      const dest = path.join(targetDir, inner)
      mkdirSync(path.dirname(dest), { recursive: true })
      writeFileSync(dest, data)
      files.push(inner)
      bytes += data.length
    }

    const metaPath = path.join(targetDir, 'meta.xml')
    if (!files.includes('meta.xml') || !existsSync(metaPath)) throw new Error('解出来的文件里没有根目录 meta.xml')
    files.sort()
    writeFileSync(path.join(targetDir, '_files.txt'), `${files.join('\n')}\n`, 'utf8')

    return { files, bytes }
  } finally {
    closeSync(fd)
  }
}

function readFilesList(targetDir) {
  const listPath = path.join(targetDir, '_files.txt')
  if (!existsSync(listPath)) {
    throw new Error('缺少 _files.txt（可加 --force 重新展开）')
  }
  return readFileSync(listPath, 'utf8').split('\n').map((line) => line.trim()).filter(Boolean)
}

// ── 主流程 ──────────────────────────────────────────────────────────────

function formatBytes(bytes) {
  if (bytes >= 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`
  if (bytes >= 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  return `${Math.round(bytes / 1024)} KB`
}

function loadIndex() {
  if (!existsSync(INDEX_PATH)) return { version: 1, maps: [] }
  try {
    const parsed = JSON.parse(readFileSync(INDEX_PATH, 'utf8'))
    if (Array.isArray(parsed.maps)) return parsed
  } catch {
    // 索引损坏时整体重建
  }
  return { version: 1, maps: [] }
}

function saveIndex(index) {
  index.maps.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
  index.generatedAt = new Date().toISOString()
  index.version = 1
  writeFileSync(INDEX_PATH, `${JSON.stringify(index)}\n`, 'utf8')
}

function listZips(dir) {
  return readdirSync(dir)
    .filter((name) => name.toLowerCase().endsWith('.zip'))
    .map((name) => path.join(dir, name))
}

function moveZip(zipPath) {
  if (options.moveZips) {
    mkdirSync(options.moveZips, { recursive: true })
    const dest = path.join(options.moveZips, path.basename(zipPath))
    if (existsSync(dest)) {
      // 备份目录里已有同名 zip：内容大小一致就直接丢掉 resources 里这份
      if (statSync(dest).size === statSync(zipPath).size) {
        unlinkSync(zipPath)
      } else {
        renameSync(dest, `${dest}.old-${Date.now()}`)
        renameSync(zipPath, dest)
      }
    } else {
      renameSync(zipPath, dest)
    }
  } else if (options.deleteZips) {
    unlinkSync(zipPath)
  }
}

function inspectExtracted(id, targetDir, previous) {
  const files = readFilesList(targetDir)
  const metaText = readFileSync(path.join(targetDir, 'meta.xml'), 'utf8')
  const meta = inspectMeta(metaText, files)
  const bytes = previous && typeof previous.bytes === 'number'
    ? previous.bytes
    : files.reduce((sum, file) => {
        try {
          return sum + statSync(path.join(targetDir, file)).size
        } catch {
          return sum
        }
      }, 0)

  return {
    id,
    name: meta.name,
    author: meta.author,
    map: meta.map,
    dimension: meta.dimension,
    bytes,
    files: files.length,
    valid: meta.valid,
    ...(meta.valid ? {} : { missing: meta.missing.slice(0, 12) }),
  }
}

function main() {
  if (!existsSync(options.zips)) {
    console.error(`zip 目录不存在：${options.zips}`)
    process.exit(1)
  }

  mkdirSync(MAPS_DIR, { recursive: true })

  const index = loadIndex()
  const byId = new Map(index.maps.map((entry) => [entry.id, entry]))

  let zips = listZips(options.zips)
  if (options.only.length) {
    const wanted = new Set(options.only)
    zips = zips.filter((zipPath) => wanted.has(path.basename(zipPath, path.extname(zipPath))))
  }
  zips.sort()
  if (options.limit > 0) zips = zips.slice(0, options.limit)

  // 只重算索引（zip 都搬走之后补 valid / 清单）：--only 为空且 zip 目录为空时也能跑
  console.log(`地图库目录：${options.out}`)
  console.log(`zip 来源  ：${options.zips}（${zips.length} 个）`)

  const failures = []
  let extracted = 0
  let refreshed = 0
  let done = 0
  const startedAt = Date.now()

  for (const zipPath of zips) {
    const id = path.basename(zipPath, path.extname(zipPath))
    done += 1
    const targetDir = path.join(MAPS_DIR, id)
    const previous = byId.get(id)
    const alreadyDone = existsSync(path.join(targetDir, 'meta.xml')) && existsSync(path.join(targetDir, '_files.txt'))

    try {
      if (!alreadyDone || options.force) {
        if (existsSync(targetDir)) rmSync(targetDir, { recursive: true, force: true })
        mkdirSync(targetDir, { recursive: true })
        extractZip(zipPath, targetDir)
        extracted += 1
      } else {
        refreshed += 1
      }

      byId.set(id, inspectExtracted(id, targetDir, previous))
      moveZip(zipPath)
    } catch (error) {
      failures.push({ id, error: error.message })
      console.error(`  ✗ ${id}: ${error.message}`)
    }

    if (done % 25 === 0 || done === zips.length) {
      const elapsed = Math.max(1, (Date.now() - startedAt) / 1000)
      const rate = (done / elapsed).toFixed(1)
      const invalid = [...byId.values()].filter((entry) => entry.valid === false).length
      console.log(
        `[${done}/${zips.length}] 展开 ${extracted} · 重算 ${refreshed} · 失败 ${failures.length} · 无效 ${invalid} · ${rate}/s`,
      )
    }
  }

  // 索引只保留展开目录仍然存在的地图；目录被删掉的条目也清掉
  const maps = [...byId.values()].filter((entry) => existsSync(path.join(MAPS_DIR, entry.id, 'meta.xml')))
  index.maps = maps
  saveIndex(index)

  const playable = maps.filter((entry) => entry.valid !== false)
  const invalid = maps.filter((entry) => entry.valid === false)
  const totalBytes = playable.reduce((sum, entry) => sum + (entry.bytes || 0), 0)
  writeFileSync(
    REPORT_PATH,
    `${JSON.stringify(
      {
        generatedAt: new Date().toISOString(),
        maps: maps.length,
        playable: playable.length,
        invalid: invalid.map((entry) => ({ id: entry.id, missing: entry.missing || [] })),
        failures,
      },
      null,
      2,
    )}\n`,
    'utf8',
  )

  console.log('')
  console.log(`地图库条目：${maps.length}（可玩 ${playable.length}，无效 ${invalid.length}，${formatBytes(totalBytes)}）`)
  console.log(`索引文件  ：${INDEX_PATH}`)
  if (invalid.length) console.log(`无效原因  ：见 ${REPORT_PATH}`)
  if (failures.length) console.log(`展开失败  ：${failures.length} 张，详见 ${REPORT_PATH}`)
  if (failures.length || invalid.length) process.exitCode = 2
}

main()
