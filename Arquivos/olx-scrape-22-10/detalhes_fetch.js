// Coleta o detalhe (initial-data) de TODOS os anúncios de todos.json por fetch() dentro de uma aba de am.olx.com.br
// no Chrome do agente (porta 9377). Grava em JSONL (retomável): node detalhes_fetch.js <todos.json> <saida.jsonl> [paralelo]
const fs = require('fs')
const [arqTodos, arqSaida, parArg] = process.argv.slice(2)
const PAR = Number(parArg || 3)
const dorme = ms => new Promise(r => setTimeout(r, ms))
const todos = JSON.parse(fs.readFileSync(arqTodos, 'utf8'))
const feitos = new Set()
if (fs.existsSync(arqSaida)) for (const l of fs.readFileSync(arqSaida, 'utf8').split('\n')) { if (l.trim()) { try { feitos.add(JSON.parse(l).olx_id) } catch {} } }
const fila = []; const vistos = new Set()
for (const a of todos) { if (!vistos.has(a.olx_id) && !feitos.has(a.olx_id)) { vistos.add(a.olx_id); fila.push(a) } }
console.log(`faltam ${fila.length} (já feitos ${feitos.size})`)

// roda DENTRO da página: busca o HTML e devolve só o que interessa do initial-data
function naPagina(u) {
  return fetch(u, { credentials: 'include' }).then(async r => {
    const t = await r.text()
    if (r.status !== 200) return { status: r.status, titulo: (t.match(/<title>([^<]*)/) || [])[1] }
    const m = t.match(/id="initial-data"[^>]*data-json="([^"]+)"/)
    if (!m) return { status: r.status, erro: 'sem initial-data', titulo: (t.match(/<title>([^<]*)/) || [])[1] }
    const ta = document.createElement('textarea'); ta.innerHTML = m[1]
    const d = JSON.parse(ta.value)
    const achar = o => { if (o && typeof o === 'object') { if (o.listId && o.subject) return o; for (const v of Object.values(o)) { const x = achar(v); if (x) return x } } return null }
    const a = achar(d); if (!a) return { status: 200, erro: 'sem anúncio' }
    const props = {}; for (const p of a.properties || []) props[p.name] = p.value
    const val = {}; for (const v of a.realEstatePriceInfo || []) val[v.name] = v.value
    const l = a.location || {}, us = a.user || {}
    return { status: 200, olx_id: a.listId, ad_id: a.adId, titulo: a.subject, rotulo_preco: a.priceLabel, preco_texto: a.priceValue, preco_antigo: a.oldPrice,
      descricao: (a.body || '').replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]+>/g, ''), categoria: a.categoryName, profissional: a.professionalAd,
      campos: props, valores: val, anunciante: us.name, anunciante_id: us.publicAccountId, anunciante_user_id: us.userId, conta_pro: us.configs ? us.configs.proAccount : null,
      telefone_mascarado: a.phone ? a.phone.maskedPhone : null, telefone_verificado: a.phone ? a.phone.phoneVerified : null, whatsapp: a.adFeatures ? a.adFeatures.whatsappEnabled : null,
      endereco: l.address, bairro: l.neighbourhood, municipio: l.municipality, uf: l.uf, cep: l.zipcode, lat: l.mapLati, lng: l.mapLong,
      publicado_em: a.listTime, publicado_epoch: a.origListTime, destaque: a.hasRealEstateHighlight, selo: a.imageGalleryBadge ? a.imageGalleryBadge.label : null,
      zap_id: a.zapListingId || null, n_fotos: (a.images || []).length, n_videos: (a.videos || []).length, url: a.friendlyUrl || u }
  }).catch(e => ({ erro: String(e) }))
}

;(async () => {
  const base = 'https://am.olx.com.br/regiao-de-manaus/imoveis/reserva-das-praias-ponta-negra-vendo-alugo-mobiliado-2-qtos-s-1-suite-1-vaga-1544942873'
  const alvo = await fetch('http://127.0.0.1:9377/json/new?' + encodeURIComponent(base), { method: 'PUT' }).then(r => r.json())
  const ws = new WebSocket(alvo.webSocketDebuggerUrl)
  await new Promise(r => { ws.onopen = r })
  let id = 0; const espera = new Map()
  ws.onmessage = e => { const m = JSON.parse(e.data); if (m.id && espera.has(m.id)) { espera.get(m.id)(m.result || m.error); espera.delete(m.id) } }
  const cmd = (method, params = {}) => new Promise(r => { const i = ++id; espera.set(i, r); ws.send(JSON.stringify({ id: i, method, params })) })
  const avaliar = async js => { const r = await cmd('Runtime.evaluate', { expression: js, awaitPromise: true, returnByValue: true, timeout: 60000 }); return r.result ? r.result.value : { erro: JSON.stringify(r).slice(0, 200) } }
  await cmd('Runtime.enable'); await dorme(3000)
  await avaliar('(' + naPagina.toString() + ')')   // só para checar sintaxe
  const titulo = await avaliar('document.title'); console.log('aba:', titulo)
  if (/Attention Required|blocked/i.test(titulo || '')) { console.log('BLOQUEADO'); process.exit(3) }
  const saida = fs.createWriteStream(arqSaida, { flags: 'a' })
  let ok = 0, erros = 0, i = 0; const t0 = Date.now(); let bloqueios = 0
  async function trabalhador() {
    while (i < fila.length) {
      const a = fila[i++]
      const r = await avaliar('(' + naPagina.toString() + ')(' + JSON.stringify(a.url) + ')')
      const linha = { olx_id: a.olx_id, busca: a.busca, ...r }
      if (r && r.status === 200 && !r.erro) ok++; else { erros++; if (r && (r.status === 403 || /blocked/i.test(r.titulo || ''))) bloqueios++ }
      saida.write(JSON.stringify(linha) + '\n')
      if ((ok + erros) % 50 === 0) console.log(`${ok + erros}/${fila.length} ok ${ok} erros ${erros} em ${Math.round((Date.now() - t0) / 1000)} s`)
      if (bloqueios >= 5) { console.log('muitos bloqueios, parando'); i = fila.length }
      await dorme(400 + Math.random() * 600)
    }
  }
  await Promise.all(Array.from({ length: PAR }, trabalhador))
  saida.end()
  console.log(`fim: ok ${ok} erros ${erros} em ${Math.round((Date.now() - t0) / 1000)} s`)
  await cmd('Page.close'); ws.close()
})()
