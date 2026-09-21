// Helper TEMPORÁRIO pra subir um arquivo local pra VPS via SFTP.
// Uso: VPS_HOST=x VPS_USER=x VPS_PASS=x node scripts/vps-upload.mjs <local> <remoto>
import { Client } from 'ssh2'

const host = process.env.VPS_HOST
const username = process.env.VPS_USER
const password = process.env.VPS_PASS
const [, , localPath, remotePath] = process.argv

if (!host || !username || !password || !localPath || !remotePath) {
  console.error('uso: VPS_HOST=x VPS_USER=x VPS_PASS=x node scripts/vps-upload.mjs <local> <remoto>')
  process.exit(1)
}

const conn = new Client()
conn.on('ready', () => {
  conn.sftp((err, sftp) => {
    if (err) { console.error('SFTP ERROR:', err.message); conn.end(); process.exit(1) }
    sftp.fastPut(localPath, remotePath, (err) => {
      if (err) { console.error('UPLOAD ERROR:', err.message); conn.end(); process.exit(1) }
      console.log(`Enviado: ${localPath} -> ${remotePath}`)
      conn.end()
      process.exit(0)
    })
  })
}).on('error', (err) => {
  console.error('CONNECTION ERROR:', err.message)
  process.exit(1)
}).connect({ host, port: 22, username, password, readyTimeout: 20000, tryKeyboard: true })

conn.on('keyboard-interactive', (name, instructions, lang, prompts, finish) => finish([password]))
