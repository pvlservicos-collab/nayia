// Recadastra (edita no lugar, mesmo nome) os modelos que saíram SEM o rodapé "Imobeasy". Pedro, 12/10/2026:
// "recadastra esses: captacao_status_novo_numero_2, captacao_status_novo_numero_3, l1_util_16 (...) mas os de
// corretores muda os botões: Entrar no grupo / Pedir pelo número: l1_util_12".
// A Meta deixa editar um modelo aprovado (até 10 vezes por mês); ele volta para revisão com o mesmo nome.
// 16/10 (Pedro: "quero os botões Pedir imóvel por número e embaixo Entrar no grupo de corretores"): este passou de 25
// letras, o limite do botão; ele escolheu "Grupo de corretores". Edição de aprovado: 1 vez a cada 24 h.
//   docker exec -i crm-imobeasy node - ver|editar|situacao [nome ...] < este arquivo      (token no ambiente do CRM)
//   com nome(s), só esses; sem nome, todos do MUDAR (editar todos manda todos de volta para a revisão)
const token = process.env.META_TOKEN, waba = process.env.META_WABA_ID
const H = { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' }
const G = 'https://graph.facebook.com/v23.0'
const RODAPE = { type: 'FOOTER', text: 'Imobeasy' }
const BOTOES_CORRETOR = { type: 'BUTTONS', buttons: ['Pedir imóvel por número', 'Grupo de corretores'].map(t => ({ type: 'QUICK_REPLY', text: t })) }
const MUDAR = {
  captacao_status_novo_numero_2: {},
  captacao_status_novo_numero_3: {},
  l1_util_16: {},
  l1_util_12: { botoes: BOTOES_CORRETOR },
}
async function main() {
  const modo = process.argv[2], nomes = process.argv.slice(3)
  const lista = await fetch(`${G}/${waba}/message_templates?limit=200&fields=id,name,status,category,components`, { headers: H }).then(x => x.json())
  const tem = new Map((lista.data || []).map(t => [t.name, t]))
  for (const [name, m] of Object.entries(MUDAR)) {
    if (nomes.length && !nomes.includes(name)) continue
    const t = tem.get(name)
    if (!t) { console.log(name, '-> não existe na Meta'); continue }
    if (modo === 'ver') { console.log(name, t.id, t.status, t.category, JSON.stringify(t.components)); continue }
    if (modo === 'editar') {
      const comps = t.components.filter(c => c.type !== 'FOOTER' && (!m.botoes || c.type !== 'BUTTONS'))
      const corpoI = comps.findIndex(c => c.type === 'BODY')
      comps.splice(corpoI + 1, 0, RODAPE)
      if (m.botoes) comps.push(m.botoes)
      const r = await fetch(`${G}/${t.id}`, { method: 'POST', headers: H, body: JSON.stringify({ components: comps }) }).then(x => x.json())
      console.log(name, '->', r.error ? 'ERRO: ' + (r.error.error_user_msg || r.error.message) : 'editado (volta para revisão)')
      continue
    }
    const rodape = (t.components.find(c => c.type === 'FOOTER') || {}).text || '(sem rodapé)'
    const botoes = ((t.components.find(c => c.type === 'BUTTONS') || {}).buttons || []).map(b => b.text).join(' / ')
    console.log(name, '->', t.status, '|', t.category, '| rodapé:', rodape, '| botões:', botoes)
  }
}
main().catch(e => console.log('falhou:', e.message))
