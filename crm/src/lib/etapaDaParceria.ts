/**
 * A ETAPA DE UMA CONVERSA DA PARCERIA (Tel, 30/09/2026).
 *
 * Quatro lugares, e a conversa está em UM só -- é o que deixa a lista
 * organizada: "os proprietários não vão aparecer em outras etapas, só ali".
 *
 *   todos         a Nay atende. É onde todo mundo começa e para onde volta.
 *   visitas       o corretor confirmou e a visita passou à Rayssa
 *                 (`visitaRayssa`, migração 197). Desde a 379 (Pedro, 16/10:
 *                 "ninguém sai de Visitas sozinho") fica até ALGUÉM mudar a
 *                 etapa, mesmo depois da hora da visita (antes: hora + 120
 *                 min). Aí vale a regra da etapa nova: Todos, a Nay atende;
 *                 Proprietários, não. A Nay não tira ninguém de Visitas.
 *                 ATENÇÃO: visita ABERTA não é Visitas. Enquanto a Nay ainda
 *                 coleta e confirma, ela continua atendendo.
 *   proprietarios é dono de imóvel. Nunca aparece em outra etapa.
 *   fechamento    está em `nai_fechamento`: recebeu o checklist e a Nay não
 *                 responde até a Rayssa concluir.
 *
 * A ORDEM IMPORTA quando vale mais de uma: fechamento na frente (é o ponto mais
 * adiante, e o único que alguém abre de propósito -- 01/10, o caso do Ícaro);
 * depois proprietário, que é regra dele; e visita por último -- o checklist
 * costuma vir DEPOIS da visita, e quem está juntando documento não está mais
 * esperando visita.
 *
 * O FATO MANDA, A MÃO NÃO TRANCA (Pedro, 01/10/2026: "não quero isso de escolha
 * à mão ganhar de nada, isso tudo é um estado temporário").
 *
 * Até 01/10 a escolha do card (`custom_attributes.etapa_parceria`) ganhava de
 * tudo e não vencia: quem foi marcado "Todos" uma vez nunca mais aparecia em
 * Visitas, mesmo com visita confirmada -- foi o caso da Solange, com a visita
 * #1062 marcada e o card parado em Todos.
 *
 * Agora: proprietário, acompanhante, fechamento e visita (o que a Nay SABE)
 * decidem sempre. A escolha à mão só preenche o vazio -- quando a Nay não sabe
 * nada -- e vale 7 dias, a mesma validade que a Nay dá à escolha dela
 * (`nai_etapa_manual.valido_ate`, migração 201). Nada aqui é permanente.
 *
 * Escolher "Todos" continua tendo efeito de verdade, e é do lado da Nay:
 * `crm_etapa_manual` conclui o fechamento aberto e tira a marca de humano -- o
 * FATO sai, e a conversa volta para Todos por consequência, não por trava.
 */
import type { MarcaDaNay } from '@/lib/tiposNay'

export const ETAPAS_DA_PARCERIA = ['todos', 'visitas', 'proprietarios', 'fechamento'] as const

/* Tel e Rayssa NÃO são etapas: são pessoas que assumiram a conversa. Mas o
   card manda para lá do mesmo jeito (Tel, 30/09: "preciso que tenha no card do
   lead para eu mandar ele para alguma outra etapa, só copia esse menu"), então
   entram na mesma lista de destinos. Quem está com uma pessoa sai das etapas —
   não está mais no fluxo da Nay. */
/* 02/11 (Pedro: "tira a tag Tel lá da Parceria e põe a tag Lucas"): o card e a aba mostram o Lucas no lugar do Tel.
   'tel' continua reconhecido (escolha antiga, e o Leads ainda tem o Tel), mas não é mais oferecido na Parceria. */
export const DESTINOS_DA_PARCERIA = [...ETAPAS_DA_PARCERIA, 'tel', 'rayssa', 'lucas'] as const
export type DestinoParceria = (typeof DESTINOS_DA_PARCERIA)[number]
export type EtapaParceria = (typeof ETAPAS_DA_PARCERIA)[number]

export const ROTULO_DA_ETAPA: Record<DestinoParceria, string> = {
  todos: 'Todos',
  visitas: 'Visitas',
  proprietarios: 'Proprietários',
  fechamento: 'Fechamento',   // 03/11, à tarde (Pedro): voltou a Fechamento; Administração é o tipo de contato, só do Tel
  tel: 'Tel',
  rayssa: 'Rayssa',
  lucas: 'Lucas',
}

export function escolhaAMao(lead: { custom_attributes?: any } | null | undefined): DestinoParceria | null {
  const v = String(lead?.custom_attributes?.etapa_parceria || '')
  return (DESTINOS_DA_PARCERIA as readonly string[]).includes(v) ? (v as DestinoParceria) : null
}

/** Só a escolha que é ETAPA (Tel e Rayssa ficam de fora: são pessoa). */
export function etapaEscolhidaAMao(lead: { custom_attributes?: any } | null | undefined): EtapaParceria | null {
  const v = escolhaAMao(lead)
  return v && (ETAPAS_DA_PARCERIA as readonly string[]).includes(v) ? (v as EtapaParceria) : null
}

/** A escolha do card dura 7 dias, como a da Nay. Depois ela não conta mais. Visitas não vence (379). */
export const VALIDADE_DA_ESCOLHA_MS = 7 * 24 * 3600_000

function escolhaAindaValida(lead: { custom_attributes?: any } | null | undefined, agora = Date.now()): EtapaParceria | null {
  const etapa = etapaEscolhidaAMao(lead)
  if (!etapa) return null
  // 379 (Pedro, 16/10): ninguém sai de Visitas sozinho; a Nay também deixou de vencer essa escolha
  if (etapa === 'visitas') return etapa
  const em = Date.parse(String(lead?.custom_attributes?.etapa_parceria_em || ''))
  // escolha antiga sem data: conta (é de antes de guardarmos a data)
  if (!Number.isFinite(em)) return etapa
  return agora - em <= VALIDADE_DA_ESCOLHA_MS ? etapa : null
}

export function etapaDaParceria(
  lead: { custom_attributes?: any } | null | undefined,
  marca: MarcaDaNay | undefined,
  agora = Date.now(),
): EtapaParceria {
  /* O QUE A NAY SABE decide, nesta ordem: FECHAMENTO na frente de tudo (ver
     abaixo); depois proprietário, que é regra do Tel; o André mora em Visitas
     porque acompanha; e a visita passada à Rayssa por último.

     FECHAMENTO ANTES DE PROPRIETÁRIO (Pedro, 01/10: "coloco em fechamento e não
     vai o Ícaro"). O Ícaro Correia é dono do 5725, e dono ganhava de tudo: ele
     ia para Proprietários mesmo com o fechamento #6 aberto, e o Fechamento
     ficava vazio. Fechamento é o único estado que ALGUÉM ABRE de propósito, e é
     o ponto mais adiante da jornada -- quem está juntando documento não está
     mais sendo "o dono de um imóvel do catálogo". Também é o mais temporário:
     escolher Todos conclui o fechamento e a pessoa volta a Proprietários
     sozinha, por consequência. */
  if (marca?.fechamentoId != null) return 'fechamento'
  if (marca?.proprietario) return 'proprietarios'
  if (marca?.acompanhante) return 'visitas'
  if (marca?.visitaRayssa) return 'visitas'
  // a Nay não sabe de nada: aí vale o que alguém escolheu, enquanto for recente
  return escolhaAindaValida(lead, agora) ?? 'todos'
}

/**
 * A PAUSA NÃO É "COM O TEL" (Pedro, 03/10/2026). Quando alguém escreve à mão numa
 * conversa, a Nay carimba "o Tel escreveu pelo celular" e fica 30 minutos calada
 * (regra do Tel, 16/09). Até 03/10 essa marca levava a conversa para a aba Tel: ele
 * punha em Todos, respondia a pessoa, e a conversa "voltava" para o Tel -- "coloco
 * para Todos e não salva". Perguntado, escolheu: a Nay continua esperando os 30
 * minutos, mas a conversa FICA NA ABA DELA, com a etiqueta "Nay em pausa". A aba Tel
 * é só do que foi mandado para o Tel, assumido por ele ou escalado.
 *
 * O banco devolve o motivo MAIS FORTE entre as linhas da pessoa (migração 288):
 * `telMotivo` só é o da pausa quando a pausa é o único motivo valendo.
 */
export const MOTIVO_DA_PAUSA = 'o Tel escreveu pelo celular'

type MarcaDoTel = Pick<MarcaDaNay, 'telAtendendo' | 'telMotivo'> | null | undefined

/** A Nay só está esperando os 30 minutos de quem escreveu à mão. */
export function nayEmPausa(m: MarcaDoTel): boolean {
  return !!m?.telAtendendo && m.telMotivo === MOTIVO_DA_PAUSA
}

/** Alguém está com a conversa de verdade (Tel ou Rayssa): mandada, assumida ou escalada. */
export function comAlguemPelaNay(m: MarcaDoTel): boolean {
  return !!m?.telAtendendo && m.telMotivo !== MOTIVO_DA_PAUSA
}

/**
 * EM QUAL ABA DA LISTA A CONVERSA APARECE: a mesma conta do LeadList. Quem está com
 * uma PESSOA (Tel ou Rayssa) sai das etapas; senão vale a etapa (o fato da Nay na
 * frente, a escolha do card só quando ela não sabe de nada). A pausa de 30 minutos
 * não conta como pessoa.
 */
export function abaDaConversa(
  lead: { custom_attributes?: any } | null | undefined,
  marca: MarcaDaNay | undefined,
  agora = Date.now(),
): DestinoParceria {
  // 30/10 (Pedro): Tel e Rayssa só pela escolha À MÃO; a Nay parar porque alguém escreveu não muda a aba
  const aMao = escolhaAMao(lead)
  if (aMao === 'rayssa' || aMao === 'tel' || aMao === 'lucas') return aMao
  return etapaDaParceria(lead, marca, agora)
}

export interface ResultadoDaMudanca {
  /** ok: foi para onde pediram. aviso: salvou, mas ficou em outro lugar (ou a Nay não soube). */
  tom: 'ok' | 'aviso'
  titulo: string
  texto: string
  /** a aba em que a conversa está de verdade, depois de salvar */
  ficou: DestinoParceria
}

const EFEITO_DA_ETAPA: Record<DestinoParceria, string> = {
  todos: 'A Nay volta a atender essa conversa. Se alguém escrever nela à mão (celular ou CRM), a Nay espera 30 minutos antes de responder; a conversa continua nesta aba.',
  visitas: 'Quem atende é a Rayssa; a Nay não responde. Fica em Visitas até alguém mudar a etapa.',
  proprietarios: 'A Nay não responde essa conversa.',
  fechamento: 'Quem atende é a Rayssa, até ela concluir o fechamento.',
  tel: 'A Nay não responde até o Tel devolver a conversa.',
  rayssa: 'A Nay não responde até a conversa voltar para Todos.',
  lucas: 'A Nay não responde até a conversa voltar para Todos.',
}

/** O fato que segura a conversa numa aba, em uma frase (sem ponto final). */
function oQueSegura(ficou: DestinoParceria, m: MarcaDaNay | undefined): string {
  if (ficou === 'fechamento') return 'tem um fechamento aberto (o checklist foi pedido ou enviado)'
  if (ficou === 'proprietarios') {
    if (!m?.proprietario) return 'alguém escolheu Proprietários no card há menos de 7 dias'
    const imoveis = m.imoveisDoDono?.length ? ` (${m.imoveisDoDono.length === 1 ? 'imóvel' : 'imóveis'} ${m.imoveisDoDono.slice(0, 3).join(', ')})` : ''
    return `é proprietário${imoveis}, e dono de imóvel aparece só em Proprietários`
  }
  if (ficou === 'visitas') {
    if (m?.acompanhante) return 'é quem acompanha as visitas, e fica sempre em Visitas'
    if (m?.visitaRayssa) {
      return `tem visita confirmada com a Rayssa${m.visitaId ? ` (visita #${m.visitaId})` : ''}; `
        + 'fica em Visitas até alguém mudar a etapa (ou excluir a visita na agenda)'
    }
    return 'alguém escolheu Visitas no card, e fica até alguém mudar a etapa'
  }
  if (ficou === 'tel') return `a Nay marca que o Tel está com essa conversa${m?.telMotivo ? ` (${m.telMotivo})` : ''}`
  if (ficou === 'rayssa') return 'a Nay marca que a Rayssa está com essa conversa'
  if (ficou === 'lucas') return 'a Nay marca que o Lucas está com essa conversa'
  return 'não há visita, fechamento, nem imóvel dele que a prenda em outra etapa'
}

/**
 * O QUE ACONTECEU DEPOIS DE SALVAR A ETAPA (Pedro, 03/10/2026): "coloca um aviso claro
 * quando eu mudar o status de um contato... tem uns que eu coloco para Todos e não
 * salva; põe uma notificaçãozinha".
 *
 * Salvava, mas a tela não dizia nada -- e quando um FATO da Nay segura a conversa (é
 * proprietário, tem visita confirmada com a Rayssa, tem fechamento aberto) ela
 * continua na mesma aba, que é a regra de 01/10 ("o fato manda, a mão não tranca").
 * Para quem clicou, isso é "não salvou". Aqui sai a frase certa para cada caso: foi,
 * ou não foi e por quê. `lead` e `marca` são os de DEPOIS de salvar.
 */
export function resultadoDaMudanca(
  pedido: DestinoParceria,
  lead: { custom_attributes?: any } | null | undefined,
  marca: MarcaDaNay | undefined,
  nayRecebeu: boolean,
  agora = Date.now(),
): ResultadoDaMudanca {
  const ficou = abaDaConversa(lead, marca, agora)
  const semANay = nayRecebeu ? '' : ' A Nay não confirmou a mudança do lado dela: salve de novo em alguns segundos.'
  if (ficou === pedido) {
    return nayRecebeu
      ? { tom: 'ok', titulo: `Movido para ${ROTULO_DA_ETAPA[pedido]}`, texto: EFEITO_DA_ETAPA[pedido], ficou }
      : { tom: 'aviso', titulo: `Movido para ${ROTULO_DA_ETAPA[pedido]}, mas a Nay não foi avisada`,
          texto: 'A lista mudou, mas a Nay pode continuar agindo como antes. Salve de novo em alguns segundos.', ficou }
  }
  const soltou = pedido === 'todos' ? ' O Todos tirou a marca de atendimento por pessoa e concluiu o fechamento aberto, se havia.' : ''
  return {
    tom: 'aviso',
    titulo: `Não foi para ${ROTULO_DA_ETAPA[pedido]}: continua em ${ROTULO_DA_ETAPA[ficou]}`,
    texto: `Motivo: ${oQueSegura(ficou, marca)}.${soltou}${semANay}`,
    ficou,
  }
}
