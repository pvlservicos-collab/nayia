// 30/10/2026 (Pedro: "faça uma nova verificação agora, raspagem agora"): os anúncios MAIS RECENTES de Manaus, aluguel e
// venda, de TODOS os anunciantes (dono e profissional) e todos os preços -- para o Cadastrar imóvel pelo link do CRM (535)
// achar o anúncio na base. Cópia do olx_scrape.js de 18/10 (Chrome escondido do Agente OLX, porta 9377), com as
// características do anúncio (campos) guardadas e sem abrir anúncio por anúncio.
// node olx_scrape.js <pasta_saida> [maxPaginas] [amostraDetalhes]
//  - abre cada busca, lê o JSON da lista (self.__next_f, Next.js App Router), pagina com &o=N até totalOfAds
//  - para uma amostra de anúncios abre a página e lê o bloco initial-data (descrição, anunciante, CEP, lat/long...)
const fs = require('fs')
const path = require('path')
const [pasta, maxPagArg, amostraArg] = process.argv.slice(2)
const MAX_PAG = Number(maxPagArg || 100)
const AMOSTRA = Number(amostraArg || 5)
const PORTA = 9377
const dorme = ms => new Promise(r => setTimeout(r, ms))

const BUSCAS = [
  { nome: 'aluguel_recentes', url: 'https://www.olx.com.br/imoveis/aluguel/estado-am/regiao-de-manaus/manaus?sf=1' },
  { nome: 'venda_recentes', url: 'https://www.olx.com.br/imoveis/venda/estado-am/regiao-de-manaus/manaus?sf=1' },
  // a OLX só pagina até a página 100 (5.000 anúncios) por busca: a venda (~13.900) vai em faixas de preço (ps/pe)
  ...[[0, 150000], [150001, 250000], [250001, 350000], [350001, 450000], [450001, 600000], [600001, 850000],
      [850001, 1300000], [1300001, 0]].map(([de, ate]) => ({
    nome: `venda_faixa_${de}_${ate || 'mais'}`,
    url: `https://www.olx.com.br/imoveis/venda/estado-am/regiao-de-manaus/manaus?sf=1&ps=${de}${ate ? '&pe=' + ate : ''}`,
  })),
]

// ---- CDP mínimo
async function abrir(url) {
  const alvo = await fetch(`http://127.0.0.1:${PORTA}/json/new?` + encodeURIComponent(url), { method: 'PUT' }).then(r => r.json())
  const ws = new WebSocket(alvo.webSocketDebuggerUrl)
  await new Promise((ok, erro) => { ws.onopen = ok; ws.onerror = erro })
  let id = 0; const espera = new Map()
  ws.onmessage = e => { const m = JSON.parse(e.data); if (m.id && espera.has(m.id)) { espera.get(m.id)(m.result || m.error); espera.delete(m.id) } }
  const cmd = (method, params = {}) => new Promise(r => { const i = ++id; espera.set(i, r); ws.send(JSON.stringify({ id: i, method, params })) })
  await cmd('Runtime.enable')
  const avaliar = async js => { const r = await cmd('Runtime.evaluate', { expression: js, awaitPromise: true, returnByValue: true }); return r.result ? r.result.value : null }
  const fechar = async () => { try { await cmd('Page.close') } catch {} ws.close() }
  return { avaliar, fechar }
}
async function esperar(pg, js, tempo = 25000) {
  const fim = Date.now() + tempo
  while (Date.now() < fim) {
    const v = await pg.avaliar(js)
    if (v) return v
    await dorme(500)
  }
  return null
}

// ---- JSON "solto" dentro de uma string: acha o fim do array/objeto que começa em i
function cortarJson(s, i) {
  let prof = 0, emStr = false
  for (let k = i; k < s.length; k++) {
    const c = s[k]
    if (emStr) { if (c === '\\') k++; else if (c === '"') emStr = false; continue }
    if (c === '"') emStr = true
    else if (c === '[' || c === '{') prof++
    else if (c === ']' || c === '}') { prof--; if (prof === 0) return s.slice(i, k + 1) }
  }
  return null
}
function pegarCampo(s, chave) {
  const m = s.match(new RegExp('"' + chave + '":(\\d+|"[^"]*")'))
  return m ? JSON.parse(m[1]) : null
}

function __flightNaPagina() { try {
  const pedacos = []
  for (const sc of document.scripts) {
    const t = sc.textContent || ''
    if (!t.startsWith('self.__next_f.push([1,')) continue
    const m = t.match(/^self\.__next_f\.push\(\[1,("[\s\S]*")\]\)\s*;?\s*$/)
    if (m) { try { pedacos.push(JSON.parse(m[1])) } catch (e) {} }
  }
  if (!pedacos.length && Array.isArray(self.__next_f)) for (const x of self.__next_f) if (x && x[0] === 1 && typeof x[1] === 'string') pedacos.push(x[1])
  const f = pedacos.join('')
  return f.includes('"ads":[') && f.includes('"totalOfAds"') ? f : null
} catch (e) { return null } }
const JS_FLIGHT = '(' + __flightNaPagina.toString() + ')()'
const JS_TITULO = `document.title`

function precoNumero(txt) {
  if (!txt) return null
  const m = String(txt).replace(/\./g, '').match(/(\d+)(?:,(\d+))?/)
  return m ? Number(m[1] + (m[2] ? '.' + m[2] : '')) : null
}
function achatar(a) {
  const props = {}
  for (const p of a.properties || []) props[p.name] = p.value
  return {
    olx_id: a.listId,
    titulo: a.subject,
    preco_texto: a.price || a.priceValue,
    preco: precoNumero(a.price || a.priceValue),
    preco_antigo: a.oldPrice,
    categoria: a.categoryName,
    tipo_negocio: props.real_estate_type || null,
    subtipo: props.re_types || null,
    quartos: props.rooms ? Number(props.rooms) : null,
    banheiros: props.bathrooms ? Number(props.bathrooms) : null,
    vagas: props.garage_spaces ? Number(props.garage_spaces) : null,
    area_m2: props.size ? precoNumero(props.size) : null,
    condominio: props.condominio || null,
    condominio_valor: props.condominio ? precoNumero(props.condominio) : null,
    iptu: props.iptu || null,
    iptu_valor: props.iptu ? precoNumero(props.iptu) : null,
    detalhes_imovel: props.re_features || null,
    detalhes_condominio: props.re_complex_features || null,
    bairro: a.locationDetails ? a.locationDetails.neighbourhood : null,
    municipio: a.locationDetails ? a.locationDetails.municipality : null,
    local: a.location,
    profissional: a.professionalAd,
    anunciante: a.olxPay ? a.olxPay.transactionalSellerName : null,
    nota_google: a.userGoogleRating,
    destaque: a.hasRealEstateHighlight,
    patrocinado: a.isFeatured,
    fixado_no_topo: a.fixedOnTop,
    baixou_preco: a.priceReductionBadge,
    chat: a.isChatEnabled,
    online: a.isOnline,
    data_epoch: a.date,
    data: a.date ? new Date(a.date * 1000).toISOString() : null,
    ultimo_bump_seg: a.lastBumpAgeSecs ? Number(a.lastBumpAgeSecs) : null,
    n_fotos: a.imageCount,
    n_videos: a.videoCount,
    fotos: (a.images || []).map(i => i.original),
    url: a.url,
    campos: props,
  }
}

async function rasparBusca(b) {
  const anuncios = new Map(); const paginas = []
  let total = null, tamPag = 50, n = 1
  while (true) {
    const url = b.url + (n > 1 ? '&o=' + n : '')
    const pg = await abrir(url)
    let flight = null
    try {
      flight = await esperar(pg, JS_FLIGHT)
      if (!flight) {
        const t = await pg.avaliar(JS_TITULO)
        paginas.push({ pagina: n, url, erro: 'sem JSON da lista', titulo: t })
        console.log(`  ${b.nome} p${n}: SEM JSON (${t})`)
        if (/Attention Required|blocked/i.test(t || '')) { console.log('  BLOQUEADO pelo Cloudflare, parando'); break }
        if (n > 1) break
      }
    } finally { await pg.fechar() }
    if (!flight) break
    const i = flight.indexOf('"ads":[')
    const bloco = cortarJson(flight, i + 6)
    const ads = JSON.parse(bloco).filter(a => a && a.listId)
    total = pegarCampo(flight, 'totalOfAds'); tamPag = pegarCampo(flight, 'pageSize') || 50
    let novos = 0
    for (const a of ads) { if (!anuncios.has(a.listId)) { anuncios.set(a.listId, { ...achatar(a), busca: b.nome, pagina: n, posicao: a.position }); novos++ } }
    paginas.push({ pagina: n, url, anuncios: ads.length, novos, total })
    console.log(`  ${b.nome} p${n}/${Math.ceil(total / tamPag)}: ${ads.length} anúncios (${novos} novos), total ${total}`)
    if (ads.length === 0 || n >= Math.ceil(total / tamPag) || n >= MAX_PAG) break
    if (novos === 0 && n > 1) { console.log(`  ${b.nome}: a OLX só repete daqui em diante, parando`); break }
    n++
    await dorme(1500 + Math.random() * 1500)
  }
  return { total, paginas, anuncios: [...anuncios.values()] }
}

function limparHtml(s) { return (s || '').replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]+>/g, '').replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'").trim() }
function acharAd(o) {
  if (o && typeof o === 'object') {
    if (o.listId && o.subject) return o
    for (const v of Object.values(o)) { const r = acharAd(v); if (r) return r }
  }
  return null
}
async function rasparDetalhe(url) {
  const pg = await abrir(url)
  try {
    const dj = await esperar(pg, `(() => { const e = document.getElementById('initial-data'); return e ? e.getAttribute('data-json') : null })()`)
    if (!dj) { const t = await pg.avaliar(JS_TITULO); return { url, erro: 'sem initial-data', titulo: t } }
    const a = acharAd(JSON.parse(dj))
    if (!a) return { url, erro: 'initial-data sem anúncio' }
    const props = {}; for (const p of a.properties || []) props[p.name] = p.value
    const loc = a.location || {}
    const u = a.user || {}
    const valores = {}; for (const v of a.realEstatePriceInfo || []) valores[v.name] = v.value
    return {
      olx_id: a.listId, ad_id: a.adId, titulo: a.subject, rotulo_preco: a.priceLabel, preco_texto: a.priceValue, preco: precoNumero(a.priceValue), preco_antigo: a.oldPrice,
      descricao: limparHtml(a.body), categoria: a.categoryName, profissional: a.professionalAd,
      campos: props, valores,
      anunciante: u.name, anunciante_id_publico: u.publicAccountId, anunciante_user_id: u.userId, conta_pro: u.configs ? u.configs.proAccount : null,
      telefone_mascarado: a.phone ? a.phone.maskedPhone : null, telefone_verificado: a.phone ? a.phone.phoneVerified : null, whatsapp: a.adFeatures ? a.adFeatures.whatsappEnabled : null,
      endereco: loc.address, bairro: loc.neighbourhood, municipio: loc.municipality, uf: loc.uf, cep: loc.zipcode, lat: loc.mapLati, lng: loc.mapLong,
      publicado_em: a.listTime, publicado_epoch: a.origListTime,
      destaque: a.hasRealEstateHighlight, selo: a.imageGalleryBadge ? a.imageGalleryBadge.label : null, zap_id: a.zapListingId || null,
      fotos: (a.images || []).map(i => i.original), n_videos: (a.videos || []).length,
      url: a.friendlyUrl || url,
    }
  } finally { await pg.fechar() }
}

function csv(linhas) {
  const cols = ['busca', 'olx_id', 'titulo', 'preco', 'categoria', 'tipo_negocio', 'subtipo', 'quartos', 'banheiros', 'vagas', 'area_m2', 'condominio_valor', 'iptu_valor', 'bairro', 'anunciante', 'destaque', 'patrocinado', 'baixou_preco', 'preco_antigo', 'data', 'n_fotos', 'detalhes_imovel', 'detalhes_condominio', 'url']
  const esc = v => v == null ? '' : /[;"\n]/.test(String(v)) ? '"' + String(v).replace(/"/g, '""') + '"' : String(v)
  return [cols.join(';'), ...linhas.map(l => cols.map(c => esc(l[c])).join(';'))].join('\n')
}

;(async () => {
  fs.mkdirSync(pasta, { recursive: true })
  const versao = await fetch(`http://127.0.0.1:${PORTA}/json/version`).then(r => r.json()).catch(() => null)
  if (!versao) { console.log('o Chrome do Agente OLX (porta 9377) não está ligado'); process.exit(2) }
  const resumo = []; const todos = []; const detalhes = []
  // 5º argumento: só a busca com esse nome (ex.: venda_recentes), para refazer uma que falhou
  for (const b of BUSCAS.filter((x) => !process.argv[5] || x.nome.startsWith(process.argv[5]))) {
    console.log(`== ${b.nome}`)
    const r = await rasparBusca(b)
    fs.writeFileSync(path.join(pasta, b.nome + '.json'), JSON.stringify(r, null, 1))
    resumo.push({ busca: b.nome, url: b.url, total_olx: r.total, paginas: r.paginas.length, anuncios: r.anuncios.length })
    todos.push(...r.anuncios)
    // amostra de detalhes: os primeiros N da busca
    for (const a of r.anuncios.slice(0, AMOSTRA)) {
      try { const d = await rasparDetalhe(a.url); d.busca = b.nome; detalhes.push(d); console.log(`  detalhe ${a.olx_id}: ${d.erro || (d.anunciante + ' · ' + d.cep + ' · ' + (d.descricao || '').length + ' chars')}`) }
      catch (e) { detalhes.push({ url: a.url, erro: String(e) }) }
      await dorme(1000 + Math.random() * 1000)
    }
  }
  fs.writeFileSync(path.join(pasta, 'todos.json'), JSON.stringify(todos, null, 1))
  fs.writeFileSync(path.join(pasta, 'todos.csv'), '﻿' + csv(todos))
  fs.writeFileSync(path.join(pasta, 'detalhes.json'), JSON.stringify(detalhes, null, 1))
  fs.writeFileSync(path.join(pasta, 'resumo.json'), JSON.stringify(resumo, null, 1))
  console.log(JSON.stringify(resumo, null, 1))
})()
