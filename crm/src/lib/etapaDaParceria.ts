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
 * A ORDEM IMPORTA quando vale mais de uma: proprietário manda sobre tudo (é
 * regra dele); depois fechamento, que é mais adiante que visita -- o checklist
 * costuma vir DEPOIS da visita, e quem está juntando documento não está mais
 * esperando visita.
 *
 * E A MÃO MANDA SOBRE A NAY: o que alguém escolhe no card do lead
 * (`custom_attributes.etapa_parceria`) vale mais que o que a Nay deduziu. Quem
 * está olhando a conversa sabe de coisa que o banco não sabe.
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

export function etapaDaParceria(
  lead: { custom_attributes?: any } | null | undefined,
  marca: MarcaDaNay | undefined,
): EtapaParceria {
  const aMao = etapaEscolhidaAMao(lead)
  if (aMao) return aMao
  if (marca?.proprietario) return 'proprietarios'
  // O André mora em Visitas (Pedro, 30/09): ele acompanha, então está sempre
  // nessa etapa, mesmo sem visita passada à Rayssa no nome dele.
  if (marca?.acompanhante) return 'visitas'
  if (marca?.fechamentoId != null) return 'fechamento'
  if (marca?.visitaRayssa) return 'visitas'
  return 'todos'
}
