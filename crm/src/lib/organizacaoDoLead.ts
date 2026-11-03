/**
 * A ORGANIZAÇÃO DAS CONVERSAS (Pedro, 03/11/2026): "as conversas na aba Leads estão muito confusas, preciso que tenha uma
 * cor para cada tipo de conversa ... tipos de contato diferentes personalizados ... e misto de leads".
 *
 * Tudo mora em `leads.custom_attributes` (rota /api/leads/[id]/organizar):
 *   tipo_contato        a chave do tipo escolhido à mão (Cliente, Corretor, Proprietário, Administração... editáveis);
 *                       sem escolha, vale o que a lista já sabe (corretor/proprietário do Leads; corretor na Parceria)
 *   mostrar_tambem_em   as OUTRAS abas onde a conversa também aparece ("misto de leads"): a conversa continua sendo da
 *                       linha dela (um lead por linha, crm/CLAUDE.md) e a resposta sai pelo número dela; a outra aba só a
 *                       mostra, com a faixa "Falando pelo número Parceria" / "Conversando pelo número Leads"
 *   mudou_para          ENVIADA para a aba de outro número ("Enviar para Rayssa"; Pedro, 03/11: "quando enviar para o outro
 *                       número ele some da lista do Leads e aparece no outro número, lá em cima, como conversa nova"): some
 *                       da aba da própria linha e aparece só lá, até alguém devolver
 *   dentro_de           os 8 últimos dígitos das conversas em que esta foi posta "dentro" (a setinha da 517), à mão
 * Os tipos ficam em integrations.config.tipos_de_contato da linha Leads (/api/linhas/tipos-de-contato).
 */
import type { LeadWithOwner } from '@/lib/types'
import { getLinhaWhatsapp, type LinhaWhatsapp } from '@/lib/leadChannel'

export interface TipoDeContato { chave: string; nome: string; cor: string }

export const TIPOS_PADRAO: TipoDeContato[] = [
  { chave: 'cliente', nome: 'Cliente', cor: '#2563eb' },
  { chave: 'corretor', nome: 'Corretor', cor: '#7c3aed' },
  { chave: 'proprietario', nome: 'Proprietário', cor: '#d97706' },
  { chave: 'administracao', nome: 'Administração', cor: '#dc2626' },
  { chave: 'equipe', nome: 'Equipe', cor: '#64748b' },
]

/** a aba de cada linha, pelo nome que a equipe usa */
export const NOME_DA_LINHA: Record<LinhaWhatsapp, string> = { oficial: 'Oficial', parceria: 'Parceria', captacao: 'Leads' }

export const LINHAS_MISTAS: LinhaWhatsapp[] = ['parceria', 'captacao']

export function tipoEscolhido(lead: { custom_attributes?: any } | null | undefined): string | null {
  const v = lead?.custom_attributes?.tipo_contato
  return typeof v === 'string' && v ? v : null
}

export function mostrarTambemEm(lead: { custom_attributes?: any } | null | undefined): LinhaWhatsapp[] {
  const v = lead?.custom_attributes?.mostrar_tambem_em
  return Array.isArray(v) ? v.filter((x: unknown): x is LinhaWhatsapp => x === 'parceria' || x === 'captacao' || x === 'oficial') : []
}

export function mudouPara(lead: { custom_attributes?: any } | null | undefined): LinhaWhatsapp | null {
  const v = lead?.custom_attributes?.mudou_para
  return v === 'parceria' || v === 'captacao' || v === 'oficial' ? v : null
}

export function dentroDe(lead: { custom_attributes?: any } | null | undefined): string[] {
  const v = lead?.custom_attributes?.dentro_de
  return Array.isArray(v) ? v.map(String).filter((x) => /^\d{8}$/.test(x)) : []
}

/** A conversa aparece nesta aba: é da linha dela, ou foi posta também aqui (misto). */
export function apareceNaAba(lead: LeadWithOwner, linha: LinhaWhatsapp): boolean {
  const para = mudouPara(lead)
  if (para) return para === linha
  return getLinhaWhatsapp(lead) === linha || mostrarTambemEm(lead).includes(linha)
}

/** Na aba de OUTRA linha, a faixa que diz por qual número a conversa fala (null = está na aba dela). */
export function faixaDeOutraLinha(lead: LeadWithOwner, aba: LinhaWhatsapp | null | undefined): string | null {
  const dela = getLinhaWhatsapp(lead)
  if (!aba || !dela || dela === aba) return null
  return dela === 'captacao' ? 'Conversando pelo número Leads' : `Falando pelo número ${NOME_DA_LINHA[dela]}`
}

export function acharTipo(tipos: TipoDeContato[], chave: string | null | undefined): TipoDeContato | null {
  return (chave && tipos.find((t) => t.chave === chave)) || null
}
