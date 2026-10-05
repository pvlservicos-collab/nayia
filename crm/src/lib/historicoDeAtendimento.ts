/**
 * O HISTÓRICO DE ATENDIMENTO NO CARD (Pedro, 05/10/2026): "uma filinha para eu saber
 * quando é a Nay atendendo, ou o Tel entra e digita mensagem ... Tel ou Rayssa têm suas
 * próprias tags baseadas em sua conta ... não é algo completo, só umas tags passando
 * para o lado que não gaste muito dos nossos recursos".
 *
 * Uma tag por vez que alguém do nosso lado falou: as mensagens NOSSAS seguidas do mesmo
 * autor, no mesmo dia, viram uma tag só ("Nay · 09:12–09:40 · 6"). O que a pessoa escreve
 * não entra: a fila é de quem atendeu, não da conversa.
 *
 * Quem é o autor de cada mensagem nossa:
 *   - saiu pelo CRM: a conta de quem mandou (Tel, Rayssa...), com a cor dela na lista;
 *   - chegou como eco da Z-API: o banco da Nay diz pelo id (crm_quem_mandou, 290) se foi
 *     a Nay, um envio automático (publicador) ou nenhum dos dois -- aí foi alguém
 *     digitando no celular do número da Nay.
 *
 * Este arquivo é só a conta (sem banco), para dar para testar fora do servidor.
 */
import { diaEmManaus } from '@/lib/fusoDeManaus'

export type TipoDeAutor = 'nay' | 'conta' | 'celular' | 'sistema' | 'desconhecido'

export interface AutorDoEnvio {
  tipo: TipoDeAutor
  /** o que a tag mostra: "Nay", "Tel", "Rayssa", "Celular", "Envio automático" */
  nome: string
  cor: string
}

export interface TagDeAtendimento extends AutorDoEnvio {
  /** a primeira e a última mensagem da tag (ISO) */
  de: string
  ate: string
  /** quantas mensagens nossas a tag junta */
  n: number
}

export const COR_DA_NAY = '#25D366'
export const COR_DO_CELULAR = '#94A3B8'
export const COR_DO_SISTEMA = '#60A5FA'

export const AUTOR_NAY: AutorDoEnvio = { tipo: 'nay', nome: 'Nay', cor: COR_DA_NAY }
/* O que é digitado direto no WhatsApp do número (celular ou WhatsApp Web) não tem conta do CRM. Pedro, 05/10:
   "o que é essa tag Celular? é para ser por conta, Tel ou Rayssa". Quem usa o aparelho do número é o Tel (é
   assim que a Nay também trata a mensagem manual: "o Tel escreveu"); a Rayssa atende pela conta dela no CRM.
   A tag sai como Tel, na cor dele, com o ícone do celular para distinguir do que ele manda pelo CRM. */
export const AUTOR_CELULAR: AutorDoEnvio = { tipo: 'celular', nome: 'Tel', cor: '#FB7185' }
export const AUTOR_SISTEMA: AutorDoEnvio = { tipo: 'sistema', nome: 'Envio automático', cor: COR_DO_SISTEMA }
export const AUTOR_DESCONHECIDO: AutorDoEnvio = { tipo: 'desconhecido', nome: '?', cor: COR_DO_CELULAR }

/** A origem que o banco da Nay devolveu para um eco -> o autor da tag. */
export function autorDoEco(origem: string | null | undefined): AutorDoEnvio {
  if (origem === 'nay') return AUTOR_NAY
  if (origem === 'sistema') return AUTOR_SISTEMA
  if (origem === 'gente') return AUTOR_CELULAR
  return AUTOR_DESCONHECIDO
}

export interface EnvioNosso {
  em: string
  autor: AutorDoEnvio
  /** foto ou vídeo (sem isto, a regra das fotos do publicador não se aplica) */
  midia?: boolean
}

/**
 * AS FOTOS DO PUBLICADOR. Quando o publicador manda um imóvel a um corretor, o card tem
 * o id guardado (vira "Envio automático"), mas as fotos que vão junto nem sempre: medido
 * em 05/10, elas saíam como "Celular" coladas no card -- 13 fotos em 3 minutos que
 * ninguém digitou. Foto sem dono colada (até 5 min) num envio automático é dele também.
 * Só mídia: texto digitado perto do card continua sendo de quem digitou.
 */
const COLADA_MS = 5 * 60_000
export function fotosDoEnvioAutomatico(envios: EnvioNosso[]): EnvioNosso[] {
  const saida = envios.map((e) => ({ ...e }))
  const colada = (a: EnvioNosso, b: EnvioNosso) => Math.abs(Date.parse(a.em) - Date.parse(b.em)) <= COLADA_MS
  const vira = (e: EnvioNosso, vizinho: EnvioNosso | undefined) =>
    e.autor.tipo === 'celular' && e.midia === true && !!vizinho && vizinho.autor.tipo === 'sistema' && colada(e, vizinho)
  for (let i = 1; i < saida.length; i++) if (vira(saida[i], saida[i - 1])) saida[i].autor = AUTOR_SISTEMA
  for (let i = saida.length - 2; i >= 0; i--) if (vira(saida[i], saida[i + 1])) saida[i].autor = AUTOR_SISTEMA
  return saida
}

/**
 * Junta os envios (do mais antigo para o mais novo) em tags e fica com as últimas
 * `maximo`. Muda de tag quando muda o autor ou o dia (de Manaus).
 */
export function juntarEmTags(envios: EnvioNosso[], maximo = 25): TagDeAtendimento[] {
  const tags: TagDeAtendimento[] = []
  let diaDaUltima = ''
  for (const e of envios) {
    const dia = diaEmManaus(new Date(e.em))
    const ultima = tags[tags.length - 1]
    if (ultima && ultima.tipo === e.autor.tipo && ultima.nome === e.autor.nome && diaDaUltima === dia) {
      ultima.ate = e.em
      ultima.n++
    } else {
      tags.push({ ...e.autor, de: e.em, ate: e.em, n: 1 })
    }
    diaDaUltima = dia
  }
  return tags.slice(-maximo)
}
