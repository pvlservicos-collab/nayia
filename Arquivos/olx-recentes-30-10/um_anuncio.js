// Um anúncio da OLX pelo Chrome escondido do Agente OLX (porta 9377), com a descrição -- para o Cadastrar imóvel pelo
// link do CRM (535) achar um anúncio que a raspagem não pegou (Pedro, 30/10/2026: o Village Park 1516207869).
// node um_anuncio.js <link> <saida.json>   -> o item no formato da carga do Scrap (montar_carga.py / site_scrap_importar)
const fs = require('fs')
const [link, saida] = process.argv.slice(2)
const PORTA = 9377
const dorme = (ms) => new Promise((r) => setTimeout(r, ms))

async function abrir(url) {
  const alvo = await fetch(`http://127.0.0.1:${PORTA}/json/new?` + encodeURIComponent(url), { method: 'PUT' }).then((r) => r.json())
  const ws = new WebSocket(alvo.webSocketDebuggerUrl)
  await new Promise((ok, erro) => { ws.onopen = ok; ws.onerror = erro })
  let id = 0; const espera = new Map()
  ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && espera.has(m.id)) { espera.get(m.id)(m.result || m.error); espera.delete(m.id) } }
  const cmd = (method, params = {}) => new Promise((r) => { const i = ++id; espera.set(i, r); ws.send(JSON.stringify({ id: i, method, params })) })
  await cmd('Runtime.enable')
  const avaliar = async (js) => { const r = await cmd('Runtime.evaluate', { expression: js, awaitPromise: true, returnByValue: true }); return r.result ? r.result.value : null }
  return { avaliar, fechar: async () => { try { await cmd('Page.close') } catch {} ws.close() } }
}
function acharAd(o) {
  if (o && typeof o === 'object') {
    if (o.listId && o.subject) return o
    for (const v of Object.values(o)) { const r = acharAd(v); if (r) return r }
  }
  return null
}
const limparHtml = (s) => (s || '').replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]+>/g, '').replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'").trim()
const numero = (t) => { const m = String(t || '').replace(/\./g, '').match(/(\d+)(?:,(\d+))?/); return m ? Number(m[1] + (m[2] ? '.' + m[2] : '')) : null }

;(async () => {
  const pg = await abrir(link.split('?')[0])
  try {
    let dj = null
    for (let n = 0; n < 50 && !dj; n++) { dj = await pg.avaliar(`(() => { const e = document.getElementById('initial-data'); return e ? e.getAttribute('data-json') : null })()`); if (!dj) await dorme(500) }
    if (!dj) { console.log('ERRO: a página não trouxe o anúncio:', await pg.avaliar('document.title')); process.exit(1) }
    const a = acharAd(JSON.parse(dj))
    if (!a) { console.log('ERRO: a página não tem o anúncio'); process.exit(1) }
    const props = {}; for (const p of a.properties || []) props[p.name] = p.value
    const loc = a.location || {}
    const item = {
      olx_id: a.listId, titulo: a.subject, preco_texto: a.priceValue, preco: numero(a.priceValue), categoria: a.categoryName,
      tipo_negocio: props.real_estate_type || null, subtipo: props.re_types || null,
      quartos: props.rooms ? Number(props.rooms) : null, banheiros: props.bathrooms ? Number(props.bathrooms) : null,
      vagas: props.garage_spaces ? Number(props.garage_spaces) : null, area_m2: props.size ? numero(props.size) : null,
      condominio_valor: props.condominio ? numero(props.condominio) : null, iptu_valor: props.iptu ? numero(props.iptu) : null,
      bairro: loc.neighbourhood || null, cep: loc.zipcode || null, lat: loc.mapLati || null, lng: loc.mapLong || null,
      anunciante: a.user ? a.user.name : null, descricao: limparHtml(a.body),
      fotos: (a.images || []).map((i) => i.original), n_fotos: (a.images || []).length, url: a.friendlyUrl || link.split('?')[0],
      dados: { campos: props, local: [loc.municipality, loc.neighbourhood].filter(Boolean).join(', '),
               tipo_anunciante: a.professionalAd ? 'profissional' : 'particular', busca: 'um_anuncio' },
    }
    fs.writeFileSync(saida, JSON.stringify(item))
    console.log(`ok: ${item.olx_id} · ${item.titulo} · ${item.preco_texto} · ${item.bairro} · ${item.fotos.length} fotos · descrição ${item.descricao.length} letras`)
  } finally { await pg.fechar() }
})()
