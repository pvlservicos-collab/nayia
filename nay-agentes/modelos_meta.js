// Lê os modelos da API oficial do WhatsApp (Graph) e imprime o JSON que a aba Captação › Modelos WhatsApp mostra.
// Roda DENTRO do container do CRM, que é quem tem o token (cron nay-agentes: docker exec -i crm-imobeasy node - < este
// arquivo > admin/dados/modelos.json). O token nunca sai do container. Só leitura. Pedro, 12/10/2026.
const token = process.env.META_TOKEN, waba = process.env.META_WABA_ID
async function main() {
  if (!token || !waba) { console.log(JSON.stringify({ erro: 'sem META_TOKEN/META_WABA_ID no CRM', modelos: [] })); return }
  const campos = 'name,language,status,category,components,quality_score,rejected_reason'
  let url = `https://graph.facebook.com/v23.0/${waba}/message_templates?limit=100&fields=${campos}`
  const todos = []
  while (url) {
    const j = await fetch(url, { headers: { Authorization: `Bearer ${token}` } }).then(r => r.json())
    if (j.error) { console.log(JSON.stringify({ erro: j.error.message, modelos: [] })); return }
    todos.push(...(j.data || []))
    url = j.paging && j.paging.next ? j.paging.next : null
  }
  const modelos = todos.map(t => {
    const c = t.components || []
    const pega = tipo => c.find(x => x.type === tipo) || {}
    return {
      nome: t.name, idioma: t.language, status: t.status, categoria: t.category,
      qualidade: t.quality_score && t.quality_score.score, motivo: t.rejected_reason && t.rejected_reason !== 'NONE' ? t.rejected_reason : null,
      cabecalho: pega('HEADER').format === 'TEXT' ? pega('HEADER').text : (pega('HEADER').format ? '[' + pega('HEADER').format + ']' : null),
      corpo: pega('BODY').text || '', rodape: pega('FOOTER').text || null,
      botoes: (pega('BUTTONS').buttons || []).map(b => ({ tipo: b.type, texto: b.text })),
    }
  }).sort((a, b) => (a.status === 'APPROVED' ? 0 : 1) - (b.status === 'APPROVED' ? 0 : 1) || a.nome.localeCompare(b.nome))
  console.log(JSON.stringify({ lido_em: Math.floor(Date.now() / 1000), total: modelos.length, modelos }))
}
main().catch(e => console.log(JSON.stringify({ erro: e.message, modelos: [] })))
