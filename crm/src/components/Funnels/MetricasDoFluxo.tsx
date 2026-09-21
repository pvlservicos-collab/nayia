'use client'

/**
 * Métricas de um fluxo — a tela que responde "qual mensagem funciona melhor?".
 *
 * O número que importa aqui é RESPOSTA, não entrega. Entrega só diz que o
 * WhatsApp aceitou; resposta diz que a pessoa parou o que estava fazendo e
 * escreveu de volta, que é o objetivo de uma mensagem de retomada.
 *
 * Quando o fluxo tem teste A/B/C, cada versão aparece com seus próprios
 * números e a melhor fica marcada. A comparação só vale com volume: abaixo de
 * ~30 envios por versão a diferença é ruído, e a tela diz isso em vez de
 * deixar alguém trocar o texto por causa de dois cliques de sorte.
 */

import { useEffect, useState } from 'react'
import { ChartBar, Trophy, X } from '@phosphor-icons/react'

/** Abaixo disto, diferença entre versões não significa nada. */
const ENVIOS_PARA_CONFIAR = 30

interface VarianteMetrica {
  block_id: string
  variante: string
  enviado: number
  entregue: number
  responderam: number
  taxa_resposta: number
}

interface EnvioMetrica {
  block_id: string
  enviado: number
  entregue: number
  falhou: number
  taxa_entrega: number
}

export default function MetricasDoFluxo({
  funnelId,
  rotuloDoBloco,
  onClose,
}: {
  funnelId: string
  /** Nome do bloco, pra tabela não mostrar id cru. */
  rotuloDoBloco: (blockId: string) => string
  onClose: () => void
}) {
  const [variantes, setVariantes] = useState<VarianteMetrica[]>([])
  const [envios, setEnvios] = useState<EnvioMetrica[]>([])
  const [carregando, setCarregando] = useState(true)
  const [erro, setErro] = useState(false)

  useEffect(() => {
    let cancelado = false
    setCarregando(true)
    fetch(`/api/funnels/${funnelId}/metrics`)
      .then((r) => (r.ok ? r.json() : Promise.reject()))
      .then((json) => {
        if (cancelado) return
        setVariantes(json?.data?.variantes ?? [])
        setEnvios(json?.data?.envios ?? [])
      })
      .catch(() => { if (!cancelado) setErro(true) })
      .finally(() => { if (!cancelado) setCarregando(false) })
    return () => { cancelado = true }
  }, [funnelId])

  const totalEnviado = envios.reduce((soma, e) => soma + e.enviado, 0)
  const totalEntregue = envios.reduce((soma, e) => soma + e.entregue, 0)
  const totalResponderam = variantes.reduce((soma, v) => soma + v.responderam, 0)

  // A melhor versão: maior taxa de resposta, e só entre as que já têm volume.
  const comVolume = variantes.filter((v) => v.entregue >= ENVIOS_PARA_CONFIAR)
  const melhor = comVolume.length > 1
    ? comVolume.reduce((a, b) => (b.taxa_resposta > a.taxa_resposta ? b : a))
    : null

  const porcento = (n: number) => `${(n * 100).toFixed(1)}%`

  return (
    <div className="absolute inset-0 z-20 flex items-start justify-center p-4 sm:p-8 overflow-y-auto bg-black/50 backdrop-blur-sm">
      <div className="panel w-full max-w-3xl rounded-2xl overflow-hidden">
        <div className="flex items-center gap-2.5 px-5 py-3.5 border-b border-line">
          <ChartBar size={18} weight="bold" className="text-accent-2" />
          <div className="min-w-0 flex-1">
            <h2 className="text-sm font-bold text-ink">Métricas do fluxo</h2>
            <p className="text-[11px] text-muted">Quantas mensagens saíram e quantas pessoas responderam.</p>
          </div>
          <button onClick={onClose} className="btn-icon w-8 h-8" aria-label="Fechar">
            <X size={16} />
          </button>
        </div>

        <div className="p-5 space-y-5">
          {carregando ? (
            <p className="text-sm text-muted py-8 text-center">Carregando…</p>
          ) : erro ? (
            <p className="text-sm text-red-400 py-8 text-center">Não consegui carregar as métricas.</p>
          ) : (
            <>
              <div className="grid grid-cols-3 gap-3">
                <Numero titulo="Enviadas" valor={totalEnviado} />
                <Numero titulo="Entregues" valor={totalEntregue} />
                <Numero titulo="Responderam" valor={totalResponderam} destaque />
              </div>

              {variantes.length === 0 ? (
                <p className="text-[12.5px] text-muted leading-relaxed">
                  Este fluxo ainda não tem teste A/B/C, ou nenhuma mensagem de teste saiu.
                  As versões aparecem aqui assim que o primeiro disparo acontecer.
                </p>
              ) : (
                <div>
                  <div className="flex items-baseline justify-between mb-2">
                    <h3 className="text-xs font-bold uppercase tracking-wider text-muted">Versões da mensagem</h3>
                    {!melhor && (
                      <span className="text-[11px] text-muted">
                        precisa de {ENVIOS_PARA_CONFIAR}+ entregas por versão para comparar
                      </span>
                    )}
                  </div>

                  <div className="overflow-x-auto">
                    <table className="w-full text-sm border-collapse">
                      <thead>
                        <tr className="text-[10px] font-bold uppercase tracking-wider text-muted">
                          <th className="text-left py-2 pr-3">Versão</th>
                          <th className="text-right py-2 px-3">Enviadas</th>
                          <th className="text-right py-2 px-3">Entregues</th>
                          <th className="text-right py-2 px-3">Responderam</th>
                          <th className="text-right py-2 pl-3">Taxa</th>
                        </tr>
                      </thead>
                      <tbody>
                        {variantes.map((v) => {
                          const ehMelhor = melhor?.variante === v.variante && melhor?.block_id === v.block_id
                          return (
                            <tr key={`${v.block_id}-${v.variante}`} className="border-t border-line">
                              <td className="py-2.5 pr-3">
                                <span className="inline-flex items-center gap-1.5 font-bold text-ink">
                                  {ehMelhor && <Trophy size={14} weight="fill" className="text-amber-400" />}
                                  {v.variante}
                                </span>
                                <span className="block text-[10.5px] text-muted truncate max-w-[220px]">
                                  {rotuloDoBloco(v.block_id)}
                                </span>
                              </td>
                              <td className="py-2.5 px-3 text-right tabular-nums text-ink">{v.enviado}</td>
                              <td className="py-2.5 px-3 text-right tabular-nums text-muted">{v.entregue}</td>
                              <td className="py-2.5 px-3 text-right tabular-nums text-ink">{v.responderam}</td>
                              <td className="py-2.5 pl-3 text-right tabular-nums font-bold" style={{ color: ehMelhor ? '#fbbf24' : undefined }}>
                                {porcento(v.taxa_resposta)}
                              </td>
                            </tr>
                          )
                        })}
                      </tbody>
                    </table>
                  </div>

                  <p className="text-[11px] text-muted leading-relaxed mt-3">
                    Responderam = a pessoa mandou mensagem depois de receber aquela versão.
                    {melhor && (
                      <>
                        {' '}Hoje a versão <strong className="text-ink">{melhor.variante}</strong> está ganhando,
                        com {porcento(melhor.taxa_resposta)} de resposta.
                      </>
                    )}
                  </p>
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  )
}

function Numero({ titulo, valor, destaque }: { titulo: string; valor: number; destaque?: boolean }) {
  return (
    <div className={`rounded-xl border px-4 py-3 ${destaque ? 'border-accent/40 bg-accent/10' : 'border-line bg-white/[0.02]'}`}>
      <p className="text-[10px] font-bold uppercase tracking-wider text-muted">{titulo}</p>
      <p className="text-2xl font-bold text-ink tabular-nums mt-0.5">{valor}</p>
    </div>
  )
}
