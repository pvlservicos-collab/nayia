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

import type { EstadoDaNay, EventoDaVisita, ImovelEnviado, ItemDoHistorico, MarcaDaNay, VisitaDaNay, VisitaNaTela } from './tiposNay'
export type { EstadoDaNay, EventoDaVisita, ImovelEnviado, ItemDoHistorico, MarcaDaNay, VisitaDaNay } from './tiposNay'

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
      checklist: l.checklist === true,
      // preenchidos logo abaixo, pela 197
      visitaRayssa: false,
      fechamentoId: null,
      fechamentoDesde: null,
      acompanhante: false,
    })
  }

  /* O QUE A NAY PASSOU À RAYSSA (migração 197, sessão nay-ia-1b).
   *
   * "Visita aberta" NÃO é a etapa Visitas: enquanto a Nay ainda coleta e
   * confirma, ela continua atendendo o corretor. A conversa só vira Visitas
   * quando o corretor confirma e a visita passa para a Rayssa
   * (`visita_rayssa`) -- é daí até a hora da visita + 120 min que a Nay se
   * cala. Fechamento é o mesmo: quem manda é `nai_fechamento`, que sabe
   * quando a Rayssa conclui e devolve a pessoa para Todos. A marca
   * `checklist` sozinha não sabe disso e prenderia a conversa para sempre. */
  const rr = await naydb().query('SELECT * FROM crm_parceria_com_a_rayssa($1::text[])', [unicos])
  for (const l of rr.rows) {
    const m = mapa.get(String(l.telefone))
    if (!m) continue
    m.visitaRayssa = l.visita_rayssa === true
    m.fechamentoId = l.fechamento_id != null ? Number(l.fechamento_id) : null
    m.fechamentoDesde = iso(l.fechamento_desde)
    m.acompanhante = l.acompanhante === true
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
  // 250: a duração e quem agendou à mão vêm à parte, para não mexer na crm_visitas
  const extra = new Map<number, { duracaoMin: number | null; criadaNoCrmPor: string | null }>()
  if (r.rows.length) {
    const e = await naydb().query('SELECT * FROM crm_visitas_extra($1::bigint[])', [r.rows.map((l: any) => Number(l.id))])
    for (const l of e.rows as any[]) {
      extra.set(Number(l.id), { duracaoMin: l.duracao_min != null ? Number(l.duracao_min) : null, criadaNoCrmPor: l.criada_no_crm_por ?? null })
    }
  }
  return r.rows.map((l: any) => ({
    ...(extra.get(Number(l.id)) || {}),
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

/**
 * 513 (Pedro, 28/10): AS VISITAS DA NAY LEADS (número 8595, privado.olx_visita) na mesma agenda. Chegam com id
 * NEGATIVO (-id) e linha 'leads'; quem mexe nelas é a Nay Leads, então aqui só se lê. Sem a 513 no banco a função
 * não existe: a agenda segue só com as da Parceria.
 */
export async function visitasDosLeads(desde?: string | null, ate?: string | null): Promise<VisitaNaTela[]> {
  let r
  try {
    r = await naydb().query('SELECT * FROM crm_visitas_leads($1::date, $2::date)', [desde || null, ate || null])
  } catch (e: any) {
    if (e?.code === '42883') return []          // a função ainda não existe (antes da 513)
    throw e
  }
  return r.rows.map((l: any) => ({
    id: -Number(l.id),
    linha: 'leads' as const,
    codigo: l.codigo != null ? Number(l.codigo) : null,
    imovel: l.imovel ?? null,
    estado: String(l.estado),
    aberta: l.aberta === true,
    aguardando: null, urgente: false, acesso: null,
    quando: iso(l.quando), quandoSugerido: null,
    criadoEm: iso(l.criado_em),
    confirmadaCorretorEm: null, aprovadaEm: null, aprovadaPor: null, propOkEm: null, motoOkEm: null,
    confirmadaEm: iso(l.confirmada_em),
    posVisitaEm: iso(l.realizada_em), encerradaEm: null,
    atualizadoEm: iso(l.atualizado_em),
    resultado: null, motivo: null,
    corretorNome: l.corretor_nome ?? null,
    proprietarioNome: l.proprietario_nome ?? null,
    visitanteNome: l.cliente_nome ?? null,
    clienteNome: l.cliente_nome ?? null,
    clienteTelefone: l.cliente_telefone ?? null,
    clienteConfirmouEm: iso(l.cliente_confirmou_em),
    realizadaEm: iso(l.realizada_em),
    realizadaPor: l.realizada_por ?? null,
    feedbackPara: l.feedback_para ?? null,
    feedbackEm: iso(l.feedback_em),
    conversa: null,
    corretorTelefone: l.corretor_telefone ?? null,
    dono: l.proprietario_telefone || l.proprietario_nome
      ? { telefone: l.proprietario_telefone ?? null, leadId: null, avatar: null } : null,
  }))
}

/** 513: o VISITA REALIZADA de uma visita da Nay Leads; a Nay pergunta "como foi?" ao cliente ou ao corretor. */
/** 587 (v2, aba Proprietários): o nome de cada imóvel (condomínio, ou tipo e bairro) pelo código. */
export async function nomesDosImoveis(codigos: number[]): Promise<Record<number, string>> {
  if (!codigos.length) return {}
  const r = await naydb().query('SELECT codigo, nome FROM crm_imoveis_nomes($1::int[])', [codigos.slice(0, 500)])
  return Object.fromEntries(r.rows.filter((x: any) => x.nome).map((x: any) => [Number(x.codigo), String(x.nome)]))
}

/** 587 (v2, aba Visita › Status da visita › Cancelada): a visita da Nay Leads deixa de valer; ninguém é avisado. */
export async function visitaDosLeadsCancelar(id: number, quem: string): Promise<{ ok: boolean; mensagem: string }> {
  const r = await naydb().query('SELECT * FROM crm_visita_leads_cancelar($1::bigint, $2::text)', [id, quem])
  const l = r.rows[0]
  return { ok: l?.ok === true, mensagem: l?.mensagem || 'Não consegui cancelar a visita.' }
}

export async function visitaDosLeadsRealizada(id: number, para: 'cliente' | 'corretor', quem: string): Promise<{ ok: boolean; mensagem: string }> {
  try {
    const r = await naydb().query('SELECT * FROM crm_visita_leads_realizada($1::bigint, $2::text, $3::text)', [id, para, quem])
    const l = r.rows[0]
    return { ok: l?.ok === true, mensagem: l?.mensagem || 'Não consegui marcar a visita.' }
  } catch (e: any) {
    if (e?.code === '42883') return { ok: false, mensagem: 'O banco da Nay ainda não tem o VISITA REALIZADA dos Leads (migração 513).' }
    throw e
  }
}

/** 293: por visita, o telefone do corretor e o do proprietário (com as chaves dele, para achar a conversa). */
export async function pessoasDasVisitas(ids: number[]) {
  const mapa = new Map<number, { corretorTelefone: string | null; donoTelefone: string | null; donoChaves: string[] }>()
  if (!ids.length) return mapa
  const r = await naydb().query('SELECT * FROM crm_visitas_pessoas($1::bigint[])', [ids])
  for (const l of r.rows as any[]) {
    mapa.set(Number(l.id), {
      corretorTelefone: l.corretor_telefone ?? null,
      donoTelefone: l.proprietario_telefone ?? null,
      donoChaves: Array.isArray(l.proprietario_chaves) ? l.proprietario_chaves.map(String) : [],
    })
  }
  return mapa
}

/**
 * AGENDAR VISITA À MÃO (Pedro, 01/10/2026; migração 250). A visita nasce da
 * equipe ('com_rayssa'): a Nay não manda nada sozinha -- quem avisa é o
 * lembrete que a pessoa marca no CRM. Devolve o telefone do dono e do corretor
 * SÓ para o servidor achar a conversa de cada um; não vai para a tela.
 */
export interface VisitaAgendada {
  ok: boolean; mensagem: string; visita: number | null
  corretorTelefone: string | null; corretorNome: string | null
  proprietarioTelefone: string | null; proprietarioNome: string | null
  imovel: string | null; imovelDoDono: string | null
}

export async function agendarVisita(codigo: number, corretorTelefone: string, corretorNome: string | null,
                                    quando: Date, duracaoMin: number, quem: string): Promise<VisitaAgendada> {
  const r = await naydb().query(
    'SELECT * FROM crm_visita_agendar($1::int, $2::text, $3::text, $4::timestamptz, $5::int, $6::text)',
    [codigo, corretorTelefone, corretorNome, quando.toISOString(), duracaoMin, quem])
  const l = r.rows[0] || {}
  return {
    ok: l.ok === true, mensagem: String(l.mensagem || 'Sem resposta da Nay.'),
    visita: l.visita != null ? Number(l.visita) : null,
    corretorTelefone: l.corretor_telefone ?? null, corretorNome: l.corretor_nome ?? null,
    proprietarioTelefone: l.proprietario_telefone ?? null, proprietarioNome: l.proprietario_nome ?? null,
    imovel: l.imovel ?? null, imovelDoDono: l.imovel_do_dono ?? null,
  }
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
export type AcaoNaVisita = 'horario' | 'realizada' | 'excluir' | 'proprietario_ok'

export async function mexerNaVisita(
  id: number, acao: AcaoNaVisita, quem: string, quando?: Date,
): Promise<{ ok: boolean; mensagem: string }> {
  const r = acao === 'horario'
    ? await naydb().query('SELECT * FROM crm_visita_mudar_horario($1::bigint, $2::timestamptz, $3::text)', [id, quando!.toISOString(), quem])
    : acao === 'realizada'
      ? await naydb().query('SELECT * FROM crm_visita_realizada($1::bigint, $2::text)', [id, quem])
      : acao === 'proprietario_ok'
        // 468 (22/10): o dono confirmou (por telefone, por exemplo): a Nay avisa o acompanhante
        ? await naydb().query('SELECT * FROM crm_visita_proprietario_ok($1::bigint, $2::text)', [id, quem])
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

/** Visitas do WhatsApp Leads (8595) marcadas para hoje, em Manaus, sem as que caíram (a mesma conta da Parceria). */
export async function visitasLeadsHoje(): Promise<number> {
  const r = await naydb().query(
    `SELECT count(*)::int AS n FROM crm_visitas_leads((now() AT TIME ZONE 'America/Manaus')::date - 1, (now() AT TIME ZONE 'America/Manaus')::date + 1) v
      WHERE (v.quando AT TIME ZONE 'America/Manaus')::date = (now() AT TIME ZONE 'America/Manaus')::date
        AND v.estado NOT IN ('cancelada', 'expirada', 'sem_corretor', 'sem_proprietario')`)
  return Number(r.rows[0]?.n || 0)
}

/** 02/11 (Pedro: "troca o contador de visitas de por dia para semana: Parceria 10, Leads 5"): as visitas marcadas de segunda a
 *  domingo da semana de agora, em Manaus, sem as que caíram (a mesma conta de "hoje"). */
export async function visitasDaSemana(): Promise<{ parceria: number; leads: number }> {
  const ini = `(date_trunc('week', now() AT TIME ZONE 'America/Manaus'))::date`
  const [p, l] = await Promise.all([
    naydb().query(
      `SELECT count(*)::int AS n FROM nai_visita v
        WHERE v.excluida_em IS NULL AND v.estado NOT IN ('cancelada', 'expirada', 'coletando')
          AND (v.quando AT TIME ZONE 'America/Manaus')::date >= ${ini} AND (v.quando AT TIME ZONE 'America/Manaus')::date < ${ini} + 7`),
    naydb().query(
      `SELECT count(*)::int AS n FROM crm_visitas_leads(${ini} - 1, ${ini} + 8) v
        WHERE (v.quando AT TIME ZONE 'America/Manaus')::date >= ${ini} AND (v.quando AT TIME ZONE 'America/Manaus')::date < ${ini} + 7
          AND v.estado NOT IN ('cancelada', 'expirada', 'sem_corretor', 'sem_proprietario')`),
  ])
  return { parceria: Number(p.rows[0]?.n || 0), leads: Number(l.rows[0]?.n || 0) }
}

/** "Parar Nay" / "Nay voltar a atender" no card do contato (migração 176). */
export async function pararOuDevolverANay(telefone: string, acao: 'parar' | 'voltar', quem: string): Promise<{ ok: boolean; mensagem: string }> {
  const fn = acao === 'parar' ? 'crm_nay_parar' : 'crm_nay_voltar'
  const r = await naydb().query(`SELECT * FROM ${fn}($1::text, $2::text)`, [telefone, quem])
  const l = r.rows[0]
  return { ok: !!l?.ok, mensagem: String(l?.mensagem || 'Sem resposta da Nay.') }
}

/** "Nay atender com instrução" (migração 235): guarda a instrução por 48 h e solta a Nay. */
export async function instruirANay(telefone: string, texto: string, quem: string): Promise<{ ok: boolean; mensagem: string }> {
  const r = await naydb().query('SELECT * FROM crm_nay_instruir($1::text, $2::text, $3::text)', [telefone, texto, quem])
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

/** Os imóveis que já saíram para a pessoa, do mais recente para o mais antigo (migração 292). */
export async function imoveisEnviados(telefone: string): Promise<ImovelEnviado[]> {
  const r = await naydb().query('SELECT * FROM crm_imoveis_enviados($1::text)', [telefone])
  return r.rows.map((l: any) => ({
    codigo: Number(l.codigo),
    imovel: l.imovel ?? null,
    ultimoEm: iso(l.ultimo_em) || '',
    primeiroEm: iso(l.primeiro_em) || '',
    dias: Number(l.dias || 1),
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
  /** as abas da captação em que a IA pôs a pessoa (migração 236) */
  abas: string[]
  /** a etapa escolhida à mão no CRM, quando alguém escolheu (migração 242) */
  etapaManual: string | null
}

export async function donosDaCaptacao(): Promise<DonoDaCaptacao[]> {
  const r = await naydb().query('SELECT * FROM crm_captacao_donos()')
  return r.rows.map((l: any) => ({
    telefone: String(l.telefone || ''), lid: l.chat_lid ?? null, nome: l.nome ?? null, condominio: l.condominio ?? null,
    codigo: l.codigo ?? null, bairro: l.bairro ?? null, tipo: l.tipo ?? null, captacaoId: Number(l.captacao_id),
    imoveis: Number(l.imoveis || 1),
    abas: Array.isArray(l.abas) ? l.abas.map(String) : [],
    etapaManual: l.etapa_manual ?? null,
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

/* ===================================================================
 * O CADASTRO PELO CARD DA CAPTAÇÃO (migração 246, Pedro 01/10/2026)
 * =================================================================== */

export interface CondominioDaLista {
  id: number; nome: string; bairro: string | null; endereco: string | null
  /** de onde veio o endereço: 'ficha' (condominio_ficha) ou 'imoveis' (a moda do logradouro) */
  enderecoDe: 'ficha' | 'imoveis' | null
  /** de quantos imóveis saiu o endereço, quando saiu dos imóveis */
  base: number; cidade: string; estado: string; imoveis: number
  andares: string | null; elevador: string | null; torres: string | null; construtora: string | null
  lazer: string[]
}
export interface RascunhoParaPuxar {
  codigo: number; tipo: string; bairro: string; condominio: string; condoId: number | null
  origem: string; aluguel: number; venda: number; fotos: number; dono: string | null; criado: string | null
}
export interface OpcoesDoCadastro {
  condominios: CondominioDaLista[]
  caracteristicas: Array<{ nome: string; usos: number }>
  tipos: string[]
  bairros: string[]
  rascunhos: RascunhoParaPuxar[]
}

/* A lista é grande (483 condomínios) e muda pouco: guardada por 5 minutos
   nesta instância, para o popup abrir na hora. */
let opcoesGuardadas: { em: number; dados: OpcoesDoCadastro } | null = null

export async function opcoesDoCadastro(): Promise<OpcoesDoCadastro> {
  if (opcoesGuardadas && Date.now() - opcoesGuardadas.em < 5 * 60_000) return opcoesGuardadas.dados
  const r = await naydb().query('SELECT crm_captacao_cadastro_opcoes() AS o')
  const o = (r.rows[0]?.o || {}) as any
  const dados: OpcoesDoCadastro = {
    condominios: Array.isArray(o.condominios) ? o.condominios : [],
    caracteristicas: Array.isArray(o.caracteristicas) ? o.caracteristicas : [],
    tipos: Array.isArray(o.tipos) ? o.tipos.filter(Boolean).sort((a: string, b: string) => a.localeCompare(b, 'pt-BR')) : [],
    bairros: Array.isArray(o.bairros) ? o.bairros : [],
    rascunhos: Array.isArray(o.rascunhos) ? o.rascunhos : [],
  }
  opcoesGuardadas = { em: Date.now(), dados }
  return dados
}

/** O "preencher automático": o condomínio que a pessoa citou no texto. */
export async function condominioPeloTexto(texto: string): Promise<Array<{ id: number; nome: string; bairro: string | null }>> {
  const t = String(texto || '').slice(0, 4000)
  if (t.trim().length < 4) return []
  const r = await naydb().query('SELECT * FROM crm_condominio_pelo_texto($1::text)', [t])
  return r.rows.map((l: any) => ({ id: Number(l.id), nome: String(l.nome), bairro: l.bairro ?? null }))
}

/** Quanto cada imóvel está preenchido, 0 a 100% -- a mesma régua da aba Imóveis (244). */
export interface PontuacaoDoImovel { codigo: number; pct: number; falta: string[]; faltaEssencial: string[] }

export async function pontuacaoDosImoveis(codigos: number[]): Promise<Record<number, PontuacaoDoImovel>> {
  const limpos = Array.from(new Set((codigos || []).map(Number).filter((n) => Number.isInteger(n) && n > 0)))
  if (!limpos.length) return {}
  const r = await naydb().query('SELECT * FROM crm_imoveis_pontuacao($1::int[])', [limpos])
  const mapa: Record<number, PontuacaoDoImovel> = {}
  for (const l of r.rows as any[]) {
    mapa[Number(l.codigo)] = {
      codigo: Number(l.codigo), pct: Number(l.pct || 0),
      falta: Array.isArray(l.falta) ? l.falta.map(String) : [],
      faltaEssencial: Array.isArray(l.falta_essencial) ? l.falta_essencial.map(String) : [],
    }
  }
  return mapa
}

/** O que a campanha sabe do corretor, para o card (migração 247). */
export async function donoDaCampanha(captacaoId: number): Promise<Record<string, any> | null> {
  const r = await naydb().query('SELECT crm_captacao_dono_cadastro($1::bigint) AS d', [captacaoId])
  return (r.rows[0]?.d as Record<string, any>) || null
}

/** Os campos de hoje de um imóvel, para o popup abrir preenchido. */
export async function imovelParaCadastro(codigo: number): Promise<Record<string, any> | null> {
  const r = await naydb().query('SELECT crm_imovel_para_cadastro($1::int) AS i', [codigo])
  return (r.rows[0]?.i as Record<string, any>) || null
}

/** A etapa da captação escolhida à mão (migração 242). */
export async function escolherEtapaDaCaptacao(telefone: string, etapa: string, quem: string): Promise<{ ok: boolean; mensagem: string }> {
  const r = await naydb().query('SELECT * FROM crm_captacao_etapa_manual($1::text, $2::text, $3::text)', [telefone, etapa, quem])
  const l = r.rows[0]
  return { ok: !!l?.ok, mensagem: String(l?.mensagem || 'Sem resposta.') }
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

/**
 * ONDE CADA CORRETOR PAROU (migração 203, sessão nay-ia-1b): o resumo da
 * conversa e o próximo passo, da revisão de 30/09. É o que falta para quem
 * abre uma conversa velha saber o que já foi dito.
 */
export interface Retomada {
  etapa: string | null
  resumo: string | null
  proximoPasso: string | null
  imoveis: number[]
  criadoEm: string | null
  validoAte: string | null
}

export async function retomadaDaParceria(telefones: string[]): Promise<Map<string, Retomada>> {
  const mapa = new Map<string, Retomada>()
  const unicos = Array.from(new Set(telefones.filter(Boolean)))
  if (!unicos.length) return mapa
  const r = await naydb().query('SELECT * FROM crm_parceria_retomada($1::text[])', [unicos])
  for (const l of r.rows) {
    mapa.set(String(l.telefone), {
      etapa: l.etapa ?? null,
      resumo: l.resumo ?? null,
      proximoPasso: l.proximo_passo ?? null,
      imoveis: Array.isArray(l.imoveis) ? l.imoveis.map(Number) : [],
      criadoEm: iso(l.criado_em),
      validoAte: iso(l.valido_ate),
    })
  }
  return mapa
}

/**
 * A ETAPA ESCOLHIDA À MÃO, DITA À NAY (migração 201).
 *
 * Sem isto, escolher a etapa no card só organizava a lista: a Nay continuava
 * respondendo quem estava "preso" em Fechamento. Agora a escolha cala ou
 * solta a Nay de verdade -- 'visitas' por 7 dias, 'tel' até o DEVOLVER,
 * 'todos' devolve a conversa a ela.
 *
 * Nunca derruba quem chamou: a etapa no CRM já foi gravada, e perder o aviso
 * à Nay é ruim, mas perder a mudança que a pessoa fez na tela é pior.
 */
export async function marcarEtapaNaNay(telefone: string, etapa: string, quem: string): Promise<string | null> {
  if (!telefone) return null
  try {
    const r = await naydb().query('SELECT * FROM crm_etapa_manual($1::text, $2::text, $3::text)',
      [telefone, etapa, quem.slice(0, 60)])
    const l = r.rows[0]
    return l?.ok === true ? (l.mensagem ?? null) : null
  } catch (err: any) {
    console.error('[etapa manual] a Nay não recebeu', err?.message || err)
    return null
  }
}

/**
 * O DISPARO PELA API OFICIAL (migração 331; Pedro, 09/10: "uma barrinha para eu saber qual lista está sendo
 * disparada e quanto falta para acabar"). As listas da fila do Python, na ordem em que saem, com quantos já
 * receberam o modelo e quantos faltam; e se está saindo agora. null quando a função ainda não existe no banco.
 */
export interface ListaDoDisparo { chave: string; rotulo: string; titulo: string; enviados: number; faltam: number }
export interface DisparoOficial {
  ligado: boolean; motivo: string | null; voltaEm: string | null
  hoje: number; falharamHoje: number; ultimoEm: string | null; segMedio: number
  listas: ListaDoDisparo[]
}
export async function disparoOficial(): Promise<DisparoOficial | null> {
  try {
    const r = await naydb().query('SELECT crm_captacao_disparo_oficial() AS d')
    const d = r.rows[0]?.d
    if (!d) return null
    const n = (x: unknown) => Number(x || 0)
    return {
      ligado: !!d.ligado, motivo: d.motivo ?? null, voltaEm: d.volta_em ?? null,
      hoje: n(d.hoje), falharamHoje: n(d.falharam_hoje), ultimoEm: d.ultimo_em ?? null, segMedio: n(d.seg_medio) || 60,
      listas: (d.listas || []).map((l: any) => ({ chave: String(l.chave), rotulo: String(l.rotulo), titulo: String(l.titulo || ''),
                                                  enviados: n(l.enviados), faltam: n(l.faltam) })),
    }
  } catch (e: any) {
    if (e?.code === '42883') return null   // a 331 ainda não foi aplicada: a barra não aparece
    throw e
  }
}
