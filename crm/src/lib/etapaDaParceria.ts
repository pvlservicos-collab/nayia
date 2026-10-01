/**
 * A ETAPA DE UMA CONVERSA DA PARCERIA (Tel, 30/09/2026).
 *
 * Quatro lugares, e a conversa está em UM só -- é o que deixa a lista
 * organizada: "os proprietários não vão aparecer em outras etapas, só ali".
 *
 *   todos         a Nay atende. É onde todo mundo começa e para onde volta.
 *   visitas       o corretor confirmou e a visita passou à Rayssa
 *                 (`visitaRayssa`, migração 197). É temporário: até a hora da
 *                 visita + 120 min, ou quando ela é cancelada/realizada -- aí
 *                 a conversa volta para Todos e a Nay volta a atender.
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
export const DESTINOS_DA_PARCERIA = [...ETAPAS_DA_PARCERIA, 'tel', 'rayssa'] as const
export type DestinoParceria = (typeof DESTINOS_DA_PARCERIA)[number]
export type EtapaParceria = (typeof ETAPAS_DA_PARCERIA)[number]

export const ROTULO_DA_ETAPA: Record<DestinoParceria, string> = {
  todos: 'Todos',
  visitas: 'Visitas',
  proprietarios: 'Proprietários',
  fechamento: 'Fechamento',
  tel: 'Tel',
  rayssa: 'Rayssa',
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

/** A escolha do card dura 7 dias, como a da Nay. Depois ela não conta mais. */
export const VALIDADE_DA_ESCOLHA_MS = 7 * 24 * 3600_000

function escolhaAindaValida(lead: { custom_attributes?: any } | null | undefined, agora = Date.now()): EtapaParceria | null {
  const etapa = etapaEscolhidaAMao(lead)
  if (!etapa) return null
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
