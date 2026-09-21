// Túnel SSH TEMPORÁRIO (dev local) pro Postgres novo na VPS, que não tem porta pública.
// Escuta em 127.0.0.1:<LOCAL_PORT> e encaminha pra <REMOTE_HOST>:<REMOTE_PORT> através
// da conexão SSH (equivalente a `ssh -L`, mas sem precisar de sshpass/chave).
// Uso: VPS_HOST=x VPS_USER=x VPS_PASS=x REMOTE_HOST=10.0.2.5 REMOTE_PORT=5432 LOCAL_PORT=5434 node scripts/vps-tunnel.mjs
import { Client } from 'ssh2'
import net from 'node:net'

const host = process.env.VPS_HOST
const username = process.env.VPS_USER
const password = process.env.VPS_PASS
const remoteHost = process.env.REMOTE_HOST
const remotePort = Number(process.env.REMOTE_PORT)
const localPort = Number(process.env.LOCAL_PORT)

if (!host || !username || !password || !remoteHost || !remotePort || !localPort) {
  console.error('faltam env vars: VPS_HOST, VPS_USER, VPS_PASS, REMOTE_HOST, REMOTE_PORT, LOCAL_PORT')
  process.exit(1)
}

const conn = new Client()

conn.on('ready', () => {
  console.log(`SSH conectado. Túnel pronto: 127.0.0.1:${localPort} -> ${remoteHost}:${remotePort}`)
  const server = net.createServer((localSocket) => {
    localSocket.on('error', (e) => console.error('local socket error:', e.message))
    conn.forwardOut(localSocket.remoteAddress || '127.0.0.1', localSocket.remotePort || 0, remoteHost, remotePort, (err, stream) => {
      if (err) {
        console.error('forwardOut error:', err.message)
        localSocket.end()
        return
      }
      stream.on('error', (e) => console.error('stream error:', e.message))
      localSocket.pipe(stream).pipe(localSocket)
    })
  })
  server.on('error', (e) => console.error('server error:', e.message))
  server.listen(localPort, '127.0.0.1')
}).on('error', (err) => {
  console.error('CONNECTION ERROR:', err.message)
  process.exit(1)
}).connect({ host, port: 22, username, password, readyTimeout: 20000, tryKeyboard: true, keepaliveInterval: 15000 })

conn.on('keyboard-interactive', (name, instructions, lang, prompts, finish) => finish([password]))
