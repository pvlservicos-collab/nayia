// Modelo situacao_imovel_cadastrado_1 (aprovado como Utilidade) com DUAS variáveis: {{1}} nome, {{2}} condomínio,
// rodapé Imobeasy, botões Disponível / Alugado / Vendido. Pedro, 11/10/2026. Mais 2 variações para garantir.
//   docker exec -i crm-imobeasy node - enviar|situacao < este arquivo      (token no ambiente do CRM)
const token = process.env.META_TOKEN, waba = process.env.META_WABA_ID
const H = { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' }
const MODELOS = {
  situacao_condominio_1: 'Olá, {{1}}! Este é o novo número da Imob Easy. Precisamos atualizar a situação do seu imóvel no {{2}}, cadastrado conosco. Por favor, selecione a opção que corresponde à situação atual:',
  situacao_condominio_2: 'Olá, {{1}}! Este é o novo número da Imob Easy. Precisamos atualizar a situação do seu imóvel no {{2}}, que está cadastrado conosco. Por favor, selecione a opção que corresponde à situação atual:',
  situacao_condominio_3: 'Olá, {{1}}. Este é o novo número da Imob Easy. O seu imóvel no {{2}} está cadastrado conosco e precisamos atualizar a situação dele. Selecione a opção que corresponde à situação atual:',
}
const corpo = text => ({ name: '', language: 'pt_BR', category: 'UTILITY', components: [
  { type: 'BODY', text, example: { body_text: [['Pedro', 'Maison Rochelle']] } }, { type: 'FOOTER', text: 'Imobeasy' },
  { type: 'BUTTONS', buttons: ['Disponível', 'Alugado', 'Vendido'].map(t => ({ type: 'QUICK_REPLY', text: t })) } ] })
async function main() {
  const modo = process.argv[2]
  const lista = await fetch(`https://graph.facebook.com/v23.0/${waba}/message_templates?limit=200&fields=name,status,category`, { headers: H }).then(x => x.json())
  const tem = new Map((lista.data || []).map(t => [t.name, t]))
  for (const [name, text] of Object.entries(MODELOS)) {
    if (modo === 'enviar' && !tem.has(name)) {
      const r = await fetch(`https://graph.facebook.com/v23.0/${waba}/message_templates`, { method: 'POST', headers: H, body: JSON.stringify({ ...corpo(text), name }) }).then(x => x.json())
      console.log(name, '->', r.error ? 'ERRO: ' + (r.error.error_user_msg || r.error.message) : `criado: ${r.status} | ${r.category} (provisório)`)
    } else {
      const t = tem.get(name); console.log(name, '->', t ? `${t.status} | ${t.category}` : '(não enviado)')
    }
  }
}
main().catch(e => console.log('falhou:', e.message))
