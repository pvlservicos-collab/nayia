/**
 * A MENSAGEM QUE CHEGOU PEDE GENTE? (Pedro, 04/10/2026: a Rayssa disse que não
 * estava chegando mensagem; perguntado sobre o aviso no celular, escolheu "só o
 * que precisa de gente".)
 *
 * O aviso no celular existia no código avisando TODA mensagem recebida. Medido
 * em 04/10: a Parceria recebe 400 a 600 por dia e a captação 150 a 250, quase
 * tudo respondido pela Nay sozinha. Avisar tudo é o mesmo que não avisar: em um
 * dia ninguém olha mais.
 *
 * Avisa quando quem responde é uma PESSOA:
 *   Parceria   a conversa está fora da aba Todos (Tel, Rayssa, Visitas,
 *              Proprietários, Fechamento -- a mesma conta das abas, em
 *              etapaDaParceria.ts), ou alguém está respondendo à mão (a Nay em
 *              pausa de 30 min).
 *   Captação   o dono está na aba "Com o Tel" (a Nay parou para ele), ou quem
 *              escreveu não é da campanha.
 *   Outras     (API oficial e o que mais houver) sempre: lá ninguém responde
 *              sozinho.
 *
 * Nunca avisa: grupo, os nossos próprios números, a equipe, e a mensagem que só
 * fecha a conversa ("ok", "obrigado", reação).
 *
 * NA DÚVIDA, AVISA: se não deu para ler a Nay (banco fora), o aviso sai. Um
 * aviso a mais custa um olhar; um a menos é a mensagem que ninguém viu.
 *
 * O que ESTE aviso não pega: a mensagem que FAZ a conversa passar para uma
 * pessoa (o corretor confirma a visita, a Nay escala ao Tel). Na hora em que
 * ela chega a Nay ainda está atendendo; quem avisa essa passagem é a própria
 * Nay, pelo WhatsApp. Daí em diante, cada mensagem da conversa avisa.
 */
import type { MarcaDaNay } from '@/lib/tiposNay'
import { abaDaConversa, nayEmPausa } from '@/lib/etapaDaParceria'
import { ehNumeroDaNay, soCortesia } from '@/lib/esperaResposta'

export interface MensagemParaAvisar {
  /** integrations.type da linha do lead */
  linha: string | null
  grupo: boolean
  telefone: string | null
  texto: string | null
  midia: string | null
  customAttributes: any
  /** Parceria: a marca da Nay. undefined = a Nay não conhece a pessoa; null = não consegui ler. */
  marca?: MarcaDaNay | null
  /** Captação: as abas do dono. undefined = não é da campanha; null = não consegui ler. */
  abasDoDono?: string[] | null
}

export const LINHA_DA_PARCERIA = 'whatsapp_zapi'
export const LINHA_DA_CAPTACAO = 'whatsapp_zapi_captacao'

/** O que nunca avisa, e se sabe sem perguntar nada à Nay. Devolve o motivo, ou null. */
export function nuncaAvisa(m: Pick<MensagemParaAvisar, 'grupo' | 'telefone' | 'texto' | 'midia'>): string | null {
  if (m.grupo) return 'grupo'
  if (ehNumeroDaNay(m.telefone)) return 'número nosso'
  if (!m.midia && soCortesia(m.texto)) return 'só fecha a conversa'
  return null
}

export function precisaDeGente(m: MensagemParaAvisar): { avisar: boolean; motivo: string } {
  const nunca = nuncaAvisa(m)
  if (nunca) return { avisar: false, motivo: nunca }

  if (m.linha === LINHA_DA_PARCERIA) {
    if (m.marca === null) return { avisar: true, motivo: 'não consegui ler a Nay' }
    const marca = m.marca ?? undefined
    if (marca?.equipe) return { avisar: false, motivo: 'equipe' }
    const aba = abaDaConversa({ custom_attributes: m.customAttributes }, marca)
    if (aba !== 'todos') return { avisar: true, motivo: `aba ${aba}` }
    if (nayEmPausa(marca)) return { avisar: true, motivo: 'alguém está respondendo à mão' }
    return { avisar: false, motivo: 'a Nay atende' }
  }

  if (m.linha === LINHA_DA_CAPTACAO) {
    if (m.abasDoDono === null) return { avisar: true, motivo: 'não consegui ler a captação' }
    if (m.abasDoDono === undefined) return { avisar: true, motivo: 'não é da campanha' }
    if (m.abasDoDono.includes('com_o_tel')) return { avisar: true, motivo: 'com o Tel' }
    return { avisar: false, motivo: 'a Nay da captação atende' }
  }

  return { avisar: true, motivo: 'linha sem Nay' }
}
