/**
 * Os tipos do chat da OLX que a tela e as rotas dividem (Pedro, 08/10/2026). Sem nada de servidor aqui:
 * o que fala com o banco e com a OLX está em src/lib/olxChat.ts.
 */
export const CONTAS_OLX = ['proprietarios', 'corretores'] as const
export type ContaOlx = (typeof CONTAS_OLX)[number]

export const NOME_DA_CONTA_OLX: Record<ContaOlx, string> = {
  proprietarios: 'Conta proprietários',
  corretores: 'Conta corretores',
}

export interface EstadoDaContaOlx {
  conta: ContaOlx
  conectada: boolean
  conectadaEm: string | null
  conectadaPor: string | null
  /** quem é a conta na OLX, para conferir que ligou a certa */
  olxNome: string | null
  olxEmail: string | null
  webhookAtivo: boolean
  webhookAtivadoEm: string | null
  webhookResposta: string | null
  conversas: number
  ultimaMensagemEm: string | null
  /** o aplicativo da OLX (client_id e client_secret) está no servidor */
  aplicativoCadastrado: boolean
}

export interface ChatOlxNaLista {
  id: number
  /** o anúncio da OLX em que a conversa acontece */
  listId: string | null
  nome: string | null
  email: string | null
  telefone: string | null
  ultimaEm: string | null
  ultimaTexto: string | null
  ultimaDe: string | null
  naoLidas: number
  criadoEm: string
  mensagens: number
  /** o anúncio da conversa, do que o nay-olx publicou (migração 378); null quando não é um anúncio nosso conhecido */
  anuncio: AnuncioDoChatOlx | null
}

/** O que o chat da OLX mostra do anúncio em cada conversa (Pedro, 16/10/2026: "igual o da olx normal"). */
export interface AnuncioDoChatOlx {
  codigo: number | null
  negocio: string | null
  titulo: string | null
  preco: number | null
  /** a capa do anúncio (a primeira foto mandada à OLX) */
  foto: string | null
  url: string | null
  /** ainda publicado na OLX; a conversa de anúncio que saiu vai para "Conversas inativas" */
  noAr: boolean
  /** do cadastro do imóvel (383): para saber qual é sem abrir o anúncio */
  condominio: string | null
  bairro: string | null
}

export interface MensagemOlx {
  id: number
  de: 'comprador' | 'nos' | 'sistema'
  texto: string
  /** a hora em que a mensagem chegou a nós (ou em que mandamos) */
  quando: string
  enviadaPor: string | null
}

/** Um anúncio da conta na OLX (aba Anúncios, 13/10): o que a OLX lista somado às conversas que temos dele. */
export interface AnuncioOlx {
  listId: string
  titulo: string | null
  situacao: string | null
  /** quantas conversas nossas são deste anúncio, e quando foi a última mensagem */
  conversas: number
  naoLidas: number
  ultimaEm: string | null
  /** veio da lista da OLX (true) ou só o conhecemos pelas conversas (false) */
  daOlx: boolean
}

/** O painel da publicação automática (migração 364, `crm_olx_anuncios_painel`): as chaves, as contas e as listas. */
export interface PainelDosAnunciosOlx {
  config: Record<string, string>
  contagem: { imoveis: number; prontos: number; faltando_dados: number; enviados: number; publicados: number; recusados: number; removidos: number }
  falta: { motivo: string; n: number; codigos: number[] }[]
  nossos: {
    ad_id: string; codigo: number; negocio: 'venda' | 'locacao'; conta: string; estado: string; titulo: string | null
    preco: number | null; list_id: string | null; url: string | null; olx_status: string | null; mensagem: string | null
    enviado_em: string | null; publicado_em: string | null
  }[]
  proximos: { codigo: number; negocio: 'venda' | 'locacao'; titulo: string; preco: number; fotos: number }[]
}
