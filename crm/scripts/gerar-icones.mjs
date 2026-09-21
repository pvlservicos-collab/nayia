// Gera todos os ícones do app a partir de um PNG único.
//
// Uso:  node scripts/gerar-icones.mjs [caminho-do-png]
//       (sem argumento, usa public/logos/tita-logo.png)
//
// Rode de novo sempre que a logo mudar — é a única coisa que precisa ser feita,
// e evita alguém trocar a logo do topo e esquecer do ícone do PWA.
//
// sharp é devDependency: só roda aqui, nunca em rota. Por isso não precisa de
// serverExternalPackages no next.config (ver CLAUDE.md) — nada dele é
// empacotado no bundle das rotas.
import sharp from 'sharp'
import { mkdir } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'

const raiz = fileURLToPath(new URL('..', import.meta.url))
const origem = process.argv[2] || `${raiz}public/logos/tita-logo.png`

// Fundo dos ícones opacos. Igual ao --void da marca e ao background_color do
// manifest, pra não aparecer uma borda de cor diferente na tela de início.
const FUNDO = { r: 6, g: 6, b: 6, alpha: 1 }

/**
 * Ícone "maskable" pode ser recortado em círculo, losango ou squircle,
 * dependendo do aparelho. A spec reserva os 40% centrais como zona segura, então
 * a logo entra a 60% do lado e centralizada — assim nenhum recorte a corta.
 */
async function maskable(tamanho, destino) {
  const interno = Math.round(tamanho * 0.6)
  const logo = await sharp(origem).resize(interno, interno, {
    fit: 'contain',
    background: { r: 0, g: 0, b: 0, alpha: 0 },
  }).toBuffer()

  await sharp({
    create: { width: tamanho, height: tamanho, channels: 4, background: FUNDO },
  })
    .composite([{ input: logo, gravity: 'centre' }])
    .png()
    .toFile(destino)
}

/** Ícone comum: a logo ocupa a área toda, fundo transparente. */
async function transparente(tamanho, destino) {
  await sharp(origem)
    .resize(tamanho, tamanho, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png()
    .toFile(destino)
}

/**
 * O iOS ignora transparência e pinta o que for transparente de preto, então o
 * apple-touch-icon já sai com o fundo da marca. Um respiro de 12% evita a logo
 * encostar no arredondamento que o próprio iOS aplica.
 */
async function appleTouch(tamanho, destino) {
  const interno = Math.round(tamanho * 0.76)
  const logo = await sharp(origem).resize(interno, interno, {
    fit: 'contain',
    background: { r: 0, g: 0, b: 0, alpha: 0 },
  }).toBuffer()

  await sharp({
    create: { width: tamanho, height: tamanho, channels: 4, background: FUNDO },
  })
    .composite([{ input: logo, gravity: 'centre' }])
    .png()
    .toFile(destino)
}

await mkdir(`${raiz}public/icons`, { recursive: true })

const feitos = []
async function registrar(nome, promessa) {
  await promessa
  feitos.push(nome)
}

await registrar('icons/icon-192.png', transparente(192, `${raiz}public/icons/icon-192.png`))
await registrar('icons/icon-512.png', transparente(512, `${raiz}public/icons/icon-512.png`))
await registrar('icons/icon-maskable-192.png', maskable(192, `${raiz}public/icons/icon-maskable-192.png`))
await registrar('icons/icon-maskable-512.png', maskable(512, `${raiz}public/icons/icon-maskable-512.png`))
await registrar('icons/apple-touch-icon.png', appleTouch(180, `${raiz}public/icons/apple-touch-icon.png`))

// public/favicon.ico não é gerado aqui: navegador e crawler pedem /favicon.ico
// direto, sem olhar o <link>, e o formato .ico o sharp não escreve. O que vale
// pro favicon é o icons.icon do metadata (src/app/layout.tsx), apontando pro
// icon-192 acima.
//
// Também não geramos src/app/icon.png: a convenção de arquivo do Next perde pro
// `icons` declarado no metadata, então o arquivo ficaria ali sem ninguém servir.

console.log('Ícones gerados a partir de ' + origem.replace(raiz, ''))
for (const f of feitos) console.log('  ' + f)
