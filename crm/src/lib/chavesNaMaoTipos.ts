/**
 * Os tipos do CHAT CHAVES NA MÃO (Pedro, 21/10/2026: "Chat Chaves na Mão igual o olx mesmas coisas").
 * O portal não tem chat: cada lead que ele manda (privado.cnm_lead, migração 458) é uma "mensagem", e os leads da
 * mesma pessoa (mesmo telefone, ou mesmo e-mail) são uma conversa. Quem monta é o banco (459): crm_cnm_chats,
 * crm_cnm_conversa, crm_cnm_ler e crm_cnm_painel.
 */
export interface AnuncioCnm {
  titulo: string | null
  url: string | null
  preco: number | null
  negocio: string | null       // Venda, Locação, Venda/Locação (como o portal escreve)
  codigo: number | null        // o nosso código, quando a referência do anúncio é um código nosso
  condominio?: string | null
  bairro?: string | null
  noAr?: boolean
  foto?: string | null
}

export interface ChatCnmNaLista {
  chave: string
  nome: string | null
  telefone: string | null
  email: string | null
  leads: number
  naoLidas: number
  criadoEm: string
  ultimaEm: string
  ultimaTexto: string
  tipo: string | null
  autenticado: boolean
  anuncio: AnuncioCnm
}

export interface LeadCnm {
  id: string
  quando: string
  recebidoEm: string
  texto: string | null
  tipo: string | null
  autenticado: boolean
  anuncio: AnuncioCnm
}

export interface AnuncioNoXml {
  codigo: number
  ok: boolean
  falta: string[]
  titulo: string | null
  tipo: string | null
  valor: number | null
  valorLocacao: number | null
  transacao: string
  fotos: number
  foto: string | null
  leads: number
  ultimoLead: string | null
}

export interface PainelCnm {
  xml: string
  leadsUrl: string
  vao: number
  ficam: number
  anuncios: AnuncioNoXml[]
  leads: { total: number; pessoas: number; naoLidos: number; autenticados: number; ultimoEm: string | null }
  senhaGuardada: boolean
  naySim?: boolean             // só no Chat Zap (574): a Nay do 8595 chama o lead (zap_config.nay_atende)
  conferido?: boolean          // só no Chat Zap: false = a API do site não disse quem fica de fora do XML
}
