// Renders mockup HTML files to iPhone-sized images (440×956 pt at 3×, like the CI simulator shots).
// Files named sheet-*.html are contact sheets: 1800 px wide, as tall as their content, 1×.
// usage: node render.mjs <chrome-binary> <out-dir> <file.html>...   (writes .jpg)
import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'
import { basename, resolve } from 'node:path'

const [chrome, outDir, ...files] = process.argv.slice(2)
const port = 9300 + Math.floor(Math.random() * 400)
// Web security off so the page can trim logo margins on a canvas (cross-origin artwork).
const proc = spawn(chrome, ['--no-sandbox', '--disable-web-security', `--user-data-dir=/tmp/sbmock-${port}`,
  `--remote-debugging-port=${port}`, '--hide-scrollbars', 'about:blank'], { stdio: 'ignore' })
const sleep = (ms) => new Promise((ok) => setTimeout(ok, ms))
for (let i = 0; i < 50; i++) { try { await fetch(`http://127.0.0.1:${port}/json/version`); break } catch { await sleep(200) } }

for (const file of files) {
  const sheet = basename(file).startsWith('sheet-')
  const landscape = basename(file).includes('player')    // the player is shown sideways
  const target = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: 'PUT' })).json()
  const ws = new WebSocket(target.webSocketDebuggerUrl)
  await new Promise((ok) => ws.addEventListener('open', ok))
  let id = 0
  const call = (method, params = {}) => new Promise((ok) => {
    const n = ++id
    ws.addEventListener('message', function h(e) { const m = JSON.parse(e.data); if (m.id === n) { ws.removeEventListener('message', h); ok(m.result) } })
    ws.send(JSON.stringify({ id: n, method, params }))
  })
  await call('Emulation.setDeviceMetricsOverride', sheet ? { width: 1800, height: 1000, deviceScaleFactor: 1, mobile: false }
                                                         : landscape ? { width: 956, height: 440, deviceScaleFactor: 3, mobile: true }
                                                         : { width: 440, height: 956, deviceScaleFactor: 3, mobile: true })
  await call('Page.enable')
  await call('Page.navigate', { url: 'file://' + resolve(file) })
  await sleep(sheet ? 2500 : 5000)                    // remote artwork, web fonts, logo trimming
  if (sheet) {
    const { cssContentSize } = await call('Page.getLayoutMetrics')
    await call('Emulation.setDeviceMetricsOverride', { width: 1800, height: Math.ceil(cssContentSize.height), deviceScaleFactor: 1, mobile: false })
    await sleep(500)
  }
  const shot = await call('Page.captureScreenshot', { format: 'jpeg', quality: 86 })
  const out = `${outDir}/${basename(file, '.html')}.jpg`
  writeFileSync(out, Buffer.from(shot.data, 'base64'))
  console.log('rendered', out)
  ws.close()
}
proc.kill()
