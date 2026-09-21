/**
 * Simulação da conversa aberta no chat — `node scripts/simular-selecao-chat.mjs`.
 *
 * Existe porque o mesmo bug voltou três vezes: clicar numa conversa e a tela
 * abrir outra, ou congelar na anterior, ou não abrir nada. A causa era sempre a
 * mesma família de corrida entre a seleção (estado do React) e o `?leadId=` do
 * endereço — e ela NÃO aparece em checagem de tipo nem no build. Só clicando, e
 * nem sempre.
 *
 * O desenho atual (src/app/(authenticated)/chat/page.tsx) tem UMA fonte de
 * verdade: o que a pessoa escolheu. O endereço é só entrada, e o clique não
 * escreve nele. Este arquivo modela exatamente isso e passa os cenários que
 * quebraram na prática, inclusive os dois defeitos do navegador que tornavam
 * tudo pior:
 *
 *   - `searchParams` chega uma renderização DEPOIS da navegação;
 *   - às vezes não chega nunca (o endereço muda na barra e o componente segue
 *     lendo o valor antigo).
 *
 * Mexeu no efeito do `?leadId=` ou em `handleSelectLead`? Rode isto antes de
 * subir. Se a regra voltar a depender do endereço pra saber o que está aberto,
 * algum cenário aqui quebra.
 */

/** A tela, modelada: refs, estado e o efeito do endereço. */
function criarTela({ urlInicial, enderecoSincroniza, leadsEmMemoria }) {
  let selecionado = null
  // O endereço é sempre um PEDIDO: conversa + marca de abertura (src/lib/links.ts).
  let urlReal = urlInicial ? { lead: urlInicial, marca: 'inicial' } : null
  let urlVistaPeloReact = urlReal
  const refs = { ultimaUrlVista: null }
  let proximaMarca = 0

  // Espelho do efeito de verdade.
  const efeitoDoEndereco = () => {
    const pedido = urlVistaPeloReact
    if (!pedido) return
    const chave = `${pedido.lead}|${pedido.marca}`
    if (chave === refs.ultimaUrlVista) return // pedido repetido/atrasado não manda
    refs.ultimaUrlVista = chave
    if (selecionado === pedido.lead) return
    if (leadsEmMemoria.has(pedido.lead)) selecionado = pedido.lead
  }

  const renderizar = () => {
    efeitoDoEndereco()
    if (enderecoSincroniza) urlVistaPeloReact = urlReal
  }

  // Abertura da página: dois quadros, que é o que o React faz na montagem.
  renderizar()
  renderizar()

  return {
    ver: () => selecionado,
    /** A pessoa clica numa conversa da lista. O endereço NÃO é tocado. */
    clicar(lead) {
      selecionado = lead
      renderizar()
      renderizar()
    },
    /** Link do aviso no grupo, "Ver conversa" do Pipeline, busca global. */
    navegarPorLink(lead) {
      // Todo link interno carrega uma marca nova — é o que faz "abrir a mesma
      // conversa de novo" ser um pedido diferente do anterior.
      urlReal = { lead, marca: `m${proximaMarca++}` }
      if (!enderecoSincroniza) urlVistaPeloReact = urlReal // navegação de verdade sempre chega
      renderizar()
      renderizar()
    },
    /** Lista se atualizando sozinha, mensagem chegando, etc. */
    passarTempo(quadros = 5) {
      for (let i = 0; i < quadros; i++) renderizar()
    },
  }
}

const LEADS = new Set(['A', 'B', 'C'])

const CENARIOS = [
  {
    nome: 'abriu por link e clicou em outras conversas',
    urlInicial: 'A',
    passos: [
      ['abertura', null, 'A'],
      ['clicar', 'B', 'B'],
      ['clicar', 'C', 'C'],
      ['tempo', null, 'C'],
      ['clicar', 'A', 'A'],
    ],
  },
  {
    nome: 'abriu sem link e clicou',
    urlInicial: null,
    passos: [
      ['clicar', 'B', 'B'],
      ['tempo', null, 'B'],
      ['clicar', 'C', 'C'],
    ],
  },
  {
    nome: 'clicou, chegou link de outra conversa, clicou de novo',
    urlInicial: 'A',
    passos: [
      ['clicar', 'B', 'B'],
      ['link', 'C', 'C'],
      ['clicar', 'B', 'B'],
      ['tempo', null, 'B'],
    ],
  },
  {
    nome: 'clicou na mesma conversa duas vezes',
    urlInicial: 'A',
    passos: [
      ['clicar', 'B', 'B'],
      ['clicar', 'B', 'B'],
      ['tempo', null, 'B'],
    ],
  },
  {
    nome: 'link repetido pra conversa que já está aberta',
    urlInicial: 'A',
    passos: [
      ['clicar', 'B', 'B'],
      ['link', 'A', 'A'],
      ['link', 'A', 'A'],
      ['clicar', 'C', 'C'],
    ],
  },
]

let falhas = 0

for (const sincroniza of [true, false]) {
  console.log(`\n### endereço ${sincroniza ? 'acompanha' : 'NÃO acompanha (defeito do navegador)'}`)
  for (const cenario of CENARIOS) {
    const tela = criarTela({
      urlInicial: cenario.urlInicial,
      enderecoSincroniza: sincroniza,
      leadsEmMemoria: LEADS,
    })
    const erros = []
    for (const [acao, alvo, esperado] of cenario.passos) {
      if (acao === 'clicar') tela.clicar(alvo)
      else if (acao === 'link') tela.navegarPorLink(alvo)
      else if (acao === 'tempo') tela.passarTempo()
      const visto = tela.ver()
      if (visto !== esperado) {
        erros.push(`${acao}${alvo ? ' ' + alvo : ''}: esperava ${esperado}, ficou em ${visto}`)
      }
    }
    if (erros.length) falhas++
    console.log(`  ${erros.length ? 'FALHA' : 'ok   '} — ${cenario.nome}`)
    for (const erro of erros) console.log(`         ${erro}`)
  }
}

console.log(
  falhas === 0
    ? '\nTodos os cenários passaram: a conversa aberta é sempre a que a pessoa escolheu.'
    : `\n${falhas} cenário(s) falharam.`
)
process.exit(falhas === 0 ? 0 : 1)
