'use client'

/**
 * A ABA ARQUITETURA DA LINHA WHATSAPP LEADS (Pedro, 24/10/2026): "uma opção ali do lado de agenda, Arquitetura, lá vai ter
 * cada etapa em tipo um fluxograma só para eu ver como está funcionando" e "de um jeito bem metrificável, para ser
 * escalável". O fluxo: a mensagem do cliente → o Mestre (JEV) escolhe o caminho → os agentes; só o Atendimento escreve ao
 * cliente. Cada caixa mostra o período escolhido: ativações, conversas, tempo médio, custo e erros (GET /api/agentes).
 * Agente novo no banco (privado.agente) aparece na fileira de baixo sozinho.
 */
import { useCallback, useEffect, useState } from 'react'
import { ArrowDown, ArrowRight, ArrowsClockwise, ChatCircleText, CircleNotch, PaperPlaneTilt } from '@phosphor-icons/react'
import { FUSO_DE_MANAUS } from '@/lib/fusoDeManaus'
import { ROTULO_DO_MODO, type AgenteNoPainel, type PainelDosAgentes } from '@/lib/agentes'
import { Legenda } from './AgentesDoLead'
import RegistroDeFluxos from './RegistroDeFluxos'

const PERIODOS: [number, string][] = [[24, '24 horas'], [24 * 7, '7 dias'], [24 * 30, '30 dias']]
const ROTULO_DO_CAMINHO: Record<string, string> = {
  imoveis: 'quer imóvel / filtros', duvida: 'dúvida de um imóvel', visita: 'visita', fotos: 'fotos', equipe: 'é com a equipe',
  geral: 'prompt inteiro (sem certeza ou 1ª mensagem)', calar: 'só cortesia (não respondeu)',
}
const TIPO: Record<string, string> = { ia: 'IA', codigo: 'regra (código)', gente: 'pessoa' }

function dinheiro(v: number) {
  return `US$ ${Number(v || 0).toLocaleString('pt-BR', { minimumFractionDigits: v && v < 0.01 ? 4 : 2, maximumFractionDigits: 4 })}`
}
function quando(iso: string | null) {
  if (!iso) return '—'
  return new Date(iso).toLocaleString('pt-BR', { timeZone: FUSO_DE_MANAUS, day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
}

function No({ a, extra, destaque }: { a?: AgenteNoPainel; extra?: React.ReactNode; destaque?: boolean }) {
  if (!a) return null
  const parado = a.ativacoes === 0 && a.sombra === 0
  return (
    <div className="rounded-xl overflow-hidden flex flex-col min-w-0"
         style={{ background: 'var(--wa-panel)', border: `1px solid ${destaque ? a.cor : 'var(--wa-divider)'}`,
                  boxShadow: destaque ? `0 0 0 3px color-mix(in srgb, ${a.cor} 14%, transparent)` : undefined, opacity: parado ? 0.75 : 1 }}>
      <div style={{ height: 4, background: a.cor }} />
      <div className="p-3 flex flex-col gap-2">
        <div className="flex items-center gap-2">
          <i className="inline-block w-3 h-3 rounded-full flex-shrink-0" style={{ background: a.cor }} />
          <b className="text-[14px] truncate" style={{ color: 'var(--wa-text)' }}>{a.nome}</b>
          <span className="ml-auto text-[10.5px] px-1.5 py-[1px] rounded-full whitespace-nowrap"
                style={{ background: 'var(--wa-row-selected)', color: 'var(--wa-text-2)' }}>
            {TIPO[a.tipo] || a.tipo}{a.modelo ? ` · ${a.modelo}` : ''}
          </span>
        </div>
        <p className="text-[12px] leading-4" style={{ color: 'var(--wa-text-2)' }}>{a.descricao}</p>
        <div className="grid grid-cols-3 gap-1.5 text-center">
          {[['ativações', a.ativacoes + (a.sombra ? ` (+${a.sombra} sombra)` : '')], ['conversas', a.conversas],
            ['tempo médio', a.ms_medio != null ? `${(a.ms_medio / 1000).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} s` : '—'],
            ['custo', dinheiro(a.custo_usd)], ['erros', a.erros], ['última', quando(a.ultima)]].map(([r, v]) => (
            <div key={r as string} className="rounded-lg py-1.5 px-1" style={{ background: 'var(--wa-row-hover)' }}>
              <div className="text-[13px] font-semibold leading-4" style={{ color: r === 'erros' && Number(v) > 0 ? '#DC2626' : 'var(--wa-text)' }}>{v}</div>
              <div className="text-[10.5px]" style={{ color: 'var(--wa-text-2)' }}>{r}</div>
            </div>
          ))}
        </div>
        {extra}
      </div>
    </div>
  )
}

function Seta({ para = 'baixo' }: { para?: 'baixo' | 'direita' }) {
  return (
    <div className="flex items-center justify-center" style={{ color: 'var(--wa-text-2)' }}>
      {para === 'baixo' ? <ArrowDown size={22} /> : <ArrowRight size={22} />}
    </div>
  )
}

function Ponta({ icone, titulo, texto }: { icone: React.ReactNode; titulo: string; texto: string }) {
  return (
    <div className="rounded-xl px-4 py-3 flex items-center gap-3 mx-auto"
         style={{ background: 'var(--wa-row-hover)', border: '1px dashed var(--wa-divider)', maxWidth: 520 }}>
      <span style={{ color: 'var(--wa-green)' }}>{icone}</span>
      <div><b className="text-[14px]" style={{ color: 'var(--wa-text)' }}>{titulo}</b>
        <p className="text-[12px]" style={{ color: 'var(--wa-text-2)' }}>{texto}</p></div>
    </div>
  )
}

export default function ArquiteturaDosAgentes() {
  const [horas, setHoras] = useState(24)
  const [p, setP] = useState<PainelDosAgentes | null>(null)
  const [carregando, setCarregando] = useState(false)
  const [erro, setErro] = useState('')

  const ler = useCallback(async () => {
    setCarregando(true)
    try {
      const r = await fetch(`/api/agentes?horas=${horas}`)
      const j = await r.json()
      if (!r.ok) throw new Error(j.error || j.erro || 'erro')
      setP(j); setErro('')
    } catch (e) {
      setErro(e instanceof Error ? e.message : 'erro')
    } finally {
      setCarregando(false)
    }
  }, [horas])

  useEffect(() => { void ler(); const t = setInterval(() => { if (!document.hidden) void ler() }, 30000); return () => clearInterval(t) }, [ler])

  const ag = (k: string) => p?.agentes.find((a) => a.chave === k)
  // 'fluxo' (490) são as portas e as ferramentas do código: aparece no registro de fluxos, não como caixa
  const conhecidos = new Set(['mestre', 'atendimento', 'imoveis', 'busca', 'visita', 'revisao', 'corretores', 'humano', 'fluxo'])
  const novos = (p?.agentes || []).filter((a) => !conhecidos.has(a.chave))
  const caminhos = Object.entries(p?.caminhos || {}).sort((a, b) => b[1] - a[1])
  const totalCaminhos = caminhos.reduce((s, [, n]) => s + n, 0)
  const rp = p?.replay?.resumo

  return (
    <div className="flex-1 min-h-0 overflow-y-auto" style={{ background: 'var(--wa-bg, var(--wa-panel))' }}>
      <div className="max-w-[1180px] mx-auto px-4 py-4 flex flex-col gap-4">
        {/* topo: o modo, o período, a legenda */}
        <div className="rounded-xl p-4 flex flex-col gap-3" style={{ background: 'var(--wa-panel)', border: '1px solid var(--wa-divider)' }}>
          <div className="flex flex-wrap items-center gap-3">
            <div>
              <h2 className="text-[17px] font-semibold" style={{ color: 'var(--wa-text)' }}>Arquitetura da Nay Leads</h2>
              <p className="text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>
                Cada mensagem passa pelo Mestre, que escolhe o caminho; só o Atendimento escreve ao cliente.
              </p>
            </div>
            {p && (
              <span className="text-[12px] font-semibold px-2.5 py-1 rounded-full"
                    style={{ background: p.modo === 'sim' ? 'color-mix(in srgb, var(--wa-green) 18%, transparent)' : p.modo === 'sombra' ? 'color-mix(in srgb, #CA8A04 18%, transparent)' : 'var(--wa-row-selected)',
                             color: 'var(--wa-text)' }}>
                {ROTULO_DO_MODO[p.modo]}
              </span>
            )}
            <div className="ml-auto flex items-center gap-1.5">
              {PERIODOS.map(([h, r]) => (
                <button key={h} type="button" onClick={() => setHoras(h)}
                        className="text-[12.5px] px-2.5 py-1 rounded-full"
                        style={horas === h ? { background: 'var(--wa-green)', color: 'var(--wa-green-ink)' } : { border: '1px solid var(--wa-divider)', color: 'var(--wa-text)' }}>{r}</button>
              ))}
              <button type="button" onClick={() => void ler()} className="p-1.5 rounded" title="Atualizar" style={{ color: 'var(--wa-text-2)' }}>
                {carregando ? <CircleNotch size={16} className="animate-spin" /> : <ArrowsClockwise size={16} />}
              </button>
            </div>
          </div>
          {p && <Legenda agentes={p.agentes} />}
          {erro && <p className="text-[12.5px]" style={{ color: '#DC2626' }}>Não deu para ler o painel: {erro}</p>}
        </div>

        {p && (
          <>
            {/* 1. a mensagem chega */}
            <Ponta icone={<ChatCircleText size={22} weight="fill" />} titulo="O cliente escreve no 8595"
                   texto="Da OLX ou orgânico. A Nay espera o silêncio, lê as mensagens novas e chama o Mestre." />
            <Seta />

            {/* 2. o mestre */}
            <div className="mx-auto w-full" style={{ maxWidth: 620 }}>
              <No a={ag('mestre')} destaque extra={totalCaminhos > 0 && (
                <div className="flex flex-col gap-1 mt-1">
                  <p className="text-[11.5px]" style={{ color: 'var(--wa-text-2)' }}>Caminhos escolhidos no período</p>
                  {caminhos.map(([k, n]) => (
                    <div key={k} className="flex items-center gap-2 text-[12px]">
                      <span className="w-[170px] truncate" style={{ color: 'var(--wa-text)' }} title={ROTULO_DO_CAMINHO[k] || k}>{ROTULO_DO_CAMINHO[k] || k}</span>
                      <div className="flex-1 h-2 rounded-full overflow-hidden" style={{ background: 'var(--wa-row-selected)' }}>
                        <div className="h-full rounded-full" style={{ width: `${(100 * n) / totalCaminhos}%`, background: ag('mestre')?.cor }} />
                      </div>
                      <span className="w-8 text-right" style={{ color: 'var(--wa-text-2)' }}>{n}</span>
                    </div>
                  ))}
                </div>
              )} />
            </div>
            <Seta />

            {/* 3. os agentes que o mestre aciona */}
            <div className="grid gap-3" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(230px, 1fr))' }}>
              <No a={ag('atendimento')} destaque />
              <div className="flex flex-col gap-2">
                <No a={ag('imoveis')} extra={(p.veto.passou + p.veto.barrou) > 0 && (
                  <p className="text-[12px]" style={{ color: 'var(--wa-text-2)' }}>
                    Veto: <b style={{ color: 'var(--wa-text)' }}>{p.veto.passou}</b> serviram · <b style={{ color: '#DC2626' }}>{p.veto.barrou}</b> barrados
                  </p>
                )} />
                <p className="text-[11.5px] text-center" style={{ color: 'var(--wa-text-2)' }}>sem o perfil exato na base ↓</p>
                <No a={ag('busca')} />
                <p className="text-[11.5px] text-center" style={{ color: 'var(--wa-text-2)' }}>o corretor que responde ↓</p>
                <No a={ag('corretores')} />
              </div>
              <No a={ag('visita')} />
              <No a={ag('revisao')} />
              <No a={ag('humano')} />
              {novos.map((a) => <No key={a.chave} a={a} />)}
            </div>
            <Seta />

            {/* 4. a resposta */}
            <Ponta icone={<PaperPlaneTilt size={22} weight="fill" />} titulo="A resposta sai pelo Atendimento"
                   texto="Os outros agentes devolvem dados (imóveis, horário, resposta da dúvida); só a voz da Nay escreve ao cliente." />

            {/* o último replay: antigo × novo */}
            <div className="rounded-xl p-4" style={{ background: 'var(--wa-panel)', border: '1px solid var(--wa-divider)' }}>
              <h3 className="text-[14px] font-semibold mb-1" style={{ color: 'var(--wa-text)' }}>Último replay (as conversas reais, sem enviar)</h3>
              {!rp ? (
                <p className="text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>Ainda não rodou.</p>
              ) : (
                <div className="flex flex-col gap-1 text-[13px]" style={{ color: 'var(--wa-text)' }}>
                  <p>{quando(p.replay!.em)} · {rp.turnos} turnos{rp.so ? ' (só os que tinham dado errado)' : ''}</p>
                  <p><b style={{ color: 'var(--wa-green)' }}>{rp.novo} melhores</b> · <b>{rp.empate} iguais</b> · <b style={{ color: '#DC2626' }}>{rp.antigo} piores</b>{rp.erro ? ` · ${rp.erro} com erro` : ''}</p>
                  <p style={{ color: 'var(--wa-text-2)' }}>
                    Tokens de entrada: {Number(rp.tokens_antigo || 0).toLocaleString('pt-BR')} antes → {Number(rp.tokens_novo || 0).toLocaleString('pt-BR')} agora ·
                    tempo médio {((rp.ms_antigo_medio || 0) / 1000).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} s → {((rp.ms_novo_medio || 0) / 1000).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} s ·
                    ações iguais em {rp.acoes_iguais} de {rp.turnos - (rp.erro || 0)}
                  </p>
                </div>
              )}
            </div>

            {/* 490: o registro de fluxos (um log de traços por turno) */}
            <RegistroDeFluxos />
          </>
        )}
      </div>
    </div>
  )
}
