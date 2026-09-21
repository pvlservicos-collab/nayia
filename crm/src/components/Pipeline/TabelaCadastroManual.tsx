'use client'

/**
 * Cadastro manual de leads em tabela — diálogo centralizado na tela.
 *
 * Por que tabela e não um formulário por lead: quem cadastra à mão quase nunca
 * tem um lead só. São os nomes que chegaram por mensagem, a lista que alguém
 * passou, o formulário que falhou. Uma linha por pessoa, tudo de uma vez, com
 * teclado — Tab anda entre as células e Enter cria a linha seguinte.
 *
 * Três decisões que valem explicação:
 *
 *   - "Disparar mensagem" nasce DESLIGADO. Cadastro manual é quase sempre
 *     registro do que já aconteceu, e mandar sem querer é irreversível: a
 *     mensagem chega no WhatsApp de gente de verdade.
 *   - "Qual WhatsApp" é só marcação. Hoje só o número do CRM está conectado;
 *     escolher "Michele" registra de quem é o lead, não muda quem envia.
 *   - Os padrões ficam no topo e valem para as linhas NOVAS; cada linha pode
 *     ser mudada depois, e "aplicar a todas" reescreve as que já estão lá.
 *
 * Serve também de "Adicionar ao pipeline" na aba Leads (modo `pipeline`): aí o
 * lead JÁ existe, e a tabela só pergunta de quem ele é e em que momento está —
 * sem interruptor de disparo, porque ali nada é enviado, nunca.
 *
 * Grava pela mesma porta das fontes externas (POST /api/ingest/leads/<fonte>),
 * uma linha por vez: é o que garante o mesmo dedupe, a mesma normalização de
 * telefone e o mesmo registro em lead_source_submissions. Linha que falha fica
 * na tabela com o erro do lado, para corrigir e mandar de novo — nada se perde.
 */

import { useEffect, useRef, useState } from 'react'
import { X, Plus, Trash, UploadSimple, CheckCircle, WarningCircle, Table } from '@phosphor-icons/react'
import { useAuth } from '@/hooks'
import { LEAD_SOURCES, type LeadSourceKey } from '@/lib/leadSources'
import { MOMENTOS, MOMENTO_PADRAO } from '@/lib/momentos'
import { EQUIPE_ATENDIMENTO, RESPONSAVEL_PADRAO } from '@/lib/atendentes'

/** Fontes com funil — só nelas o interruptor de disparo faz alguma coisa. */
const FONTES_COM_AUTOMACAO: LeadSourceKey[] = ['agenda_ascensao', 'site_evento']

const AVISO_IMPORTACAO = 'Mande para o pedro primeiro para ele preparar a integração comigo'

interface Linha {
  id: number
  /** Lead que já existe (modo `pipeline`); vazio quando é cadastro novo. */
  leadId?: string
  nome: string
  whatsapp: string
  momento: string
  indicadoPor: string
  disparar: boolean
  responsavel: string
  estado: 'novo' | 'enviando' | 'ok' | 'erro'
  erro?: string
}

interface Padroes {
  momento: string
  disparar: boolean
  responsavel: string
}

let proximoId = 1
function novaLinha(padroes: Padroes): Linha {
  return {
    id: proximoId++,
    nome: '',
    whatsapp: '',
    momento: padroes.momento,
    indicadoPor: '',
    disparar: padroes.disparar,
    responsavel: padroes.responsavel,
    estado: 'novo',
  }
}

const soDigitos = (texto: string) => texto.replace(/\D/g, '')
// 10 dígitos = fixo com DDD, 11 = celular. Menos que isso não dá pra falar com
// a pessoa, e é melhor barrar aqui do que gravar um lead inalcançável.
const estaPronta = (l: Linha) => l.nome.trim().length > 1 && soDigitos(l.whatsapp).length >= 10
const estaEmBranco = (l: Linha) => !l.nome.trim() && !soDigitos(l.whatsapp)

interface Props {
  source: LeadSourceKey
  onClose: () => void
  /** Chamado depois de gravar, pra lista recarregar. */
  onCreated: () => void
  /** Abre o formulário completo de um lead só (Instagram, e-mail, observação). */
  onCadastroCompleto?: () => void
  /**
   * `cadastro` (padrão) cria leads novos pela fonte.
   * `pipeline` põe no quadro leads que já existem — nada é enviado.
   */
  modo?: 'cadastro' | 'pipeline'
  /** Linhas já preenchidas (o lead clicado na aba Leads). */
  linhasIniciais?: { nome: string; whatsapp: string; momento?: string | null; leadId?: string }[]
}

export default function TabelaCadastroManual({
  source,
  onClose,
  onCreated,
  onCadastroCompleto,
  modo = 'cadastro',
  linhasIniciais,
}: Props) {
  const { profileName } = useAuth()
  const fonte = LEAD_SOURCES[source]
  const ehPipeline = modo === 'pipeline'
  const ehIndicacao = source === 'indicacao' && !ehPipeline
  // No modo pipeline o momento vale pra qualquer fonte: é a informação que a
  // aba Leads mostra, e quem adiciona ao quadro quer confirmar ou corrigir.
  const temMomento = ehPipeline || source === 'agenda_ascensao'
  // Nada é enviado ao pôr no quadro — o interruptor nem aparece.
  const temAutomacao = !ehPipeline && FONTES_COM_AUTOMACAO.includes(source)

  const [padroes, setPadroes] = useState<Padroes>({
    momento: MOMENTO_PADRAO,
    disparar: false,
    responsavel: RESPONSAVEL_PADRAO,
  })
  const padroesIniciais: Padroes = {
    // Vindo da aba Leads, o momento comeca com o que o lead ja tem — inclusive
    // "nao definido". Inventar "so se cadastrou" pra quem veio do site seria
    // gravar um dado que ninguem informou.
    momento: modo === 'pipeline' ? '' : MOMENTO_PADRAO,
    disparar: false,
    responsavel: RESPONSAVEL_PADRAO,
  }
  const [linhas, setLinhas] = useState<Linha[]>(() => {
    if (linhasIniciais?.length) {
      return linhasIniciais.map((l) => ({
        ...novaLinha(padroesIniciais),
        nome: l.nome,
        whatsapp: l.whatsapp,
        momento: l.momento || '',
        leadId: l.leadId,
      }))
    }
    return [novaLinha(padroesIniciais), novaLinha(padroesIniciais), novaLinha(padroesIniciais)]
  })
  const [salvando, setSalvando] = useState(false)
  const [resumo, setResumo] = useState<string | null>(null)
  const primeiraCelulaRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    primeiraCelulaRef.current?.focus()
  }, [])

  // Esc fecha. Clique fora não fecha de propósito: são dados digitados à mão, e
  // perder dez linhas por um clique torto no Kanban seria péssimo.
  useEffect(() => {
    const aoTeclar = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose()
    }
    document.addEventListener('keydown', aoTeclar)
    return () => document.removeEventListener('keydown', aoTeclar)
  }, [onClose])

  const preenchidas = linhas.filter((l) => !estaEmBranco(l))
  const prontas = preenchidas.filter(estaPronta)
  const incompletas = preenchidas.filter((l) => !estaPronta(l))

  const mudar = (id: number, campos: Partial<Linha>) =>
    setLinhas((atual) =>
      atual.map((l) => (l.id === id ? { ...l, ...campos, estado: 'novo', erro: undefined } : l))
    )

  const remover = (id: number) =>
    setLinhas((atual) => (atual.length > 1 ? atual.filter((l) => l.id !== id) : [novaLinha(padroes)]))

  const acrescentar = () => setLinhas((atual) => [...atual, novaLinha(padroes)])

  const aplicarPadroesEmTodas = () =>
    setLinhas((atual) =>
      atual.map((l) => ({
        ...l,
        momento: padroes.momento,
        disparar: padroes.disparar,
        responsavel: padroes.responsavel,
      }))
    )

  /** Digitar na última linha já prepara a próxima — jeito de planilha. */
  const garantirLinhaLivre = (id: number) =>
    setLinhas((atual) => (atual[atual.length - 1]?.id === id ? [...atual, novaLinha(padroes)] : atual))

  async function cadastrar() {
    if (prontas.length === 0 || salvando) return
    setSalvando(true)
    setResumo(null)

    let gravados = 0
    for (const linha of prontas) {
      setLinhas((atual) => atual.map((l) => (l.id === linha.id ? { ...l, estado: 'enviando' } : l)))
      try {
        // Lead que já existe: só entra no quadro e recebe as marcações. Não
        // passa pela ingestão, que criaria/reenviaria o que já está gravado.
        if (ehPipeline && linha.leadId) {
          const res = await fetch(`/api/leads/${linha.leadId}/pipeline`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              whatsapp_responsavel: linha.responsavel,
              ...(linha.momento ? { momento: linha.momento } : {}),
            }),
          })
          const retorno = await res.json().catch(() => ({}))
          if (!res.ok) throw new Error(retorno?.error || `Erro ${res.status}`)
          gravados++
          setLinhas((atual) => atual.map((l) => (l.id === linha.id ? { ...l, estado: 'ok' } : l)))
          continue
        }

        const digitos = soDigitos(linha.whatsapp)
        const corpo: Record<string, unknown> = {
          nome: linha.nome.trim(),
          whatsapp: linha.whatsapp.trim(),
          cadastrado_por: profileName || null,
          whatsapp_responsavel: linha.responsavel,
          // A Agenda identifica o lead por um id que o site dela gera, e exige
          // um. O cadastro manual cria o seu, preso ao telefone: registrar a
          // mesma pessoa de novo atualiza em vez de duplicar. O momento vai no
          // mesmo lugar que a Agenda usa (agenda.phase).
          ...(source === 'agenda_ascensao'
            ? { id: `manual-${digitos}`, ...(linha.momento ? { agenda: { phase: linha.momento } } : {}) }
            : {}),
          ...(ehIndicacao && linha.indicadoPor.trim() ? { indicado_por: linha.indicadoPor.trim() } : {}),
          // A ingestão só pula o funil quando mandam pular (src/lib/ingest.ts).
          ...(temAutomacao && !linha.disparar ? { sem_automacao: true } : {}),
        }
        const res = await fetch(`/api/ingest/leads/${source}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(corpo),
        })
        const retorno = await res.json().catch(() => ({}))
        if (!res.ok) throw new Error(retorno?.error || `Erro ${res.status}`)
        gravados++
        setLinhas((atual) => atual.map((l) => (l.id === linha.id ? { ...l, estado: 'ok' } : l)))
      } catch (err: any) {
        setLinhas((atual) =>
          atual.map((l) => (l.id === linha.id ? { ...l, estado: 'erro', erro: err?.message || 'Falhou' } : l))
        )
      }
    }

    setSalvando(false)
    if (gravados > 0) onCreated()

    const falhas = prontas.length - gravados
    setResumo(
      falhas === 0
        ? ehPipeline
          ? `${gravados} ${gravados === 1 ? 'lead adicionado' : 'leads adicionados'} ao pipeline.`
          : `${gravados} ${gravados === 1 ? 'lead cadastrado' : 'leads cadastrados'}.`
        : `${gravados} cadastrados, ${falhas} com erro — corrija e mande de novo.`
    )
    // Some quem deu certo; quem falhou fica pra corrigir.
    if (falhas === 0) {
      // Vindo da aba Leads é uma ação pontual: fecha e volta pra lista.
      if (ehPipeline) {
        onClose()
        return
      }
      setLinhas([novaLinha(padroes), novaLinha(padroes), novaLinha(padroes)])
    } else {
      setLinhas((atual) => atual.filter((l) => l.estado !== 'ok'))
    }
  }

  const celula =
    'w-full bg-transparent border-0 outline-none text-[12.5px] text-ink placeholder-muted/50 px-2 py-1.5 rounded focus:bg-white/[0.06]'

  return (
    /*
     * Centralizado, e não colado no botão que abriu.
     *
     * Colado ficava ruim em tela estreita e em tela cheia: perto do rodapé
     * sobrava pouca altura, e no celular a tabela nascia espremida num canto.
     * Centralizado, a mesma caixa serve pros dois — ela cresce até 860px,
     * respeita as bordas (p-3) e rola por dentro.
     */
    <div
      className="fixed inset-0 z-[80] flex items-center justify-center p-3 sm:p-6"
      role="dialog"
      aria-modal="true"
    >
      {/* Escurece o resto. Clicar aqui fecha; dentro da tabela, nada fecha
          sem querer — são dados digitados à mão. */}
      <div className="absolute inset-0 bg-black/55 backdrop-blur-sm" onClick={onClose} />

      <div className="panel relative z-10 w-full max-w-[860px] max-h-[88vh] rounded-2xl shadow-2xl shadow-black/50 flex flex-col overflow-hidden">
        {/* Cabeçalho */}
        <div className="flex items-center gap-2.5 px-4 py-3 border-b border-white/[0.07] flex-shrink-0">
          <Table size={16} weight="bold" className="text-accent-2 flex-shrink-0" />
          <div className="min-w-0 flex-1">
            <h2 className="text-[13.5px] font-bold text-ink truncate">
              {ehPipeline ? 'Adicionar ao pipeline' : `Cadastrar leads — ${fonte.label}`}
            </h2>
            <p className="text-[10.5px] text-muted">
              {ehPipeline
                ? 'Entra em "Em aguardo". Nenhuma mensagem é enviada.'
                : 'Uma linha por pessoa. Entram no Kanban na primeira etapa, com você como responsável.'}
            </p>
          </div>
          <button type="button" onClick={onClose} className="btn-icon w-8 h-8 flex-shrink-0" aria-label="Fechar">
            <X size={16} />
          </button>
        </div>

        {/* Padrões das linhas novas */}
        <div className="flex items-center flex-wrap gap-x-4 gap-y-2 px-4 py-2.5 border-b border-white/[0.07] bg-white/[0.02] flex-shrink-0">
          <span className="text-[10px] font-bold uppercase tracking-wider text-muted">Padrão</span>

          {temAutomacao && (
            <label className="flex items-center gap-1.5 cursor-pointer" title="Vale para as linhas novas">
              <input
                type="checkbox"
                checked={padroes.disparar}
                onChange={(e) => setPadroes((p) => ({ ...p, disparar: e.target.checked }))}
                className="w-3.5 h-3.5 accent-[var(--blue)]"
              />
              <span className="text-[11.5px] text-ink">Disparar mensagem</span>
            </label>
          )}

          <label className="flex items-center gap-1.5">
            <span className="text-[11.5px] text-muted">WhatsApp:</span>
            <SelectResponsavel
              valor={padroes.responsavel}
              onChange={(v) => setPadroes((p) => ({ ...p, responsavel: v }))}
            />
          </label>

          {temMomento && (
            <label className="flex items-center gap-1.5">
              <span className="text-[11.5px] text-muted">Momento:</span>
              <SelectMomento
                valor={padroes.momento}
                onChange={(v) => setPadroes((p) => ({ ...p, momento: v }))}
                permitirVazio={ehPipeline}
              />
            </label>
          )}

          <button
            type="button"
            hidden={linhas.length < 2}
            onClick={aplicarPadroesEmTodas}
            className="btn btn-outline btn-sm !py-1 !text-[11px] ml-auto"
            title="Reescreve momento, disparo e WhatsApp de todas as linhas"
          >
            Aplicar a todas
          </button>
        </div>

        {/* Tabela */}
        <div className="flex-1 min-h-0 overflow-auto">
          <table className="w-full min-w-[580px] border-collapse">
            <thead className="sticky top-0 z-10 bg-[var(--panel)]">
              <tr className="text-[10px] font-bold uppercase tracking-wider text-muted">
                <th className="w-8 px-2 py-2 text-left font-bold">#</th>
                <th className="px-2 py-2 text-left font-bold">Nome</th>
                <th className="px-2 py-2 text-left font-bold w-[150px]">WhatsApp</th>
                {temMomento && <th className="px-2 py-2 text-left font-bold w-[155px]">Momento</th>}
                {ehIndicacao && <th className="px-2 py-2 text-left font-bold w-[150px]">Indicado por</th>}
                {temAutomacao && <th className="px-2 py-2 text-center font-bold w-[72px]">Disparar</th>}
                <th className="px-2 py-2 text-left font-bold w-[115px]">WhatsApp</th>
                <th className="w-8 px-1 py-2" />
              </tr>
            </thead>
            <tbody>
              {linhas.map((linha, i) => {
                const incompleta = !estaEmBranco(linha) && !estaPronta(linha)
                return (
                  <tr
                    key={linha.id}
                    className={`border-t border-white/[0.05] ${
                      linha.estado === 'ok'
                        ? 'bg-emerald-500/[0.07]'
                        : linha.estado === 'erro'
                          ? 'bg-red-500/[0.07]'
                          : ''
                    }`}
                  >
                    <td className="px-2 py-0.5 text-[10.5px] text-muted tabular-nums align-middle">
                      {linha.estado === 'ok' ? (
                        <CheckCircle size={13} weight="fill" className="text-emerald-400" />
                      ) : linha.estado === 'erro' ? (
                        <span title={linha.erro}>
                          <WarningCircle size={13} weight="fill" className="text-red-400" />
                        </span>
                      ) : (
                        i + 1
                      )}
                    </td>
                    <td className="px-1 py-0.5">
                      <input
                        ref={i === 0 ? primeiraCelulaRef : undefined}
                        value={linha.nome}
                        onChange={(e) => {
                          mudar(linha.id, { nome: e.target.value })
                          garantirLinhaLivre(linha.id)
                        }}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter') {
                            e.preventDefault()
                            acrescentar()
                          }
                        }}
                        placeholder="Nome"
                        className={celula}
                      />
                    </td>
                    <td className="px-1 py-0.5">
                      <input
                        value={linha.whatsapp}
                        onChange={(e) => {
                          mudar(linha.id, { whatsapp: e.target.value })
                          garantirLinhaLivre(linha.id)
                        }}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter') {
                            e.preventDefault()
                            acrescentar()
                          }
                        }}
                        inputMode="tel"
                        placeholder="(11) 91234-5678"
                        title={incompleta ? 'Com DDD. O 55 é acrescentado sozinho.' : undefined}
                        className={`${celula} tabular-nums ${incompleta ? 'text-amber-300' : ''}`}
                      />
                    </td>
                    {temMomento && (
                      <td className="px-1 py-0.5">
                        <SelectMomento
                          valor={linha.momento}
                          onChange={(v) => mudar(linha.id, { momento: v })}
                          largura="w-full"
                          permitirVazio={ehPipeline}
                        />
                      </td>
                    )}
                    {ehIndicacao && (
                      <td className="px-1 py-0.5">
                        <input
                          value={linha.indicadoPor}
                          onChange={(e) => mudar(linha.id, { indicadoPor: e.target.value })}
                          placeholder="Quem indicou"
                          className={celula}
                        />
                      </td>
                    )}
                    {temAutomacao && (
                      <td className="px-2 py-0.5 text-center">
                        <input
                          type="checkbox"
                          checked={linha.disparar}
                          onChange={(e) => mudar(linha.id, { disparar: e.target.checked })}
                          className="w-3.5 h-3.5 accent-[var(--blue)]"
                          title={
                            linha.disparar
                              ? 'Vai receber a mensagem automática da fonte'
                              : 'Não recebe mensagem nenhuma'
                          }
                        />
                      </td>
                    )}
                    <td className="px-1 py-0.5">
                      <SelectResponsavel
                        valor={linha.responsavel}
                        onChange={(v) => mudar(linha.id, { responsavel: v })}
                        largura="w-full"
                      />
                    </td>
                    <td className="px-1 py-0.5">
                      <button
                        type="button"
                        onClick={() => remover(linha.id)}
                        className="btn-icon w-6 h-6 opacity-50 hover:opacity-100"
                        aria-label={`Remover linha ${i + 1}`}
                      >
                        <Trash size={12} />
                      </button>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>

          {!ehPipeline && (
            <button
              type="button"
              onClick={acrescentar}
              className="w-full flex items-center justify-center gap-1.5 px-3 py-2 border-t border-white/[0.05] text-[11px] font-semibold text-muted hover:text-ink hover:bg-white/[0.04] transition-colors"
            >
              <Plus size={12} weight="bold" />
              Adicionar linha
            </button>
          )}
        </div>

        {/* Rodapé */}
        <div className="flex flex-wrap items-center gap-x-3 gap-y-2 px-4 py-2.5 border-t border-white/[0.07] flex-shrink-0">
          {/* Importação em massa: desligada até a integração existir. Botão
              desabilitado não dispara eventos de mouse, então o aviso do
              title precisa ficar no elemento em volta pra aparecer. */}
          {!ehPipeline && (
            <span title={AVISO_IMPORTACAO} className="cursor-not-allowed flex-shrink-0">
              <button type="button" disabled className="btn btn-outline btn-sm !py-1 !text-[11px] opacity-40 pointer-events-none">
                <UploadSimple size={12} weight="bold" />
                Adicionar em massa (CSV)
              </button>
            </span>
          )}

          {!ehPipeline && onCadastroCompleto && (
            <button
              type="button"
              onClick={onCadastroCompleto}
              className="text-[11px] font-semibold text-accent-2 hover:underline flex-shrink-0"
              title="Um lead só, com Instagram, e-mail, observação e campos extras"
            >
              Cadastro completo
            </button>
          )}

          <div className="min-w-0 flex-1 basis-full sm:basis-auto order-last sm:order-none text-[11px]">
            {resumo ? (
              <span className={resumo.includes('erro') ? 'text-amber-300' : 'text-emerald-300'}>{resumo}</span>
            ) : incompletas.length > 0 ? (
              <span className="text-amber-300">
                {incompletas.length} {incompletas.length === 1 ? 'linha incompleta' : 'linhas incompletas'} — nome e
                WhatsApp com DDD
              </span>
            ) : (
              <span className="text-muted">
                {prontas.length > 0
                  ? `${prontas.length} ${prontas.length === 1 ? 'linha pronta' : 'linhas prontas'}`
                  : 'Preencha nome e WhatsApp'}
              </span>
            )}
          </div>

          <button
            type="button"
            onClick={cadastrar}
            disabled={prontas.length === 0 || salvando}
            className="btn btn-primary btn-sm !py-1.5 disabled:opacity-40 flex-shrink-0"
          >
            {salvando
              ? ehPipeline
                ? 'Adicionando…'
                : 'Cadastrando…'
              : ehPipeline
                ? 'Adicionar ao pipeline'
                : prontas.length > 0
                  ? `Cadastrar ${prontas.length}`
                  : 'Cadastrar'}
          </button>
        </div>
      </div>
    </div>
  )
}

function SelectMomento({
  valor,
  onChange,
  largura = 'w-[150px]',
  permitirVazio = false,
}: {
  valor: string
  onChange: (v: string) => void
  largura?: string
  /** Deixa escolher "não definido" — lead que nunca passou pela Agenda. */
  permitirVazio?: boolean
}) {
  const atual = MOMENTOS.find((m) => m.key === valor)
  return (
    <select
      value={valor}
      onChange={(e) => onChange(e.target.value)}
      title={atual?.descricao}
      className={`${largura} bg-transparent border border-white/[0.08] rounded-md text-[11.5px] px-1.5 py-1 outline-none focus:border-accent/50`}
      style={{ color: atual?.cor }}
    >
      {permitirVazio && <option value="">Não definido</option>}
      {MOMENTOS.map((m) => (
        <option key={m.key} value={m.key} title={m.descricao}>
          {m.label}
        </option>
      ))}
    </select>
  )
}

function SelectResponsavel({
  valor,
  onChange,
  largura = 'w-[105px]',
}: {
  valor: string
  onChange: (v: string) => void
  largura?: string
}) {
  const cor = EQUIPE_ATENDIMENTO.find((p) => p.nome === valor)?.cor
  return (
    <select
      value={valor}
      onChange={(e) => onChange(e.target.value)}
      title="Só marca de quem é o lead — a mensagem sai sempre do número do CRM"
      className={`${largura} bg-transparent border border-white/[0.08] rounded-md text-[11.5px] px-1.5 py-1 outline-none focus:border-accent/50`}
      style={cor ? { color: cor } : undefined}
    >
      <option value={RESPONSAVEL_PADRAO}>CRM</option>
      {EQUIPE_ATENDIMENTO.map((p) => (
        <option key={p.nome} value={p.nome}>
          {p.nome}
        </option>
      ))}
    </select>
  )
}
