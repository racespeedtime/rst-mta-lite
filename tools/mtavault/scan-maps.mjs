#!/usr/bin/env node
/**
 * 扫描已安装的 MTA 地图资源，输出可导入的 JSON 目录。
 *
 * 只读取本地资源，不联网。重点提取：
 * - meta.xml 的 info / map / settings
 * - .map 里的 spawnpoint、vehicle、racepickup、marker、object 数量
 * - 是否真的存在 checkpoint（当前竞速排名算法需要）
 *
 * 用法：
 *   node tools/mtavault/scan-maps.mjs \
 *     --root server/mods/deathmatch/resources \
 *     --out server/mods/deathmatch/map-cache/map-catalog.json
 */

import { promises as fs } from 'node:fs'
import { join, relative, resolve } from 'node:path'

function parseArgs(argv) {
  const options = {
    root: resolve(process.cwd(), 'server/mods/deathmatch/resources'),
    out: resolve(process.cwd(), 'server/mods/deathmatch/map-cache/map-catalog.json'),
  }
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    const next = () => {
      i += 1
      if (i >= argv.length) throw new Error(`${arg} 缺少参数`)
      return argv[i]
    }
    if (arg === '--root') options.root = resolve(process.cwd(), next())
    else if (arg === '--out') options.out = resolve(process.cwd(), next())
    else if (arg === '--help' || arg === '-h') options.help = true
    else throw new Error(`未知参数：${arg}`)
  }
  return options
}

const ATTR_RE = /([A-Za-z_:][\w:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')/g

function attrs(tag) {
  const result = {}
  let match
  ATTR_RE.lastIndex = 0
  while ((match = ATTR_RE.exec(tag))) {
    result[match[1]] = match[2] !== undefined ? match[2] : match[3]
  }
  return result
}

function countTag(xml, tag) {
  return (xml.match(new RegExp(`<${tag}\\b`, 'g')) || []).length
}

function collectMarkers(xml) {
  const types = {}
  const re = /<marker\b[^>]*>/g
  let match
  while ((match = re.exec(xml))) {
    const type = attrs(match[0]).type || 'unknown'
    types[type] = (types[type] || 0) + 1
  }
  return { total: Object.values(types).reduce((sum, n) => sum + n, 0), types }
}

function collectPickups(xml) {
  const types = {}
  const re = /<racepickup\b[^>]*>/g
  let match
  while ((match = re.exec(xml))) {
    const type = attrs(match[0]).type || 'unknown'
    types[type] = (types[type] || 0) + 1
  }
  return { total: Object.values(types).reduce((sum, n) => sum + n, 0), types }
}

function collectSpawns(xml) {
  const result = []
  const re = /<spawnpoint\b[^>]*>/g
  let match
  while ((match = re.exec(xml))) {
    const a = attrs(match[0])
    result.push({
      x: Number(a.posX) || 0,
      y: Number(a.posY) || 0,
      z: Number(a.posZ) || 0,
      rotation: Number(a.rotZ) || 0,
      vehicle: Number(a.vehicle) || 0,
    })
  }
  return result
}

function parseSettings(meta) {
  const settings = {}
  const re = /<setting\b[^>]*>/g
  let match
  while ((match = re.exec(meta))) {
    const a = attrs(match[0])
    if (!a.name) continue
    settings[a.name.replace(/^#/, '')] = a.value
  }
  return settings
}

async function walk(dir, result = []) {
  for (const entry of await fs.readdir(dir, { withFileTypes: true })) {
    if (entry.name.startsWith('.') || entry.name === '[rst]') continue
    const path = join(dir, entry.name)
    if (entry.isDirectory()) await walk(path, result)
    else if (entry.name === 'meta.xml') result.push(path)
  }
  return result
}

async function scanMeta(metaPath, root) {
  const resourceDir = resolve(metaPath, '..')
  const meta = await fs.readFile(metaPath, 'utf8')
  const mapMatch = meta.match(/<map\b([^>]*)>/)
  if (!mapMatch) return null

  const mapAttrs = attrs(mapMatch[0])
  const mapSrc = mapAttrs.src
  if (!mapSrc) return null

  const mapPath = join(resourceDir, mapSrc)
  const xml = await fs.readFile(mapPath, 'utf8')
  const infoMatch = meta.match(/<info\b[^>]*>/)
  const info = infoMatch ? attrs(infoMatch[0]) : {}
  const checkpoints = countTag(xml, 'checkpoint')
  const spawns = collectSpawns(xml)
  const markers = collectMarkers(xml)
  const pickups = collectPickups(xml)

  return {
    resource: relative(root, resourceDir) || '.',
    name: info.name || mapSrc,
    author: info.author || '',
    version: info.version || '',
    gamemodes: info.gamemodes || '',
    mapFile: mapSrc,
    spawnpoints: spawns,
    checkpoints,
    markers,
    pickups,
    vehicles: countTag(xml, 'vehicle'),
    objects: countTag(xml, 'object'),
    settings: parseSettings(meta),
    hasFinishData: checkpoints > 0,
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2))
  if (options.help) {
    console.log('node tools/mtavault/scan-maps.mjs [--root <resources>] [--out <json>]')
    return
  }

  const metas = await walk(options.root)
  const maps = []
  for (const metaPath of metas) {
    try {
      const entry = await scanMeta(metaPath, options.root)
      if (entry) maps.push(entry)
    } catch (error) {
      console.error(`[scan] ${metaPath}: ${error.message}`)
    }
  }

  maps.sort((a, b) => a.resource.localeCompare(b.resource))
  const output = {
    scannedAt: new Date().toISOString(),
    root: options.root,
    count: maps.length,
    withFinishData: maps.filter((map) => map.hasFinishData).length,
    maps,
  }

  await fs.mkdir(resolve(options.out, '..'), { recursive: true })
  await fs.writeFile(options.out, `${JSON.stringify(output, null, 2)}\n`, 'utf8')
  console.log(`[scan] ${maps.length} maps, ${output.withFinishData} with checkpoints -> ${options.out}`)
}

main().catch((error) => {
  console.error(`[scan] failed: ${error.stack || error.message}`)
  process.exitCode = 1
})
