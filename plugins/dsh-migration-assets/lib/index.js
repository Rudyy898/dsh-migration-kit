/**
 * dsh-migration-assets — 跨平台宠物素材桥（dsh-migration-kit 的一部分）
 *
 * 解决 dsh-client-ui-pet 在非 macOS 平台无素材服务的问题：
 * 原 macOS 方案依赖 launchd 常驻进程（127.0.0.1:54123，硬编码绝对路径），
 * Windows / Linux 无法使用。本插件用 DSH 内置 webServer 提供 /media/* 静态路由，
 * 素材文件由安装脚本部署到 <DSH_HOME>/data/pet-assets/（跨平台，无硬编码路径）。
 *
 * Node half：注册 /media 前缀路由，服务素材。
 * Client half：注入 window.__DSH_PROXY_BRIDGE__ = 同源空串，
 *              pet client 的 SPRITE = BRIDGE + "/media/..." 即指向本服务。
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

export const name = 'dsh-migration-assets'
export const inject = ['webServer']

const ROUTE_PREFIX = '/media'

/** 素材根目录：<DSH_HOME>/data/pet-assets（安装脚本部署；DSH_HOME 默认 ~/.dsh）。 */
function assetsRoot(ctx) {
  const home = process.env.DSH_HOME ?? join(fileURLToPath(new URL('.', import.meta.url)), '..', '..', '..', '..')
  return join(home, 'data', 'pet-assets')
}

const MIME = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
  '.json': 'application/json; charset=utf-8',
  '.mp3': 'audio/mpeg',
}

function contentTypeFor(rel) {
  const dot = rel.lastIndexOf('.')
  const ext = dot === -1 ? '' : rel.slice(dot).toLowerCase()
  return MIME[ext] ?? 'application/octet-stream'
}

/** 从 pathname 提取安全相对路径；拒绝 .. / \ / 空段（防穿越）。 */
function sanitize(rel) {
  if (rel === '' || rel.includes('\0')) return null
  const segments = rel.split('/')
  for (const s of segments) {
    if (s === '' || s === '.' || s === '..' || s.includes('\\')) return null
  }
  return rel
}

function apply(ctx) {
  const webServer = typeof ctx.get === 'function' ? ctx.get('webServer') : undefined
  if (webServer === undefined) return

  const root = assetsRoot(ctx)
  ctx.logger?.info?.(`[dsh-migration-assets] serving ${root} at ${ROUTE_PREFIX}/*`)

  webServer.register({
    kind: 'prefix',
    path: ROUTE_PREFIX,
    handler: async (req, res) => {
      if (req.method !== 'GET' && req.method !== 'HEAD') {
        res.writeHead(405)
        res.end()
        return
      }
      let pathname
      try {
        pathname = decodeURIComponent(new URL(req.url ?? '/', 'http://dsh.internal').pathname)
      } catch {
        res.writeHead(400)
        res.end()
        return
      }
      const rel = sanitize(pathname.slice(ROUTE_PREFIX.length + 1))
      if (rel === null) {
        res.writeHead(403)
        res.end()
        return
      }
      try {
        const data = readFileSync(join(root, rel))
        res.writeHead(200, {
          'content-type': contentTypeFor(rel),
          'cache-control': 'public, max-age=31536000, immutable',
          'access-control-allow-origin': '*',
        })
        res.end(data)
      } catch {
        res.writeHead(404)
        res.end()
      }
    },
  })

  // index tap：在 HTML 里注入桥变量（pet client 在 boot 后读它）。
  // 放在 head 开头，先于任何 client module 执行。
  if (typeof webServer.tapIndex === 'function') {
    webServer.tapIndex((html) => {
      const script = '<script>window.__DSH_PROXY_BRIDGE__ = window.__DSH_PROXY_BRIDGE__ || "";</script>'
      const head = html.indexOf('<head>')
      if (head !== -1) return `${html.slice(0, head + 6)}${script}${html.slice(head + 6)}`
      return `${script}${html}`
    })
  }
}

export { apply }
