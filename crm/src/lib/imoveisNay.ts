/**
 * O acervo de imóveis, lido da API do site.
 *
 * Tel, 27/09/2026: "ja tras uma aba imoveis que é a mesma aba do site
 * reformulada para dentro do crm tb para se alguem quiser buscar imoveis para
 * la e ja enviar para uma conversa".
 *
 * POR QUE NÃO COPIAR O BANCO PARA CÁ. Os imóveis vivem no `naydb`, com a regra
 * do parceiro, a publicação e as fotos — e é de lá que a Nay lê. Uma cópia no
 * banco do CRM envelheceria calada: imóvel alugado continuaria "disponível" na
 * tela de quem manda. Então o CRM LÊ do mesmo lugar que a Nay, pela API do
 * site, e o card é o mesmo que sai nos grupos (`nai_card_do_imovel`).
 *
 * O proxy existe por duas razões: a API do site é outro domínio (sem CORS para
 * o CRM) e assim o token de sessão do CRM continua sendo o que decide quem vê.
 */

const BASE = process.env.SITE_API_BASE || 'https://api.imobeasy.online'

export interface ImovelCard {
  codigo: number
  card: string
  qtd_fotos: number
  fotos: string[]
  e_parceiro: boolean
  /** 531: parceiro do site antigo -- não vai ao lead */
  parceiro_antigo?: boolean
  no_site: boolean
  imovel: {
    codigo: number
    status: string | null
    tipo: string | null
    condominio: string | null
    bairro: string | null
    endereco: string | null
    quartos: number | null
    suites: number | null
    banheiros: number | null
    vagas: number | null
    area_total: number | null
    valor_venda: number | null
    valor_aluguel: number | null
    financia: string | null
    e_parceiro: boolean
    publicado_no_site: boolean
    total_fotos: number
    capa: string | null
    proprietario_nome: string | null
  }
}

async function pegar(caminho: string, timeoutMs = 15000): Promise<any> {
  const ctl = new AbortController()
  const t = setTimeout(() => ctl.abort(), timeoutMs)
  try {
    const res = await fetch(`${BASE}${caminho}`, { signal: ctl.signal, cache: 'no-store' })
    const texto = await res.text()
    let corpo: any = null
    try { corpo = texto ? JSON.parse(texto) : null } catch { corpo = null }
    if (!res.ok) {
      throw { status: res.status, message: corpo?.erro || `a API do site respondeu ${res.status}` }
    }
    return corpo
  } finally {
    clearTimeout(t)
  }
}

/** A lista de imóveis, com os mesmos filtros da tela do site. */
export function listarImoveis(params: URLSearchParams) {
  return pegar(`/api/imoveis-lista?${params.toString()}`, 25000)
}

/** Os bairros do acervo, com a contagem -- a lista que desce no disparo por faixa. */
export function listarBairros(): Promise<{ bairro: string; imoveis: number }[]> {
  return pegar('/api/bairros?todos=1')
}

/** O card + as fotos de um imóvel, do jeito que a Nay manda. */
export function cardDoImovel(codigo: number, paraCliente = false): Promise<ImovelCard> {
  return pegar(`/api/imovel-card/${codigo}${paraCliente ? '?cliente=1' : ''}`)
}

/** De qual imóvel fala a mensagem que a pessoa marcou no WhatsApp. */
export function imovelDaMensagem(messageId: string): Promise<ImovelCard> {
  return pegar(`/api/mensagem-imovel?id=${encodeURIComponent(messageId)}`)
}

// As funções que leem código de texto moram em `imovelCodigo.ts` (puras, rodam
// na tela também). Reexportadas aqui para quem já importa deste arquivo.
export { codigoReferenciado, codigosNoTexto } from './imovelCodigo'
