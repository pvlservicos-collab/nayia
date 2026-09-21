'use client'

/**
 * O relatório do dia, no topo da tela Início.
 *
 * Feito para ser LIDO em cinco segundos e COPIADO para o grupo do WhatsApp — é
 * assim que o time passa o resultado do turno. Por isso o botão de copiar não
 * exporta os números crus: monta o texto já formatado, com emoji e quebras de
 * linha, do jeito que vai ser colado.
 *
 * Os números vêm de GET /api/metrics/diario, que conta tudo no fuso de São Paulo
 * (ver a rota) — um relatório diário no fuso errado erra todo dia sem parecer
 * quebrado.
 */

import { useCallback, useEffect, useState } from 'react'
import { ClipboardText, Check, ArrowsClockwise, CaretLeft, CaretRight } from '@phosphor-icons/react'

interface RelatorioDia {
  dia: string
  novos_leads: number
  abordagens_iniciais: number
  responderam: number
  taxa_resposta: number
  avancaram: number
  mensagens_enviadas: number
  mensagens_recebidas: number
  mensagens_automaticas: number
  aguardando_resposta: number
  por_fonte: { chave: string; rotulo: string; total: number }[]
  por_etapa: { etapa: string; total: number }[]
}

const FUSO = 'America/Sao_Paulo'

function hojeEmSP(): string {
  return new Date().toLocaleDateString('en-CA', { timeZone: FUSO })
}

/** "2026-09-10" → "quinta-feira, 10/09". Sem `new Date(dia)` puro: isso seria
 *  lido como UTC e mostraria o dia anterior pra quem está no Brasil. */
function rotuloDoDia(dia: string): string {
  const [ano, mes, d] = dia.split('-').map(Number)
  const data = new Date(ano, mes - 1, d)
  const semana = data.toLocaleDateString('pt-BR', { weekday: 'long' })
  return `${semana}, ${String(d).padStart(2, '0')}/${String(mes).padStart(2, '0')}`
}

function somaDias(dia: string, delta: number): string {
  const [ano, mes, d] = dia.split('-').map(Number)
  const data = new Date(ano, mes - 1, d + delta)
  return `${data.getFullYear()}-${String(data.getMonth() + 1).padStart(2, '0')}-${String(data.getDate()).padStart(2, '0')}`
}

/** O texto que vai pro grupo. */
function montarTexto(r: RelatorioDia): string {
  const linhas: string[] = [
    `📊 *Relatório do dia — ${rotuloDoDia(r.dia)}*`,
    '',
    `🆕 Leads novos: *${r.novos_leads}*`,
    `📤 Abordagens iniciais: *${r.abordagens_iniciais}*`,
    `💬 Responderam: *${r.responderam}*${r.abordagens_iniciais > 0 ? ` (${r.taxa_resposta}%)` : ''}`,
    `📈 Avançaram no funil: *${r.avancaram}*`,
  ]

  if (r.por_fonte.length > 0) {
    linhas.push('', '*De onde vieram:*')
    for (const f of r.por_fonte) linhas.push(`• ${f.rotulo}: ${f.total}`)
  }

  if (r.por_etapa.length > 0) {
    linhas.push('', '*Movimentações:*')
    for (const e of r.por_etapa) linhas.push(`• ${e.etapa}: ${e.total}`)
  }

  linhas.push(
    '',
    `✉️ Mensagens: ${r.mensagens_enviadas} enviadas · ${r.mensagens_recebidas} recebidas`,
  )
  if (r.aguardando_resposta > 0) {
    linhas.push(`⏳ Aguardando resposta (total): ${r.aguardando_resposta}`)
  }

  return linhas.join('\n')
}

export default function RelatorioDiario() {
  const [dia, setDia] = useState(hojeEmSP)
  const [relatorio, setRelatorio] = useState<RelatorioDia | null>(null)
  const [carregando, setCarregando] = useState(true)
  const [copiado, setCopiado] = useState(false)
  const [erro, setErro] = useState<string | null>(null)

  const carregar = useCallback(async (alvo: string) => {
    setCarregando(true)
    setErro(null)
    try {
      const res = await fetch(`/api/metrics/diario?data=${alvo}`)
      const json = await res.json()
      if (!res.ok) throw new Error(json?.error || 'Falha ao carregar o relatório.')
      setRelatorio(json.data)
    } catch (err: any) {
      setErro(err.message)
      setRelatorio(null)
    } finally {
      setCarregando(false)
    }
  }, [])

  useEffect(() => { carregar(dia) }, [dia, carregar])

  async function copiar() {
    if (!relatorio) return
    const texto = montarTexto(relatorio)
    try {
      await navigator.clipboard.writeText(texto)
    } catch {
      // Navegador sem permissão de área de transferência (acontece em http e em
      // alguns webviews): cai pro método antigo em vez de não fazer nada.
      const area = document.createElement('textarea')
      area.value = texto
      area.style.position = 'fixed'
      area.style.opacity = '0'
      document.body.appendChild(area)
      area.select()
      document.execCommand('copy')
      document.body.removeChild(area)
    }
    setCopiado(true)
    setTimeout(() => setCopiado(false), 2500)
  }

  const ehHoje = dia === hojeEmSP()

  return (
    <section className="glass rounded-2xl p-4 sm:p-5">
      <div className="flex items-center gap-2 mb-4 flex-wrap">
        <div className="min-w-0 mr-auto">
          <h2 className="text-base font-bold text-ink leading-tight">
            Relatório do dia
            <span className="ml-2 text-xs font-medium text-muted normal-case">
              {rotuloDoDia(dia)}{ehHoje ? ' · hoje' : ''}
            </span>
          </h2>
          <p className="text-[11px] text-muted mt-0.5">Meia-noite às 23h59, horário de Brasília.</p>
        </div>

        <div className="flex items-center gap-1 flex-shrink-0">
          <button
            onClick={() => setDia((d) => somaDias(d, -1))}
            className="btn-icon w-8 h-8"
            title="Dia anterior"
          >
            <CaretLeft size={14} weight="bold" />
          </button>
          <button
            onClick={() => setDia((d) => somaDias(d, 1))}
            disabled={ehHoje}
            className="btn-icon w-8 h-8 disabled:opacity-30"
            title="Próximo dia"
          >
            <CaretRight size={14} weight="bold" />
          </button>
          <button onClick={() => carregar(dia)} className="btn-icon w-8 h-8" title="Atualizar">
            <ArrowsClockwise size={14} weight="bold" className={carregando ? 'animate-spin' : ''} />
          </button>
          <button
            onClick={copiar}
            disabled={!relatorio}
            className="btn btn-primary btn-sm ml-1 disabled:opacity-40"
          >
            {copiado ? <Check size={14} weight="bold" /> : <ClipboardText size={14} weight="bold" />}
            {copiado ? 'Copiado!' : 'Copiar'}
          </button>
        </div>
      </div>

      {erro && <p className="text-xs text-red-400">{erro}</p>}

      {relatorio && (
        <>
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-2.5">
            <Numero rotulo="Leads novos" valor={relatorio.novos_leads} destaque />
            <Numero rotulo="Abordagens iniciais" valor={relatorio.abordagens_iniciais} />
            <Numero
              rotulo="Responderam"
              valor={relatorio.responderam}
              rodape={relatorio.abordagens_iniciais > 0 ? `${relatorio.taxa_resposta}% das abordagens` : undefined}
            />
            <Numero rotulo="Avançaram no funil" valor={relatorio.avancaram} />
          </div>

          <div className="grid sm:grid-cols-2 gap-3 mt-3">
            <Lista
              titulo="De onde vieram"
              itens={relatorio.por_fonte.map((f) => ({ rotulo: f.rotulo, total: f.total }))}
              vazio="Nenhum lead novo neste dia."
            />
            <Lista
              titulo="Movimentações no funil"
              itens={relatorio.por_etapa.map((e) => ({ rotulo: e.etapa, total: e.total }))}
              vazio="Nenhum card mudou de etapa."
            />
          </div>

          <div className="flex flex-wrap gap-x-5 gap-y-1 mt-3 pt-3 border-t border-white/5 text-[11px] text-muted">
            <span>✉️ {relatorio.mensagens_enviadas} enviadas · {relatorio.mensagens_recebidas} recebidas</span>
            {relatorio.mensagens_automaticas > 0 && (
              <span>🤖 {relatorio.mensagens_automaticas} automáticas</span>
            )}
            {relatorio.aguardando_resposta > 0 && (
              <span title="Leads que já receberam mensagem e nunca responderam — soma de todos os dias.">
                ⏳ {relatorio.aguardando_resposta} aguardando resposta
              </span>
            )}
          </div>
        </>
      )}
    </section>
  )
}

function Numero({
  rotulo,
  valor,
  rodape,
  destaque,
}: {
  rotulo: string
  valor: number
  rodape?: string
  destaque?: boolean
}) {
  return (
    <div className="panel rounded-xl px-3.5 py-3">
      <p className="text-[11px] text-muted leading-tight">{rotulo}</p>
      <p className={`text-2xl font-bold tabular-nums leading-tight mt-0.5 ${destaque ? 'text-accent-2' : 'text-ink'}`}>
        {valor}
      </p>
      {rodape && <p className="text-[10px] text-muted/70 mt-0.5">{rodape}</p>}
    </div>
  )
}

function Lista({
  titulo,
  itens,
  vazio,
}: {
  titulo: string
  itens: { rotulo: string; total: number }[]
  vazio: string
}) {
  return (
    <div className="panel rounded-xl px-3.5 py-3">
      <p className="text-[11px] font-bold uppercase tracking-wider text-muted mb-2">{titulo}</p>
      {itens.length === 0 ? (
        <p className="text-[11px] text-muted/70">{vazio}</p>
      ) : (
        <dl className="space-y-1">
          {itens.map((i) => (
            <div key={i.rotulo} className="flex items-baseline justify-between gap-3">
              <dt className="text-xs text-muted truncate">{i.rotulo}</dt>
              <dd className="text-xs font-bold text-ink tabular-nums flex-shrink-0">{i.total}</dd>
            </div>
          ))}
        </dl>
      )}
    </div>
  )
}
