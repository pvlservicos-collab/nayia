/**
 * O CRM cadastra/atualiza imóvel no site a partir da conversa da captação
 * (Pedro, 29/09/2026: "o imóvel do cara já deve aparecer lá, e dar opção de
 * atualizar, e embaixo cadastrar imóvel -- o sistema já puxa as fotos e
 * informações, o resto nós preenchemos").
 *
 * Quem grava é a API do site (nay-site-api/olx_api.py, /api/captacao/crm/...),
 * com a mesma senha de máquina das fotos da captação (CAPTACAO_FOTO_SEGREDO no
 * .env do CRM e do site). O CRM manda as fotos da conversa em bytes, uma por
 * vez: elas moram no armazém do CRM, que o site não enxerga.
 */
const BASE = (process.env.SITE_API_URL || 'https://api.imobeasy.online').replace(/\/$/, '')

function segredo(): string {
  const s = process.env.CAPTACAO_FOTO_SEGREDO || ''
  if (!s) throw Object.assign(new Error('CAPTACAO_FOTO_SEGREDO ausente no CRM'), { status: 500 })
  return s
}

export interface CadastroNoSite { codigo: number; novo: boolean; usouFicha: boolean; editor: string }

/** Com `codigo`: atualiza o imóvel do dono (só campos vazios). Sem: pré-cadastro novo (Rascunho). */
export async function cadastrarNoSite(captacaoId: number, codigo: number | null): Promise<CadastroNoSite> {
  const r = await fetch(`${BASE}/api/captacao/crm/imovel`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-captacao-segredo': segredo() },
    body: JSON.stringify({ captacao_id: captacaoId, codigo }),
    signal: AbortSignal.timeout(30_000),
  })
  const j = await r.json().catch(() => ({} as any))
  if (!r.ok || !j?.ok) throw Object.assign(new Error(j?.erro || j?.detalhe || `site respondeu ${r.status}`), { status: r.status === 403 ? 403 : 502 })
  return { codigo: Number(j.codigo), novo: !!j.novo, usouFicha: !!j.usou_ficha, editor: String(j.editor) }
}

/** Uma foto da conversa para o imóvel; `fotoId` (o id da mensagem) não deixa ir duas vezes. */
export async function mandarFotoAoSite(codigo: number, dados: Buffer, fotoId: string): Promise<void> {
  const r = await fetch(`${BASE}/api/captacao/crm/imovel/${codigo}/foto`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/octet-stream', 'x-captacao-segredo': segredo(), 'x-foto-id': fotoId },
    body: new Uint8Array(dados),
    signal: AbortSignal.timeout(60_000),
  })
  const j = await r.json().catch(() => ({} as any))
  if (!r.ok || !j?.ok) throw new Error(j?.erro || `site respondeu ${r.status}`)
}
