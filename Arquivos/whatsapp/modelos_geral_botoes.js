// Modelo GERAL com cada conjunto de botões (Pedro, 23/10/2026): "manda para aprovação esse modelo, mas com todos os
// nossos tipos de botões embaixo, e um botão Excluir meu contato; hoje temos vários botões em vários modelos, quero um
// modelo desse meio geral com cada tipo de conjunto de botão".
// O corpo é o da tela dele (Utilidade, pt_BR), igual em todos: "Olá tudo bem?" / {{1}} / "Obrigado pela atenção!".
// Os conjuntos são os 22 que existiam na Meta em 23/10 (195 modelos), sem repetição: o "Dispon?vel" quebrado é o
// Disponível/Alugado/Vendido, e os 4 que já tinham "Excluir meu contato" são o mesmo conjunto sem ele. Em todos, o
// último botão é "Excluir meu contato". Sem rodapé (a tela dele não tem).
//
// Conferir (sem token):   node Arquivos/whatsapp/modelos_geral_botoes.js conferir
// Dentro do CRM:          ssh nay-srv1894338 'docker exec -i crm-imobeasy node - enviar tudo' < este arquivo
//                         ... node - enviar 1 5 7 | situacao | apagar nome..
// Criar modelo NÃO manda mensagem a ninguém. A categoria do POST é PROVISÓRIA: conferir com `situacao` depois.
const token = process.env.META_TOKEN, waba = process.env.META_WABA_ID
const CORPO = 'Olá tudo bem?\n\n{{1}}\n\nObrigado pela atenção!'
const EXEMPLO = 'Passando para confirmar uma informação com você.'
const EXCLUIR = 'Excluir meu contato'
const CONJUNTOS = {
  1: ['geral_corretor_pedir_grupo', ['Pedir imóvel por número', 'Grupo de corretores']],
  2: ['geral_disponivel_alugado_vendido', ['Disponível', 'Alugado', 'Vendido']],
  3: ['geral_quero_vender_buscando', ['Quero vender ou alugar', 'Estou buscando imóvel', 'Estou sem no momento']],
  4: ['geral_tenho_vender_buscando', ['Tenho p/ vender ou alugar', 'Estou buscando imóvel', 'Estou sem no momento']],
  5: ['geral_outro_imovel', ['Tenho outro imóvel', 'Não tenho outro']],
  6: ['geral_alugado_ou_disponivel', ['Está alugado', 'Está disponível']],
  7: ['geral_anuncio_e_meu', ['Sim, é meu', 'Não é meu']],
  8: ['geral_proprietario_corretor_os_dois', ['Proprietário', 'Corretor', 'Os dois']],
  9: ['geral_proprietario_corretor_nenhum', ['Proprietário', 'Corretor', 'Nenhum dos dois']],
  10: ['geral_cadastro_manter_atualizar', ['Manter ativo', 'Atualizar dados', 'Encerrar cadastro']],
  11: ['geral_pelo_grupo_ou_numero', ['Pelo grupo', 'Por este número']],
  12: ['geral_continuar_atendimento', ['Continuar atendimento']],
  13: ['geral_continua_disponivel', ['Continua disponível', 'Não está disponível']],
  14: ['geral_sim_nao', ['Sim', 'Não']],
  15: ['geral_sim_disponivel_nao_mais', ['Sim, está disponível', 'Não está mais']],
  16: ['geral_disponivel_alugado_foi_vendido', ['Está disponível', 'Está alugado', 'Foi vendido']],
  17: ['geral_quero_ver_agora_nao', ['Quero ver', 'Agora não']],
  18: ['geral_disponivel_alugado_ja_vendi', ['Está disponível', 'Está alugado', 'Já vendi']],
}
const nomeDe = (n) => CONJUNTOS[n][0]
const botoesDe = (n) => [...CONJUNTOS[n][1], EXCLUIR]
const todos = () => Object.keys(CONJUNTOS).map(Number)

function modelo(n) {
  return {
    name: nomeDe(n), language: 'pt_BR', category: 'UTILITY',
    components: [
      { type: 'BODY', text: CORPO, example: { body_text: [[EXEMPLO]] } },
      { type: 'BUTTONS', buttons: botoesDe(n).map((t) => ({ type: 'QUICK_REPLY', text: t })) },
    ],
  }
}

function defeitos(n) {
  const d = []
  for (const b of botoesDe(n)) if (b.length > 25) d.push('botão com mais de 25 caracteres: ' + b)
  if (botoesDe(n).length > 10) d.push('mais de 10 botões')
  if (new Set(botoesDe(n)).size !== botoesDe(n).length) d.push('botão repetido')
  if (!/^[a-z0-9_]+$/.test(nomeDe(n)) || nomeDe(n).length > 512) d.push('nome inválido')
  return d
}

async function meta(caminho, corpo, metodo) {
  const r = await fetch('https://graph.facebook.com/v23.0/' + caminho, {
    method: metodo || (corpo ? 'POST' : 'GET'),
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: corpo ? JSON.stringify(corpo) : undefined,
  })
  return r.json()
}

async function existentes() {
  let url = waba + '/message_templates?limit=250&fields=id,name,status,category'
  const m = new Map()
  while (url) {
    const r = await meta(url)
    for (const t of r.data || []) m.set(t.name, t)
    url = r.paging && r.paging.next ? r.paging.next.replace('https://graph.facebook.com/v23.0/', '') : null
  }
  return m
}

async function main() {
  const modo = process.argv[2] || 'conferir'
  if (modo === 'conferir') {
    console.log(CORPO.replace('{{1}}', '{{1}} (ex.: ' + EXEMPLO + ')') + '\n')
    for (const n of todos()) {
      const d = defeitos(n)
      console.log(`${String(n).padStart(2)} ${nomeDe(n)}${d.length ? ' | DEFEITO: ' + d.join('; ') : ''}\n   [${botoesDe(n).join('] [')}]`)
    }
    return
  }
  if (!token || !waba) { console.log('sem META_TOKEN/META_WABA_ID no ambiente: rode dentro do container do CRM'); return }
  const existe = await existentes()
  if (modo === 'situacao') {
    for (const n of todos()) {
      const t = existe.get(nomeDe(n))
      console.log(nomeDe(n), t ? `${t.status} | ${t.category}` : '(não enviado)')
    }
    return
  }
  if (modo === 'apagar') {
    for (const nome of process.argv.slice(3)) {
      if (!nome.startsWith('geral_')) { console.log(nome, '-> só apago os geral_*'); continue }
      const r = await meta(`${waba}/message_templates?name=${nome}`, null, 'DELETE')
      console.log(nome, '->', r.error ? 'ERRO: ' + (r.error.error_user_msg || r.error.message) : 'apagado')
    }
    return
  }
  if (modo === 'enviar') {
    const args = process.argv.slice(3)
    const quais = args[0] === 'tudo' ? todos() : args.map(Number).filter((n) => CONJUNTOS[n])
    if (!quais.length) { console.log('diga os números (enviar 1 5 7) ou "enviar tudo"'); return }
    for (const n of quais) {
      const d = defeitos(n)
      if (d.length) { console.log(nomeDe(n), '-> NÃO enviado: ' + d.join('; ')); continue }
      if (existe.has(nomeDe(n))) { console.log(nomeDe(n), '-> já existe na Meta, não mandei de novo'); continue }
      const r = await meta(waba + '/message_templates', modelo(n))
      console.log(nomeDe(n), '->', r.error ? 'RECUSADO: ' + (r.error.error_user_msg || r.error.message)
        : `enviado: ${r.status} | ${r.category} (provisória) | id ${r.id}`)
    }
    return
  }
  console.log('modos: conferir | enviar N.. | enviar tudo | situacao | apagar nome..')
}
main().catch((e) => console.log('falhou:', e.message))
