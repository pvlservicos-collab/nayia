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
 *   pessoas             os membros da equipe ADICIONADOS à conversa ("Adicionar pessoa", Pedro, 03/11): no Leads, a conversa
 *                       em Administração só aparece para quem não é administrador se ele estiver aqui, e aí fixada em cima
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

export function pessoasDe(lead: { custom_attributes?: any } | null | undefined): string[] {
  const v = lead?.custom_attributes?.pessoas
  return Array.isArray(v) ? v.map(String) : []
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

/* O TIPO DO LEAD NO PIPELINE (Pedro, 04/11/2026: "embaixo do número do cara uma lista suspensa para mudar o tipo do
   contato, para proprietário ou para corretor, ou para lead de locação ou para lead de vendas, ou para Administração, e
   ele já se organiza com base nisso"). Locação x vendas: a marca à mão (atendimento_locacao, a do Enviar para Diego) vale;
   sem ela, a finalidade que a Nay Leads entendeu (a mesma regra de usePapelDoContato.ehLocacao). */
export type TipoDoLead = '' | 'proprietario' | 'corretor' | 'locacao' | 'vendas' | 'administracao'
export const TIPOS_DO_LEAD: Array<{ chave: Exclude<TipoDoLead, ''>; nome: string }> = [
  { chave: 'locacao', nome: 'Lead de locação' }, { chave: 'vendas', nome: 'Lead de vendas' },
  { chave: 'proprietario', nome: 'Proprietário' }, { chave: 'corretor', nome: 'Corretor' },
  { chave: 'administracao', nome: 'Administração' },
]
/** o que gravar (POST /api/leads/[id]/organizar) para cada escolha */
export const CORPO_DO_TIPO: Record<Exclude<TipoDoLead, ''>, Record<string, unknown>> = {
  locacao: { tipo: 'cliente', locacao: true },
  vendas: { tipo: 'cliente', locacao: false },
  proprietario: { tipo: 'proprietario' },
  corretor: { tipo: 'corretor' },
  administracao: { tipo: 'administracao' },
}
export function ehDeLocacao(lead: { custom_attributes?: any; phone?: string | null },
                            finalidadeDaNay: (fim8: string) => string | null | undefined): boolean {
  const m = lead.custom_attributes?.atendimento_locacao
  if (m === true || m === false) return m
  return finalidadeDaNay(String(lead.phone || '').replace(/\D/g, '').slice(-8)) === 'locacao'
}
/** o tipo de agora: o escolhido à mão; um cliente (ou a conversa do Leads sem tipo) é locação ou vendas */
export function tipoDoLead(lead: { custom_attributes?: any; phone?: string | null }, doLeads: boolean,
                           finalidadeDaNay: (fim8: string) => string | null | undefined): TipoDoLead {
  const t = lead.custom_attributes?.tipo_contato
  if (t === 'proprietario' || t === 'corretor' || t === 'administracao') return t
  if (t === 'cliente' || (!t && doLeads)) return ehDeLocacao(lead, finalidadeDaNay) ? 'locacao' : 'vendas'
  return ''
}
