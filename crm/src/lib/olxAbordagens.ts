/**
 * O que a aba "Chat OLX" mostra (Pedro, 08/10/2026): cada anúncio que o bot da OLX consultou, a decisão e a
 * mensagem entregue para ele mandar. Tipo e rótulos usados pela rota (/api/olx/abordagens) e pela tela
 * (components/Chat/ChatOlx.tsx). O dado vem da função crm_olx_abordagens (migração 313).
 */
export interface AbordagemOlx {
  id: number
  link: string
  titulo: string | null
  tipo: string | null
  finalidade: string | null
  preco: number | null
  bairro: string | null
  condominio: string | null
  anunciante: string | null
  telefone: string | null
  acao: 'abordar' | 'fechar'
  motivo: string
  /** o imóvel nosso, quando a resposta foi "já temos" */
  codigo: number | null
  /** o texto entregue ao bot para mandar ao anunciante (só quando acao = abordar) */
  mensagem: string | null
  entregueEm: string | null
  recebidoEm: string
  /** quantas vezes o bot consultou este anúncio */
  pedidos: number
}

/** O motivo da decisão, como a equipe lê. */
export const MOTIVO_OLX: Record<string, string> = {
  nao_temos: 'Não temos este imóvel',
  ja_temos: 'Já temos no cadastro',
  proprietario_ja_e_nosso: 'O proprietário já é nosso',
  corretor: 'É corretor ou imobiliária',
  dispensa_imobiliaria: 'O anúncio dispensa imobiliária',
}
