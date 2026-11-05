'use client'

/**
 * A ORGANIZAÇÃO DO CRM, v1 x v2 (Pedro, 03/11/2026). A v1 é a de sempre e não muda. A v2 organiza por etapas:
 *   Captação      o Chat Captação (cadastros incompletos e donos chamados pela OLX)
 *   Atendimento   os dois WhatsApp (Leads e Parceria) para escolher lá em cima; sem os proprietários (eles ficam na aba
 *                 Proprietários). No Leads, a LOCAÇÃO é do Diego: quem a Nay entendeu como locação e quem a equipe
 *                 mandou com o botão "Mandar para locação"
 *   Visita        quem está na etapa visita, dos dois números (com a faixa do número; o mesmo telefone nos dois: vale a Parceria)
 *   Proprietários todos os donos dos dois números, num lugar só ("serão falados com eles só por lá")
 *   Fechamento    (04/11) a última etapa, depois de Proprietários: só o Tel vê, e quem ele incluir na conversa
 *                 (hooks/useFechamentoV2.ts); a Rayssa e o Diego têm a aba, com só os leads em que foram incluídos
 *   Administração (04/11: "tá faltando a aba administração") o Chat Administração, só do login Tel
 *   Oficial       o WhatsApp API, só para o Tel ("por enquanto")
 * Quem vê o quê, só na v2 ("o nosso login Tel vê tudo, mas o login dos SDR só tem liberado o chat da função deles"):
 *   Tel (administrador) tudo; Lucas Captação e Visita (04/11); Diego Atendimento › Leads (locação); Rayssa Atendimento › Parceria.
 *   Visita e Proprietários valem para quem atende ("o pessoal do atendimento tem acesso caso tenha que tirar uma dúvida");
 *   Proprietários o Lucas não tem ("o Lucas não vai falar com proprietários, ele é só da etapa captação").
 * QUEM ATENDE (03/11, noite): cada pessoa tem uma cor (Rayssa rosa, Diego azul-claro, Lucas laranja; Tel roxo; a Nay Leads
 * verde e a Nay Parceria anil). O responsável por um proprietário: ver responsavelV2 (04/11).
 * A versão é uma só para todos (/api/linhas/versao); só o administrador troca, no botão do alto.
 */
import { useEffect, useState } from 'react'
import { useAuth } from '@/hooks'

export type VersaoDoCrm = 'v1' | 'v2'
export type AreaV2 = 'captacao' | 'atendimento' | 'visita' | 'proprietarios' | 'fechamento' | 'administracao' | 'oficial'
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
/* soOsNumerosDela (Pedro, 04/11: "para o cadastro da Rayssa não precisa pôr o número de Leads, deixa só o número de
   Parceria aparecendo; mas o corretor do Leads que alguém mandou com Enviar para Rayssa aparece para ela no chat da
   Parceria, com o aviso embaixo falando pelo número de Leads"): nas telas que juntam os dois números (Visita,
   Proprietários, Fechamento) ela só vê as conversas dos números dela e as que foram ENVIADAS para eles (mudou_para) */
const FUNCAO_DO_SDR: Record<string, { areas: AreaV2[]; linhas: LinhaDoAtendimento[]; soLocacao?: boolean; soOsNumerosDela?: boolean }> = {
  // 04/11, mais tarde (Pedro: "libera a aba Visita para o Lucas também"): ele passa a ver a agenda de visitas dos dois
  // números, além da Captação
  lucas: { areas: ['captacao', 'visita'], linhas: [] },
  // 05/11 (Pedro: "o Diego criou um lead e não apareceu em Todos pra ele; pode tirar todo limitador, mesmo contatos de vendas,
  // libera todas as funções de SDR pra ele"): os dois números, venda e locação, sem recorte
  diego: { areas: ['atendimento', 'visita', 'proprietarios', 'fechamento'], linhas: ['captacao', 'parceria'] },
  // 04/11 (Pedro: "libera o WhatsApp Leads para a Rayssa, mas abre primeiro o de Parceria, e o de Leads à direita; só
  // carrega se ela clicar, e quando ela sai, sai, para não pesar"): a Parceria é a primeira; o Leads só carrega aberto
  rayssa: { areas: ['atendimento', 'visita', 'proprietarios', 'fechamento'], linhas: ['parceria', 'captacao'], soOsNumerosDela: true },
}

/* AS ABAS POR FUNÇÃO (Pedro, 04/11/2026: "lá nas Funções eu quero poder liberar aba por aba para cada SDR; o Lucas é
   uma função nova chamada Captador"): em Configurações › Membros e Permissões, cada função tem "Abas do CRM (v2)"
   (permissions.abas). Quando a função tem essa lista, ela manda nas áreas; sem ela, vale a regra por nome de antes
   (FUNCAO_DO_SDR). O número de cada um no Atendimento continua por nome (Diego Leads/locação, Rayssa Parceria). */
export const AREAS_V2: Array<{ chave: AreaV2; rotulo: string }> = [
  { chave: 'captacao', rotulo: 'Captação' }, { chave: 'atendimento', rotulo: 'Atendimento' }, { chave: 'visita', rotulo: 'Visita' },
  { chave: 'proprietarios', rotulo: 'Proprietários' }, { chave: 'fechamento', rotulo: 'Fechamento' },
  { chave: 'administracao', rotulo: 'Administração' }, { chave: 'oficial', rotulo: 'WhatsApp Oficial' },
]
export type AbasDaFuncao = Partial<Record<string, boolean>> | null | undefined

/* OS MENUS DE CIMA POR FUNÇÃO (Pedro, 04/11, de novo: "eu quero poder liberar para ele a aba Proprietários, ou a aba
   Fechamento, a aba Imóveis ... menu por menu lá de cima"): a mesma lista (permissions.abas) também guarda os outros
   menus da barra, pela rota. Função com a lista: só o que está ligado aparece (na v1 e na v2) e só nisso ela entra. */
export const OUTROS_MENUS: Array<{ chave: string; rotulo: string }> = [
  { chave: '/imoveis', rotulo: 'Imóveis' }, { chave: '/pipeline', rotulo: 'Pipeline geral' },
  { chave: '/chat/parceria', rotulo: 'WhatsApp Parceria' }, { chave: '/chat/captacao', rotulo: 'WhatsApp Leads' },
  { chave: '/chat/olx', rotulo: 'Chat OLX' }, { chave: '/chat/chavesnamao', rotulo: 'Chaves' }, { chave: '/chat/zap', rotulo: 'Chat Zap' },
  { chave: '/chat/grupos', rotulo: 'Grupos' }, { chave: '/visitantes', rotulo: 'Visitantes' },
  { chave: '/buscar-imovel-olx', rotulo: 'Buscar imóvel OLX' }, { chave: '/imoveis-captar-olx', rotulo: 'Imóveis captar OLX' },
  { chave: '/cadastros-incompletos', rotulo: 'Cadastros incompletos' }, { chave: '/corretores', rotulo: 'Corretores' },
  { chave: '/esteira-followups', rotulo: 'Esteira de follow-up' }, { chave: '/visao-geral', rotulo: 'Visão geral' },
  { chave: '/guia-de-atendimento', rotulo: 'Guia de atendimento' }, { chave: '/tutoriais', rotulo: 'Tutoriais' },
  { chave: '/arquitetura', rotulo: 'Arquitetura' }, { chave: '/settings/organization', rotulo: 'Configurações' },
]

/** A função tem a lista de menus? */
export function temMenusDaFuncao(abas: AbasDaFuncao): boolean {
  return !!abas && Object.keys(abas).length > 0
}

/** Este menu (a rota) está ligado na função? As etapas da v2 contam pela área (Captação = /chat/captar). */
export function menuLiberado(abas: AbasDaFuncao, href: string): boolean {
  if (!temMenusDaFuncao(abas)) return false
  const area = (Object.keys(CAMINHOS_DA_AREA) as AreaV2[]).find((a) => CAMINHOS_DA_AREA[a][0] === href)
  return !!(area ? abas![area] : abas![href])
}

/** A rota de agora está num dos outros menus ligados na função (a guarda de endereço da v2 deixa entrar) */
export function caminhoLiberado(abas: AbasDaFuncao, caminho: string): boolean {
  return OUTROS_MENUS.some((m) => !!abas?.[m.chave] && (caminho === m.chave || caminho.startsWith(m.chave + '/')))
}

export interface AcessoV2 { areas: AreaV2[]; linhas: LinhaDoAtendimento[]; soLocacao: boolean; admin: boolean; soOsNumerosDela?: boolean }

export function acessoV2(admin: boolean, nome: string | null | undefined, abas?: AbasDaFuncao): AcessoV2 {
  if (admin) return { areas: ['captacao', 'atendimento', 'visita', 'proprietarios', 'fechamento', 'administracao', 'oficial'], linhas: ['captacao', 'parceria'], soLocacao: false, admin: true }
  const primeiro = String(nome || '').trim().split(/\s+/)[0].toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
  const f = FUNCAO_DO_SDR[primeiro]
  const daFuncao = abas && Object.keys(abas).length ? AREAS_V2.map((a) => a.chave).filter((a) => abas[a]) : null
  const linhas = f?.linhas?.length ? f.linhas : (daFuncao?.includes('atendimento') ? (['captacao', 'parceria'] as LinhaDoAtendimento[]) : [])
  return { areas: daFuncao || f?.areas || [], linhas, soLocacao: !!f?.soLocacao, admin: false, soOsNumerosDela: !!f?.soOsNumerosDela }
}

export function primeiroNome(nome: string | null | undefined): string {
  return String(nome || '').trim().split(/\s+/)[0].toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
}

/** as cores de quem atende na v2 (o nome em pé na borda, o "falando" no alto da conversa) */
export const CORES_V2: Record<string, string> = {
  tel: '#8b5cf6', rayssa: '#ec4899', diego: '#38bdf8', lucas: '#f97316', nay_leads: '#16a34a', nay_parceria: '#6366f1',
}
export interface QuemAtende { chave: string; nome: string; cor: string; nay?: boolean }

export function pessoaV2(nome: string | null | undefined): QuemAtende | null {
  const p = primeiroNome(nome)
  if (!p) return null
  const rotulo = p.charAt(0).toUpperCase() + p.slice(1)
  return { chave: p, nome: rotulo, cor: CORES_V2[p] || '#64748b' }
}

export function nayDaLinha(linha: string | null | undefined): QuemAtende {
  return linha === 'parceria'
    ? { chave: 'nay_parceria', nome: 'Nay Parceria', cor: CORES_V2.nay_parceria, nay: true }
    : { chave: 'nay_leads', nome: 'Nay Leads', cor: CORES_V2.nay_leads, nay: true }
}

/** o responsável por um proprietário na v2 (Pedro, 04/11: "com as tags só os que já estão, os outros aparecem sem tags
 *  laterais até algum dos 2 chamar; sempre que a Rayssa ou o Diego chamar deve ir para a tag deles no automático"):
 *  quem assumiu ou mandou por último (custom_attributes.responsavel_v2, gravado no envio e no "Assumir"); sem isso, a última
 *  mensagem manual da Rayssa ou do Diego (autores_manuais vem do mais recente); senão, ninguém (sem borda). */
export const DONOS_DOS_PROPRIETARIOS = ['rayssa', 'diego']
export function responsavelV2(lead: { custom_attributes?: any; autores_manuais?: string[] },
                              equipe: Record<string, QuemAtende>): QuemAtende | null {
  const r = lead.custom_attributes?.responsavel_v2
  if (r && typeof r === 'object' && r.nome) {
    const p = pessoaV2(r.nome)
    if (p) return p
  }
  for (const id of lead.autores_manuais || []) {
    const p = equipe[id]
    if (p && DONOS_DOS_PROPRIETARIOS.includes(p.chave)) return p
  }
  return null
}

/** os endereços de cada área (o primeiro é o que o menu abre) */
export const CAMINHOS_DA_AREA: Record<AreaV2, string[]> = {
  captacao: ['/chat/captar'],
  // 05/11 (Pedro: "a v3 para todos"): o Atendimento é o da v3; o da v2 fica como reserva (o endereço leva à v3)
  atendimento: ['/chat/v3', '/chat/atendimento'],
  visita: ['/chat/visita'],
  proprietarios: ['/chat/proprietarios'],
  fechamento: ['/chat/fechamento'],
  administracao: ['/chat/administracao'],
  oficial: ['/chat'],
}

/** o SDR na v2 só entra nos endereços das áreas dele (o administrador entra em tudo) */
export function podeEntrar(acesso: AcessoV2, caminho: string): boolean {
  if (acesso.admin) return true
  return acesso.areas.some((a) => CAMINHOS_DA_AREA[a].some((c) => (c === '/chat' ? caminho === '/chat' : caminho === c || caminho.startsWith(c + '/'))))
}

/* VISUALIZAR POR (Pedro, 04/11/2026: "uma listinha de visualização do CRM lá em cima; começa Padrão e só tem no login
   Tel: Visualizar por, uma lista suspensa, eu clico e aparece uma lista para eu visualizar como um dos SDR"). Só o
   administrador escolhe; o CRM passa a mostrar o que aquele SDR vê na v2 (as áreas do menu, os números, a aba Meus, o
   Fechamento em que ele foi incluído). Nada muda no banco nem para os outros: fica neste navegador. */
const CHAVE_VER_COMO = 'crm:visualizar-por'
export const SDRS_V2 = Object.keys(FUNCAO_DO_SDR)
let verComo: string | null | undefined
const ouvintesVerComo = new Set<(v: string | null) => void>()

export function useVerComo(): [string | null, (v: string | null) => void] {
  const [v, setV] = useState<string | null>(verComo ?? null)
  useEffect(() => {
    if (verComo === undefined) {
      try { const x = localStorage.getItem(CHAVE_VER_COMO); verComo = x && SDRS_V2.includes(x) ? x : null } catch { verComo = null }
    }
    setV(verComo ?? null)
    ouvintesVerComo.add(setV)
    return () => { ouvintesVerComo.delete(setV) }
  }, [])
  const trocar = (novo: string | null) => {
    verComo = novo && SDRS_V2.includes(novo) ? novo : null
    try { if (verComo) localStorage.setItem(CHAVE_VER_COMO, verComo); else localStorage.removeItem(CHAVE_VER_COMO) } catch {}
    for (const o of ouvintesVerComo) o(verComo)
  }
  return [v, trocar]
}

/** Quem a tela da v2 considera: o login de verdade, ou o SDR escolhido no Visualizar por (só para o administrador). */
/** as abas da função de cada SDR (pelo primeiro nome), para o Visualizar por: uma leitura por carga da página */
let abasPorNome: Record<string, AbasDaFuncao> | null = null
let lendoAbas: Promise<void> | null = null
function lerAbasPorNome(): Promise<void> {
  if (lendoAbas) return lendoAbas
  lendoAbas = (async () => {
    try {
      const [u, r] = await Promise.all([fetch('/api/users').then((x) => x.json()), fetch('/api/roles').then((x) => x.json())])
      const daFuncao = new Map<string, AbasDaFuncao>(((r?.data || []) as any[]).map((x) => [String(x.id), x.permissions?.abas || null]))
      const m: Record<string, AbasDaFuncao> = {}
      for (const x of (u?.data || []) as any[]) {
        const p = primeiroNome(x?.profiles?.full_name)
        if (p && !(p in m)) m[p] = daFuncao.get(String(x.role_id)) || null
      }
      abasPorNome = m
    } catch { abasPorNome = abasPorNome || {} }
  })()
  return lendoAbas
}

export function usePapelV2(): { admin: boolean; adminDeVerdade: boolean; nome: string; simulando: string | null; abas: AbasDaFuncao } {
  const { isMaster, roleName, permissions, profileName, user } = useAuth()
  const adminDeVerdade = !!(isMaster || ['admin', 'administrador', 'owner'].includes(roleName?.toLowerCase() || '') || (permissions as any)?.['*'])
  const [ver] = useVerComo()
  const simulando = adminDeVerdade && ver ? ver : null
  const [, setLido] = useState(0)
  useEffect(() => {
    if (simulando && !abasPorNome) void lerAbasPorNome().then(() => setLido((n) => n + 1))
  }, [simulando])
  return simulando
    ? { admin: false, adminDeVerdade, nome: simulando, simulando, abas: abasPorNome?.[simulando] ?? null }
    : { admin: adminDeVerdade, adminDeVerdade, nome: profileName || user?.name || '', simulando: null, abas: (permissions as any)?.abas ?? null }
}
