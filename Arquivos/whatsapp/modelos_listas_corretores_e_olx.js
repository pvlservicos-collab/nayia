// Roda DENTRO do container do CRM:  docker exec -i crm-imobeasy node - conferir                 (só mostra, não envia nada)
//                                    docker exec -i crm-imobeasy node - enviar olx_anuncio_01 ...  (cria na Meta os nomes dados)
//                                    docker exec -i crm-imobeasy node - situacao                  (a categoria e a aprovação DEPOIS da revisão)
// Pedro, 22/10/2026: "cria outros focados em disparo utilidade, eu só disparo utilidade, mas esses novos focados em o
// quanto o cliente conhece nós. Na OLX eu vou chamar ele assim: Olá, você tem um imóvel na OLX (nome do imóvel)? algo
// assim, mais leve. E nas outras listas de corretores ... tem que se apresentar", no molde do cadastro_imobeasy_26 e _10
// (aprovados como Utilidade: título "Cadastro Imobeasy" + cadastro de parceiro pendente + quem somos + botões).
// Todos com o botão "Excluir meu contato" (nay-captacao/atender.py, EXCLUIR_CONTATO: sai da lista, sem resposta).
// Três famílias, pelo quanto a pessoa nos conhece:
//   olx_anuncio_*       lista da OLX (imobiliárias e corretores que anunciam lá): não nos conhecem. {{1}} = o imóvel do anúncio.
//   corretor_cadastro_* corretores dos grupos da Parceria: estão nos grupos, mas parte nunca falou com a gente. {{1}} = nome.
//   parceiro_imovel_*   parceiros fora dos grupos (cadastro antigo): têm imóvel conosco em parceria. {{1}} = nome.
// Criar modelo NÃO manda mensagem a ninguém: entra na fila de aprovação da Meta. A categoria do POST é PROVISÓRIA (11/10).
const token = process.env.META_TOKEN, waba = process.env.META_WABA_ID
const RODAPE = 'Imobeasy'
const SAIR = 'Excluir meu contato'
const OLX = ['Sim, é meu', 'Não é meu', SAIR]
const CORRETOR = ['Pedir imóvel por número', 'Grupo de corretores', SAIR]
const PARCEIRO = ['Disponível', 'Alugado', 'Vendido', SAIR]
const EX_IMOVEL = 'Apartamento com 3 quartos no Adrianópolis'
const EX_NOME = 'Carlos'

const MODELOS = {
  // ── OLX: leve, só o anúncio dele ─────────────────────────────────────────────────────────────────────────────
  olx_anuncio_01: { corpo: 'Olá! O imóvel {{1}}, anunciado na OLX, é seu?', botoes: OLX, ex: EX_IMOVEL },
  olx_anuncio_02: { corpo: 'Olá, tudo bem? Você tem um imóvel na OLX, {{1}}, correto?', botoes: OLX, ex: EX_IMOVEL },
  olx_anuncio_03: { corpo: 'Confirmação de anúncio: o imóvel {{1}}, que está na OLX, é seu?', botoes: OLX, ex: EX_IMOVEL },
  olx_anuncio_04: { corpo: 'Olá! Encontramos o anúncio {{1}} na OLX. Ele é seu?', botoes: OLX, ex: EX_IMOVEL },
  olx_anuncio_05: { corpo: 'Olá, tudo bem? Estou falando com quem anunciou o imóvel {{1}} na OLX?', botoes: OLX, ex: EX_IMOVEL },
  olx_anuncio_06: { corpo: 'Anúncio na OLX: o imóvel {{1}} é seu? Toque em uma das opções.', botoes: OLX, ex: EX_IMOVEL },
  olx_anuncio_07: { corpo: 'Olá! Você anunciou na OLX o imóvel {{1}}? Pode confirmar por aqui.', botoes: OLX, ex: EX_IMOVEL },
  olx_anuncio_08: { corpo: 'Olá, tudo bem? O anúncio {{1}}, publicado na OLX, é seu?', botoes: OLX, ex: EX_IMOVEL },

  // ── corretores dos grupos: apresentação no molde do cadastro_imobeasy_26 e _10 ───────────────────────────────
  corretor_cadastro_01: { cabecalho: 'Cadastro Imobeasy', botoes: CORRETOR, ex: EX_NOME,
    corpo: 'Olá, {{1}}! Você está nos grupos de corretores da Imob Easy e o seu cadastro de corretor parceiro está pendente. Somos uma imobiliária em Manaus e trabalhamos em parceria: o imóvel é nosso, o cliente é seu e a comissão é dividida. Selecione como prefere ser atendido:' },
  corretor_cadastro_02: { cabecalho: 'Cadastro Imobeasy', botoes: CORRETOR, ex: EX_NOME,
    corpo: 'Olá, {{1}}. O seu número está nos grupos de corretores da Imob Easy, imobiliária em Manaus, e o seu cadastro de parceiro ainda não foi concluído. Na parceria, os imóveis da nossa carteira ficam disponíveis para você fechar com o seu cliente. Selecione uma opção:' },
  corretor_cadastro_03: { cabecalho: 'Cadastro Imobeasy', botoes: CORRETOR, ex: EX_NOME,
    corpo: 'Olá, {{1}}! O seu cadastro de corretor parceiro na Imob Easy está pendente de uma escolha. Somos uma imobiliária em Manaus e liberamos os imóveis da nossa carteira para os corretores dos nossos grupos. Selecione como prefere ser atendido:' },
  corretor_cadastro_04: { cabecalho: 'Cadastro Imobeasy', botoes: CORRETOR, ex: EX_NOME,
    corpo: 'Olá, {{1}}. Este é o número de atendimento aos corretores parceiros da Imob Easy, imobiliária em Manaus. O seu cadastro de parceiro foi iniciado pelos nossos grupos. Na parceria, o imóvel é nosso, o cliente é seu e a comissão é dividida. Para concluir, selecione:' },
  corretor_cadastro_05: { cabecalho: 'Cadastro Imobeasy', botoes: CORRETOR, ex: EX_NOME,
    corpo: 'Olá, {{1}}! O seu número foi incluído no cadastro de corretores parceiros da Imob Easy pelos nossos grupos. Somos uma imobiliária em Manaus e trabalhamos em parceria com corretores. Para concluir o cadastro, selecione como prefere receber os imóveis:' },
  corretor_cadastro_06: { cabecalho: 'Cadastro Imobeasy', botoes: CORRETOR, ex: EX_NOME,
    corpo: 'Olá, {{1}}. O seu cadastro de corretor parceiro na Imob Easy aguarda uma confirmação. Somos uma imobiliária em Manaus: você atende o seu cliente com os imóveis da nossa carteira e a comissão é dividida. Selecione uma opção:' },
  corretor_cadastro_07: { cabecalho: 'Cadastro Imobeasy', botoes: CORRETOR, ex: EX_NOME,
    corpo: 'Olá, {{1}}! O seu cadastro de parceiro na Imob Easy, imobiliária em Manaus, está em aberto. Pelos nossos grupos e por este número você recebe os imóveis da nossa carteira para o seu cliente. Conclua tocando abaixo:' },
  corretor_cadastro_08: { cabecalho: 'Cadastro Imobeasy', botoes: CORRETOR, ex: EX_NOME,
    corpo: 'Olá, {{1}}. Confirmação de cadastro de corretor parceiro na Imob Easy, imobiliária em Manaus. Os imóveis da nossa carteira ficam disponíveis para você fechar com o seu cliente, com a comissão dividida. Para ativar, selecione uma opção:' },

  // ── parceiros fora dos grupos: atualização do imóvel em parceria ─────────────────────────────────────────────
  parceiro_imovel_01: { cabecalho: 'Cadastro Imobeasy', botoes: PARCEIRO, ex: EX_NOME,
    corpo: 'Olá, {{1}}! O imóvel que você cadastrou em parceria com a Imob Easy precisa ter a situação atualizada no nosso sistema. Selecione a situação atual:' },
  parceiro_imovel_02: { cabecalho: 'Cadastro Imobeasy', botoes: PARCEIRO, ex: EX_NOME,
    corpo: 'Olá, {{1}}. Atualização de cadastro: consta um imóvel seu em parceria com a Imob Easy, imobiliária em Manaus. Ele continua disponível? Selecione uma opção:' },
  parceiro_imovel_03: { cabecalho: 'Cadastro Imobeasy', botoes: PARCEIRO, ex: EX_NOME,
    corpo: 'Olá, {{1}}! Este é o novo número da Imob Easy para os corretores parceiros. Precisamos atualizar a situação do imóvel cadastrado por você em parceria conosco:' },
  parceiro_imovel_04: { cabecalho: 'Cadastro Imobeasy', botoes: PARCEIRO, ex: EX_NOME,
    corpo: 'Olá, {{1}}. O seu cadastro de parceiro na Imob Easy tem um imóvel registrado e a situação dele está pendente de confirmação. Selecione a situação atual:' },
  parceiro_imovel_05: { cabecalho: 'Cadastro Imobeasy', botoes: PARCEIRO, ex: EX_NOME,
    corpo: 'Olá, {{1}}! Estamos atualizando os imóveis dos corretores parceiros da Imob Easy. O imóvel que consta no seu cadastro de parceiro está:' },
  parceiro_imovel_06: { cabecalho: 'Cadastro Imobeasy', botoes: PARCEIRO, ex: EX_NOME,
    corpo: 'Olá, {{1}}. Confirmação de cadastro: o imóvel que você trouxe em parceria para a Imob Easy segue disponível? Toque na situação atual:' },
}

function modelo(nome) {
  const m = MODELOS[nome]
  const comps = []
  if (m.cabecalho) comps.push({ type: 'HEADER', format: 'TEXT', text: m.cabecalho })
  comps.push({ type: 'BODY', text: m.corpo, example: { body_text: [[m.ex]] } })
  comps.push({ type: 'FOOTER', text: RODAPE })
  comps.push({ type: 'BUTTONS', buttons: m.botoes.map((t) => ({ type: 'QUICK_REPLY', text: t })) })
  return { name: nome, language: 'pt_BR', category: 'UTILITY', components: comps }
}

async function meta(caminho, corpo) {
  const r = await fetch('https://graph.facebook.com/v23.0/' + caminho, {
    method: corpo ? 'POST' : 'GET',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: corpo ? JSON.stringify(corpo) : undefined,
  })
  return r.json()
}

async function main() {
  const modo = process.argv[2] || 'conferir'
  const ja = await meta(waba + '/message_templates?limit=250&fields=name,status,category')
  if (ja.error) console.log('a Meta respondeu à lista de modelos com erro:', ja.error.message)
  const existe = new Map((ja.data || []).map((t) => [t.name, t]))
  if (modo === 'situacao') {
    for (const n of Object.keys(MODELOS)) {
      const t = existe.get(n)
      console.log(n, t ? `${t.status} | ${t.category}` : '(não enviado)')
    }
    return
  }
  const quais = modo === 'enviar' ? process.argv.slice(3) : Object.keys(MODELOS)
  for (const n of quais) {
    if (!MODELOS[n]) { console.log(n, '-> não existe neste arquivo'); continue }
    const m = MODELOS[n]
    console.log(`${n}${m.cabecalho ? ' [' + m.cabecalho + ']' : ''} | botões: ${m.botoes.join(' / ')}\n   ${m.corpo}`)
    if (modo !== 'enviar') continue
    if (existe.has(n)) { console.log('   -> já existe na Meta, não mandei de novo'); continue }
    const r = await meta(waba + '/message_templates', modelo(n))
    console.log('   -> ' + (r.error ? 'RECUSADO: ' + (r.error.error_user_msg || r.error.message) : `enviado: ${r.status} | ${r.category} | id ${r.id}`))
  }
}
main().catch((e) => console.log('falhou:', e.message))
