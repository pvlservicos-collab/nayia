// Helper TEMPORÁRIO pra rodar comandos (com sudo) na VPS via SSH (usa ssh2, instalado só
// localmente com --no-save). Lê host/usuário/senha de env vars, nunca de argumento de
// linha de comando. Manda o comando via STDIN pro bash remoto (em vez de `bash -c "..."`)
// de propósito: com -c, as aspas duplas deixam $(...) e $VAR serem expandidos pelo shell
// do usuário ANTES do sudo rodar (então sem privilégio) — via stdin isso não acontece,
// o conteúdo só é interpretado depois que o bash (já como root) está rodando.
import { Client } from 'ssh2'

const host = process.env.VPS_HOST
const username = process.env.VPS_USER
const password = process.env.VPS_PASS
const command = process.argv[2]
const noSudo = process.argv[3] === '--no-sudo'

if (!host || !username || !password || !command) {
  console.error('uso: VPS_HOST=x VPS_USER=x VPS_PASS=x node scripts/vps-exec.mjs "comando" [--no-sudo]')
  process.exit(1)
}

const conn = new Client()
conn.on('ready', () => {
  const remoteCmd = noSudo ? 'bash -s' : "sudo -S -p '' bash -s"
  conn.exec(remoteCmd, (err, stream) => {
    if (err) { console.error('EXEC ERROR:', err.message); conn.end(); process.exit(1) }
    if (!noSudo) stream.write(password + '\n')
    stream.write(command + '\n')
    stream.end()
    let stdout = '', stderr = ''
    stream.on('close', (code) => {
      if (stdout) console.log(stdout)
      if (stderr) console.error(stderr)
      console.log(`[exit code: ${code}]`)
      conn.end()
      process.exit(code || 0)
    }).on('data', (data) => { stdout += data.toString() })
      .stderr.on('data', (data) => { stderr += data.toString() })
  })
}).on('error', (err) => {
  console.error('CONNECTION ERROR:', err.message)
  process.exit(1)
}).connect({
  host,
  port: 22,
  username,
  password,
  readyTimeout: 20000,
  tryKeyboard: true,
})

conn.on('keyboard-interactive', (name, instructions, lang, prompts, finish) => {
  finish([password])
})
