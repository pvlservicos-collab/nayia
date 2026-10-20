// Dirige um Chrome sem tela (porta 9333): abre a URL, roda os passos e imprime o que a página devolve.
//   node cdp.js <url> <arquivo de passos .js>
const fs = require('fs')
const [url, passos] = process.argv.slice(2)
const dorme = ms => new Promise(r => setTimeout(r, ms))
async function main() {
  const alvo = await fetch('http://127.0.0.1:9333/json/new?' + encodeURIComponent(url), { method: 'PUT' }).then(r => r.json())
  const ws = new WebSocket(alvo.webSocketDebuggerUrl)
  await new Promise(r => { ws.onopen = r })
  let id = 0
  const espera = new Map()
  const erros = []
  ws.onmessage = e => {
    const m = JSON.parse(e.data)
    if (m.id && espera.has(m.id)) { espera.get(m.id)(m.result || m.error); espera.delete(m.id) }
    if (m.method === 'Runtime.exceptionThrown') erros.push('EXCEÇÃO: ' + (m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text).slice(0, 300))
    if (m.method === 'Runtime.consoleAPICalled' && ['error', 'warning'].includes(m.params.type)) erros.push('console.' + m.params.type + ': ' + m.params.args.map(a => a.value || a.description || '').join(' ').slice(0, 300))
    if (m.method === 'Network.responseReceived' && m.params.response.status >= 400) erros.push('HTTP ' + m.params.response.status + ' ' + m.params.response.url.slice(0, 160))
    if (m.method === 'Network.loadingFailed' && !m.params.canceled) erros.push('FALHOU carregar: ' + m.params.errorText + ' ' + (m.params.requestId || ''))
  }
  const cmd = (method, params = {}) => new Promise(r => { const i = ++id; espera.set(i, r); ws.send(JSON.stringify({ id: i, method, params })) })
  const js = async expr => { const r = await cmd('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true }); return r.exceptionDetails ? 'ERRO: ' + (r.exceptionDetails.exception?.description || r.exceptionDetails.text) : r.result?.value }
  await cmd('Runtime.enable'); await cmd('Network.enable'); await cmd('Page.enable')
  await cmd('Emulation.setDeviceMetricsOverride', { width: Number(process.env.LARG || 1366), height: 900, deviceScaleFactor: 1, mobile: !!process.env.CEL })
  await cmd('Page.reload')
  await dorme(Number(process.env.ESPERA || 9000))
  const digitar = async (seletor, texto) => {
    await js(`(()=>{const e=document.querySelector(${JSON.stringify(seletor)}); if(!e) return 'NAO ACHEI'; e.focus(); e.value=''; return 'ok'})()`)
    for (const ch of texto) await cmd('Input.insertText', { text: ch })
    await dorme(900)
  }
  const tecla = async key => { for (const type of ['keyDown', 'keyUp']) await cmd('Input.dispatchKeyEvent', { type, key, code: key, windowsVirtualKeyCode: key === 'Enter' ? 13 : 0 }) }
  const cliqueReal = async () => {
    const p = await js('window.__cdpClique'); if (!p) return
    for (const type of ['mouseMoved', 'mousePressed', 'mouseReleased']) await cmd('Input.dispatchMouseEvent', { type, x: p[0], y: p[1], button: type === 'mouseMoved' ? 'none' : 'left', clickCount: 1 })
  }
  // `cmd` (o protocolo do Chrome: foto de tela, mouse de verdade) e `require` também vão para os passos (20/10)
  const fn = new Function('js', 'digitar', 'tecla', 'dorme', 'console', 'cliqueReal', 'cmd', 'require',
    'return (async () => {' + fs.readFileSync(passos, 'utf8') + '})()')
  await fn(js, digitar, tecla, dorme, console, cliqueReal, cmd, require)
  console.log('--- erros da página:', erros.length ? '\n' + [...new Set(erros)].join('\n') : 'nenhum')
  await cmd('Page.close'); ws.close()
}
main().catch(e => { console.log('falhou:', e.message); process.exit(1) })
