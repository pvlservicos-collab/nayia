/**
 * O QUE O CRM LÊ DA NAY, NA ABA DA PARCERIA (29/09/2026).
 *
 * Pedro: "nas tags de cima ... TODOS, Não lidos, Proprietários (filtra
 * conforme o banco de dados, o sistema já sabe quem é), VISITAS, TEL (o Tel
 * atendendo)"; "uma aba só de visitas agendadas que a ia preenche sozinha";
 * e no card do lead "o histórico do que aquele contato já pediu".
 *
 * Tudo sai de funções de LEITURA do banco da Nay (Arquivos/nai/166), pelo
 * mesmo usuário `nay_disparo` do disparo -- ele só executa função, não lê
 * tabela. A regra de cada marca mora lá (quem é proprietário, o Tel com a
 * conversa, visita aberta); aqui só se traduz para a tela.
 */
import { naydb } from './nayDisparo'

import type { EstadoDaNay, EventoDaVisita, ItemDoHistorico, MarcaDaNay, VisitaDaNay } from './tiposNay'
export type { EstadoDaNay, EventoDaVisita, ItemDoHistorico, MarcaDaNay, VisitaDaNay } from './tiposNay'

const iso = (v: unknown): string | null => (v instanceof Date ? v.toISOString() : v ? String(v) : null)

/**
 * A chave da pessoa como a Nay guarda (`nai_chave`): 55 + DDD + os 8 últimos
 * dígitos -- ou `lid:<número>` quando o WhatsApp entrega o LID no lugar do
 * telefone. É por ela que a visita acha a conversa do corretor no CRM.
 */
export function chavesDaNay(telefone: string | null | undefined): string[] {
  const d = String(telefone || '').replace(/\D/g, '')
  const chaves: string[] = []
  if (/^55\d{10,11}$/.test(d)) chaves.push(d.slice(0, 4) + d.slice(-8))
  else if (d.length === 10 || d.length === 11) chaves.push('55' + d.slice(0, 2) + d.slice(-8))
  else if (d.length >= 12 && d.length <= 20) chaves.push('lid:' + d)
  return chaves
}

/** As marcas de cada telefone de conversa (por telefone, como veio). */
export async function marcasDaNay(telefones: string[]): Promise<Map<string, MarcaDaNay>> {
  const mapa = new Map<string, MarcaDaNay>()
  const unicos = Array.from(new Set(telefones.filter(Boolean)))
  if (!unicos.length) return mapa
  const r = await naydb().query('SELECT * FROM crm_parceria_marcas($1::text[])', [unicos])
  for (const l of r.rows) {
    mapa.set(String(l.telefone), {
      proprietario: l.proprietario === true,
      proprietarioNome: l.proprietario_nome ?? null,
      imoveisDoDono: Array.isArray(l.imoveis_do_dono) ? l.imoveis_do_dono.map(String) : [],
      corretor: l.corretor === true,
      corretorNome: l.corretor_nome ?? null,
      creci: l.creci ?? null,
      visitaAberta: l.visita_aberta === true,
      visitaId: l.visita_id != null ? Number(l.visita_id) : null,
      visitaQuando: iso(l.visita_quando),
      visitaEstado: l.visita_estado ?? null,
      visitaPapel: l.visita_papel ?? null,
      visitaCodigo: l.visita_codigo != null ? Number(l.visita_codigo) : null,
      telAtendendo: l.tel_atendendo === true,
      telMotivo: l.tel_motivo ?? null,
      etapa: l.etapa ?? null,
      etapaDesde: iso(l.etapa_desde),
      equipe: l.equipe === true,
    })
  }
  return mapa
}

/** A Nay está ligada (modo 'todos' e sem pausa)? -- crm_nay_ligada, migração 170. */
export async function nayLigada(): Promise<EstadoDaNay> {
  const r = await naydb().query('SELECT * FROM crm_nay_ligada()')
  const l = r.rows[0]
  return { ligada: l?.ligada === true, motivo: l?.motivo ?? (l ? null : 'Não consegui ler a Nay') }
}

export async function visitasDaNay(desde?: string | null, ate?: string | null): Promise<VisitaDaNay[]> {
  const r = await naydb().query('SELECT * FROM crm_visitas($1::date, $2::date)', [desde || null, ate || null])
  return r.rows.map((l: any) => ({
    id: Number(l.id),
    codigo: l.codigo != null ? Number(l.codigo) : null,
    imovel: l.imovel ?? null,
    estado: String(l.estado),
    aberta: l.aberta === true,
    aguardando: l.aguardando ?? null,
    urgente: l.urgente === true,
    acesso: l.acesso ?? null,
    quando: iso(l.quando),
    quandoSugerido: iso(l.quando_sugerido),
    criadoEm: iso(l.criado_em),
    confirmadaCorretorEm: iso(l.confirmada_corretor_em),
    aprovadaEm: iso(l.aprovada_em),
    aprovadaPor: l.aprovada_por ?? null,
    propOkEm: iso(l.prop_ok_em),
    motoOkEm: iso(l.moto_ok_em),
    confirmadaEm: iso(l.confirmada_em),
    posVisitaEm: iso(l.pos_visita_em),
    encerradaEm: iso(l.encerrada_em),
    atualizadoEm: iso(l.atualizado_em),
    resultado: l.resultado ?? null,
    motivo: l.motivo ?? null,
    corretorNome: l.corretor_nome ?? null,
    corretorChaves: Array.isArray(l.corretor_chaves) ? l.corretor_chaves.map(String) : [],
    proprietarioNome: l.proprietario_nome ?? null,
    visitanteNome: l.visitante_nome ?? null,
  }))
}

export async function eventosDaVisita(id: number): Promise<EventoDaVisita[]> {
  const r = await naydb().query('SELECT * FROM crm_visita_eventos($1::bigint)', [id])
  return r.rows.map((l: any) => ({ quando: iso(l.quando) || '', tipo: String(l.tipo), detalhe: l.detalhe ?? null }))
}

/**
 * O CRM mexe na visita (29/09/2026, migração 169): mudar o horário (ninguém é
 * avisado), marcar como realizada (a Nay pergunta ao corretor como foi) ou
 * excluir (some da agenda, ninguém é avisado). Quem decide o que pode é o
 * banco da Nay; aqui só se repassa a resposta dele.
 */
export type AcaoNaVisita = 'horario' | 'realizada' | 'excluir'

export async function mexerNaVisita(
  id: number, acao: AcaoNaVisita, quem: string, quando?: Date,
): Promise<{ ok: boolean; mensagem: string }> {
  const r = acao === 'horario'
    ? await naydb().query('SELECT * FROM crm_visita_mudar_horario($1::bigint, $2::timestamptz, $3::text)', [id, quando!.toISOString(), quem])
    : acao === 'realizada'
      ? await naydb().query('SELECT * FROM crm_visita_realizada($1::bigint, $2::text)', [id, quem])
      : await naydb().query('SELECT * FROM crm_visita_excluir($1::bigint, $2::text)', [id, quem])
  const l = r.rows[0]
  return { ok: !!l?.ok, mensagem: String(l?.mensagem || 'Sem resposta da Nay.') }
}

/** Um campo da visita, à mão (lápis da agenda, migração 174). Ninguém é avisado. */
export const CAMPOS_EDITAVEIS_DA_VISITA = ['codigo', 'visitante_nome', 'proprietario_nome', 'acesso', 'acesso_detalhe'] as const
export type CampoDaVisita = typeof CAMPOS_EDITAVEIS_DA_VISITA[number]

export async function editarVisita(id: number, campo: CampoDaVisita, valor: string | null, quem: string): Promise<{ ok: boolean; mensagem: string }> {
  const r = await naydb().query('SELECT * FROM crm_visita_editar($1::bigint, $2::text, $3::text, $4::text)', [id, campo, valor, quem])
  const l = r.rows[0]
  return { ok: !!l?.ok, mensagem: String(l?.mensagem || 'Sem resposta da Nay.') }
}

/** Os números do painel de métricas da Parceria (migração 175). */
export interface PainelDaNay {
  respostasHoje: number; respostasOntem: number; respostas1h: number; ultimaResposta: string | null
  corretoresHoje: number; corretoresOntem: number; imoveisHoje: number; imoveisOntem: number
  visitasHoje: number; visitasAbertas: number; visitasConfirmadas: number; turnosHoje: number
}

export async function painelDaNay(): Promise<PainelDaNay> {
  const r = await naydb().query('SELECT * FROM crm_painel_nay()')
  const l = r.rows[0] || {}
  const n = (x: unknown) => Number(x || 0)
  return {
    respostasHoje: n(l.respostas_hoje), respostasOntem: n(l.respostas_ontem), respostas1h: n(l.respostas_1h),
    ultimaResposta: iso(l.ultima_resposta),
    corretoresHoje: n(l.corretores_hoje), corretoresOntem: n(l.corretores_ontem),
    imoveisHoje: n(l.imoveis_hoje), imoveisOntem: n(l.imoveis_ontem),
    visitasHoje: n(l.visitas_hoje), visitasAbertas: n(l.visitas_abertas), visitasConfirmadas: n(l.visitas_confirmadas),
    turnosHoje: n(l.turnos_hoje),
  }
}

/** "Parar Nay" / "Nay voltar a atender" no card do contato (migração 176). */
export async function pararOuDevolverANay(telefone: string, acao: 'parar' | 'voltar', quem: string): Promise<{ ok: boolean; mensagem: string }> {
  const fn = acao === 'parar' ? 'crm_nay_parar' : 'crm_nay_voltar'
  const r = await naydb().query(`SELECT * FROM ${fn}($1::text, $2::text)`, [telefone, quem])
  const l = r.rows[0]
  return { ok: !!l?.ok, mensagem: String(l?.mensagem || 'Sem resposta da Nay.') }
}

/** O registro da captação (migração 177), para a conferência do CRM. */
export interface MensagemDaCaptacao {
  id: number; telefone: string; nome: string | null; direcao: string; origem: string
  texto: string | null; messageId: string | null; criadaEm: string
}

export async function mensagensDaCaptacao(desde: Date, ate: Date, limite = 5000): Promise<MensagemDaCaptacao[]> {
  const r = await naydb().query('SELECT * FROM crm_captacao_mensagens($1::timestamptz, $2::timestamptz, $3::int)',
    [desde.toISOString(), ate.toISOString(), limite])
  return r.rows.map((l: any) => ({
    id: Number(l.id), telefone: String(l.telefone || ''), nome: l.nome ?? null, direcao: String(l.direcao),
    origem: String(l.origem || ''), texto: l.texto ?? null, messageId: l.message_id ?? null, criadaEm: iso(l.criada_em) || '',
  }))
}

export async function historicoDaNay(telefone: string, limite = 80): Promise<ItemDoHistorico[]> {
  const r = await naydb().query('SELECT * FROM crm_contato_historico($1::text, $2::int)', [telefone, limite])
  return r.rows.map((l: any) => ({
    quando: iso(l.quando) || '',
    tipo: l.tipo,
    codigo: l.codigo != null ? Number(l.codigo) : null,
    imovel: l.imovel ?? null,
    detalhe: l.detalhe ?? null,
  }))
}

/** O telefone de um @lid, pelo que a Nay aprendeu (crm_telefone_do_lid, migração 167). */
export async function telefoneDoLidNaNay(lid: string): Promise<string | null> {
  const r = await naydb().query('SELECT crm_telefone_do_lid($1::text) AS telefone', [lid])
  const t = r.rows[0]?.telefone
  return t ? String(t) : null
}

/**
 * Quem recebeu uma mensagem NOSSA, pelo id dela (migração 171): a captação
 * guarda o id de cada disparo, a Nay o de cada envio. É o que resolve o eco com
 * @lid de quem nunca respondeu (captação, 29/09: "tá puxando id e não número").
 */
export async function contatoDaMensagemNaNay(messageId: string): Promise<{ telefone: string; nome: string | null } | null> {
  if (!messageId) return null
  const r = await naydb().query('SELECT * FROM crm_contato_da_mensagem($1::text)', [messageId])
  const l = r.rows[0]
  return l?.telefone ? { telefone: String(l.telefone), nome: l.nome ?? null } : null
}

export interface MensagemDaParceria {
  id: number
  telefone: string
  nome: string | null
  direcao: string
  origem: string
  texto: string | null
  midia: string | null
  duracao: number | null
  messageId: string
  criadaEm: string
  citadoId: string | null
}

/** As mensagens do número da Parceria num intervalo, em ordem (crm_mensagens_da_parceria, 167). */
export async function mensagensDaParceria(desde: Date, ate: Date, limite = 2000): Promise<MensagemDaParceria[]> {
  const r = await naydb().query('SELECT * FROM crm_mensagens_da_parceria($1::timestamptz, $2::timestamptz, $3::int)',
                                [desde.toISOString(), ate.toISOString(), limite])
  return r.rows.map((l: any) => ({
    id: Number(l.id),
    telefone: String(l.telefone || ''),
    nome: l.nome ?? null,
    direcao: String(l.direcao || ''),
    origem: String(l.origem || ''),
    texto: l.texto ?? null,
    midia: l.midia ?? null,
    duracao: l.duracao != null ? Number(l.duracao) : null,
    messageId: String(l.message_id),
    criadaEm: iso(l.criada_em) || '',
    citadoId: l.citado_id ?? null,
  }))
}

/** O dono de cada telefone da captação (migração 180): "Evandro Prop Kopenhagen" na lista. */
export interface DonoDaCaptacao {
  telefone: string; lid: string | null; nome: string | null; condominio: string | null
  codigo: string | null; bairro: string | null; tipo: string | null; captacaoId: number; imoveis: number
}

export async function donosDaCaptacao(): Promise<DonoDaCaptacao[]> {
  const r = await naydb().query('SELECT * FROM crm_captacao_donos()')
  return r.rows.map((l: any) => ({
    telefone: String(l.telefone || ''), lid: l.chat_lid ?? null, nome: l.nome ?? null, condominio: l.condominio ?? null,
    codigo: l.codigo ?? null, bairro: l.bairro ?? null, tipo: l.tipo ?? null, captacaoId: Number(l.captacao_id),
    imoveis: Number(l.imoveis || 1),
  }))
}

/** Os imóveis do dono da captação e a ficha aberta da conversa (migração 181), para o card. */
export interface ImovelDoDono {
  codigo: number; condominio: string | null; tipo: string | null; bairro: string | null; status: string | null
  disponivel: boolean | null; parceiro: boolean; aluguel: number | null; venda: number | null
  capa: string | null; fotos: number; daCampanha: boolean
}
export interface FichaDoDono { id: number; tipo: string; codigo: number | null; estado: string; dados: Record<string, any>; fotos: number }

export async function imoveisDoDono(captacaoId: number): Promise<{ imoveis: ImovelDoDono[]; ficha: FichaDoDono | null }> {
  const [a, b] = await Promise.all([
    naydb().query('SELECT * FROM crm_captacao_imoveis_do_dono($1::bigint)', [captacaoId]),
    naydb().query('SELECT * FROM crm_captacao_ficha_do_dono($1::bigint)', [captacaoId]),
  ])
  const num = (x: unknown) => (x === null || x === undefined ? null : Number(x))
  const f = b.rows[0]
  return {
    imoveis: a.rows.map((l: any) => ({
      codigo: Number(l.codigo), condominio: l.condominio ?? null, tipo: l.tipo ?? null, bairro: l.bairro ?? null,
      status: l.status ?? null, disponivel: l.disponivel ?? null, parceiro: !!l.e_parceiro,
      aluguel: num(l.valor_aluguel), venda: num(l.valor_venda), capa: l.capa ?? null, fotos: Number(l.fotos || 0),
      daCampanha: !!l.da_campanha,
    })),
    ficha: f ? { id: Number(f.ficha_id), tipo: String(f.tipo), codigo: num(f.codigo), estado: String(f.estado), dados: f.dados || {}, fotos: Number(f.fotos || 0) } : null,
  }
}

/** Os números da barra da captação (migração 178). As etapas são as do funil do CRM. */
export interface PlacarDaCaptacao {
  disparosHoje: number; falharamHoje: number; pessoasHoje: number
  naoRespondeu: number; respondeu: number; disponivel: number; alugado: number; vendido: number; mandouDados: number
  outroImovel: number; fila: number; total: number; sairam: number; comErro: number
  modoTeste: boolean; pausada: boolean
  // 188: o dia e o total separados, e as mensagens enviadas pelo número
  tetoHoje: number; enviadasHoje: number; enviadasHojeDisparo: number; enviadasHojeNay: number; enviadasHojeEquipe: number
  enviadasTotal: number; nuncaChamados: number; perguntarDeNovo: number
}

export async function placarDaCaptacao(): Promise<PlacarDaCaptacao> {
  const r = await naydb().query('SELECT * FROM crm_captacao_placar()')
  const l = r.rows[0] || {}
  const n = (x: unknown) => Number(x || 0)
  return {
    disparosHoje: n(l.disparos_hoje), falharamHoje: n(l.falharam_hoje), pessoasHoje: n(l.pessoas_hoje),
    naoRespondeu: n(l.nao_respondeu), respondeu: n(l.respondeu), disponivel: n(l.disponivel),
    alugado: n(l.alugado), vendido: n(l.vendido), mandouDados: n(l.mandou_dados),
    outroImovel: n(l.outro_imovel), fila: n(l.fila), total: n(l.total), sairam: n(l.sairam), comErro: n(l.com_erro),
    modoTeste: !!l.modo_teste, pausada: !!l.pausada,
    tetoHoje: n(l.teto_hoje), enviadasHoje: n(l.enviadas_hoje), enviadasHojeDisparo: n(l.enviadas_hoje_disparo),
    enviadasHojeNay: n(l.enviadas_hoje_nay), enviadasHojeEquipe: n(l.enviadas_hoje_equipe), enviadasTotal: n(l.enviadas_total),
    nuncaChamados: n(l.nunca_chamados), perguntarDeNovo: n(l.perguntar_de_novo),
  }
}

/**
 * O relatório da captação -- o mesmo texto do das 18h, para o mesmo número
 * (captacao_config.telefone_relatorio). O telefone fica no servidor: a tela só
 * vê o texto.
 */
export async function relatorioDaCaptacao(): Promise<{ telefone: string | null; mensagem: string }> {
  const r = await naydb().query('SELECT * FROM crm_captacao_relatorio()')
  const l = r.rows[0] || {}
  return { telefone: l.telefone ? String(l.telefone) : null, mensagem: String(l.mensagem || '') }
}
