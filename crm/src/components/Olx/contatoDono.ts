/** O que a busca manual faz com o dono/anunciante de um anúncio da OLX: achar ou criar a conversa, deixar a mensagem da
 *  Nay digitada (rascunho) e enviar (Pedro, 30/10/2026). Tudo pelas rotas que o CRM já tem. */
import { CAMINHO_DA_LINHA, type LinhaWhatsapp } from '@/lib/leadChannel'
import { comMarcaDeAbertura } from '@/lib/links'
import { perguntaAoAnunciante } from '@/lib/perguntaAoAnunciante'

export type Anuncio = {
  olx_id: number; titulo: string | null; preco: number | null; preco_texto: string | null; bairro: string | null
  anunciante: string | null; telefones: string[]; url: string | null; fotos: string[] | null
}
export type LinhaDeEnvio = 'captacao' | 'parceria'
export const NOME_DA_LINHA: Record<LinhaDeEnvio, string> = { captacao: 'WhatsApp Leads (8595)', parceria: 'WhatsApp Parceria' }

export const soDigitos = (t: string) => String(t || '').replace(/\D/g, '')
export const foneParaEnviar = (t: string) => soDigitos(t).replace(/^55(?=\d{10,11}$)/, '')
export const mensagemDaNay = (a: Anuncio) => perguntaAoAnunciante(a)

/** O texto fica no campo da conversa por 1 h (o mesmo rascunho do ActivityComposer). */
export function deixarRascunho(leadId: string, texto: string) {
  try { localStorage.setItem(`crm:rascunho:${leadId}`, JSON.stringify({ t: texto, em: Date.now() })) } catch { /* sem rascunho */ }
}

export async function conversasDoNumero(telefone: string): Promise<Array<{ linha: LinhaDeEnvio; configurada: boolean; leadId: string | null }>> {
  const r = await fetch('/api/leads/conversas-do-numero', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ telefone: foneParaEnviar(telefone) }),
  })
  const j = await r.json().catch(() => ({}))
  if (!r.ok) throw new Error(j?.error || j?.message || 'Não consegui conferir as conversas.')
  return j.linhas || []
}

export async function abrirConversa(telefone: string, linha: LinhaDeEnvio, nome: string | null): Promise<string> {
  const r = await fetch('/api/leads/abrir', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ telefone: foneParaEnviar(telefone), linha, nome: nome || '' }),
  })
  const j = await r.json().catch(() => ({}))
  if (!r.ok) throw new Error(j?.error || j?.message || 'Não consegui abrir a conversa.')
  return String(j.id)
}

export async function enviarTexto(leadId: string, texto: string): Promise<void> {
  const r = await fetch(`/api/leads/${leadId}/messages`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ content: texto, type: 'whatsapp', source: 'human', direction: 'outbound' }),
  })
  if (!r.ok) {
    const j = await r.json().catch(() => ({}))
    throw new Error(j?.error || j?.message || 'A mensagem não saiu.')
  }
}

export function irParaConversa(leadId: string, linha: LinhaDeEnvio) {
  window.location.href = comMarcaDeAbertura(`${CAMINHO_DA_LINHA[linha as LinhaWhatsapp]}?leadId=${leadId}`)
}
