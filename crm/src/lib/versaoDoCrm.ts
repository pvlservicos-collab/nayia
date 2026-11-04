'use client'

/**
 * A ORGANIZAÇÃO DO CRM, v1 x v2 (Pedro, 03/11/2026). A v1 é a de sempre e não muda. A v2 organiza por etapas:
 *   Captação      o Chat Captação (cadastros incompletos e donos chamados pela OLX)
 *   Atendimento   os dois WhatsApp (Leads e Parceria) para escolher lá em cima; sem os proprietários (eles ficam na aba
 *                 Proprietários). No Leads, a LOCAÇÃO é do Diego: quem a Nay entendeu como locação e quem a equipe
 *                 mandou com o botão "Mandar para locação"
 *   Visita        quem está na etapa visita, dos dois números (com a faixa do número; o mesmo telefone nos dois: vale a Parceria)
 *   Proprietários todos os donos dos dois números, num lugar só ("serão falados com eles só por lá")
 *   Oficial       o WhatsApp API, só para o Tel ("por enquanto")
 * Quem vê o quê, só na v2 ("o nosso login Tel vê tudo, mas o login dos SDR só tem liberado o chat da função deles"):
 *   Tel (administrador) tudo; Lucas Captação; Diego Atendimento › Leads (locação); Rayssa Atendimento › Parceria.
 *   Visita e Proprietários valem para todos ("o pessoal do atendimento tem acesso caso tenha que tirar uma dúvida").
 * A versão é uma só para todos (/api/linhas/versao); só o administrador troca, no botão do alto.
 */
import { useEffect, useState } from 'react'

export type VersaoDoCrm = 'v1' | 'v2'
export type AreaV2 = 'captacao' | 'atendimento' | 'visita' | 'proprietarios' | 'oficial'
export type LinhaDoAtendimento = 'captacao' | 'parceria'

let versao: VersaoDoCrm | null = null
let buscando: Promise<void> | null = null
const ouvintes = new Set<(v: VersaoDoCrm) => void>()

function ler(): Promise<void> {
  if (buscando) return buscando
  buscando = (async () => {
    try {
      const r = await fetch('/api/linhas/versao')
      const j = await r.json().catch(() => ({}))
      versao = j?.versao === 'v2' ? 'v2' : 'v1'
    } catch { versao = versao || 'v1' } finally {
      buscando = null
      for (const o of ouvintes) o(versao || 'v1')
    }
  })()
  return buscando
}

/** null enquanto não sabe (o menu espera para não piscar a versão errada) */
export function useVersaoDoCrm(): VersaoDoCrm | null {
  const [v, setV] = useState<VersaoDoCrm | null>(versao)
  useEffect(() => {
    ouvintes.add(setV)
    if (versao) setV(versao); else void ler()
    const relogio = setInterval(() => { if (document.visibilityState === 'visible') void ler() }, 120_000)
    return () => { ouvintes.delete(setV); clearInterval(relogio) }
  }, [])
  return v
}

export async function trocarVersaoDoCrm(nova: VersaoDoCrm): Promise<void> {
  const r = await fetch('/api/linhas/versao', { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ versao: nova }) })
  const j = await r.json().catch(() => ({}))
  if (!r.ok) throw new Error(j.error || j.message || 'Não consegui trocar a versão.')
  versao = j.versao === 'v2' ? 'v2' : 'v1'
  for (const o of ouvintes) o(versao)
}

/** a função de cada SDR pelo primeiro nome do login */
const FUNCAO_DO_SDR: Record<string, { areas: AreaV2[]; linhas: LinhaDoAtendimento[]; soLocacao?: boolean }> = {
  lucas: { areas: ['captacao'], linhas: [] },
  diego: { areas: ['atendimento'], linhas: ['captacao'], soLocacao: true },
  rayssa: { areas: ['atendimento'], linhas: ['parceria'] },
}
const DE_TODOS: AreaV2[] = ['visita', 'proprietarios']

export interface AcessoV2 { areas: AreaV2[]; linhas: LinhaDoAtendimento[]; soLocacao: boolean; admin: boolean }

export function acessoV2(admin: boolean, nome: string | null | undefined): AcessoV2 {
  if (admin) return { areas: ['captacao', 'atendimento', 'visita', 'proprietarios', 'oficial'], linhas: ['captacao', 'parceria'], soLocacao: false, admin: true }
  const primeiro = String(nome || '').trim().split(/\s+/)[0].toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
  const f = FUNCAO_DO_SDR[primeiro]
  return { areas: [...(f?.areas || []), ...DE_TODOS], linhas: f?.linhas || [], soLocacao: !!f?.soLocacao, admin: false }
}

/** os endereços de cada área (o primeiro é o que o menu abre) */
export const CAMINHOS_DA_AREA: Record<AreaV2, string[]> = {
  captacao: ['/chat/captar'],
  atendimento: ['/chat/atendimento'],
  visita: ['/chat/visita'],
  proprietarios: ['/chat/proprietarios'],
  oficial: ['/chat'],
}

/** o SDR na v2 só entra nos endereços das áreas dele (o administrador entra em tudo) */
export function podeEntrar(acesso: AcessoV2, caminho: string): boolean {
  if (acesso.admin) return true
  return acesso.areas.some((a) => CAMINHOS_DA_AREA[a].some((c) => (c === '/chat' ? caminho === '/chat' : caminho === c || caminho.startsWith(c + '/'))))
}
