'use client'

/**
 * ENVIAR IMÓVEL pelo número de captação (8595-6408).
 *
 * Pedro, 16/10: "coloca esse campo nos cards dos leads também do de captação" (396); 17/10: "libera lá o botão enviar
 * imóveis para todos os leads dos 2 números" -- captação e oficial. A mesma escolha da Parceria (um a um ou por faixa);
 * quem manda é a Nay do WhatsApp (nay-olx), card + fotos, um imóvel por vez, SEMPRE pelo 8595: o número oficial da Meta
 * só manda modelo fora da janela de 24 h. O card acompanha o pedido até terminar.
 */
import { useCallback, useEffect, useRef, useState } from 'react'
import { CheckCircle, CircleNotch, PaperPlaneRight, WarningCircle } from '@phosphor-icons/react'
import EscolherImoveis, { useOpcoesDoDisparo, type ImovelParaEnviar } from '@/components/Disparo/EscolherImoveis'
import BarraDeCarregamento from '@/components/Shared/BarraDeCarregamento'

type Envio = { tipo: 'ok' | 'erro' | 'aviso' | 'vai'; texto: string }

export default function EnviarImovelPelaCaptacao({ leadId, telefone, oficial }: {
  leadId: string
  telefone: string | null | undefined
  oficial?: boolean
}) {
  const { opcoes: opcoesDoDisparo, teto: tetoDoDisparo } = useOpcoesDoDisparo()
  const [escolhidos, setEscolhidos] = useState<ImovelParaEnviar[]>([])
  const [rodada, setRodada] = useState(0)
  const [enviando, setEnviando] = useState(false)
  const [envio, setEnvio] = useState<Envio | null>(null)
  const [progresso, setProgresso] = useState<number | null>(null)
  const vigia = useRef<ReturnType<typeof setTimeout> | null>(null)
  useEffect(() => () => { if (vigia.current) clearTimeout(vigia.current) }, [])
  useEffect(() => { setEscolhidos([]); setEnvio(null) }, [leadId])

  const acompanhar = useCallback((id: number, desde: number) => {
    vigia.current = setTimeout(async () => {
      try {
        const r = await fetch(`/api/captacao/enviar-imoveis?id=${id}`)
        const e = await r.json().catch(() => ({}))
        if (e?.estado === 'enviado' || e?.estado === 'falhou') {
          setEnviando(false)
          setEnvio({ tipo: e.estado === 'enviado' ? 'ok' : 'erro', texto: e.resultado || (e.estado === 'enviado' ? 'Enviado.' : 'Não saiu.') })
          return
        }
        const feitos = Array.isArray(e?.enviados) ? e.enviados.length : 0
        const total = Array.isArray(e?.codigos) ? e.codigos.length : 0
        setProgresso(total ? feitos / total : null)
        setEnvio({ tipo: 'vai', texto: `Enviando pelo 8595… ${feitos} de ${total}` })
      } catch { /* sem rede: tenta de novo */ }
      if (Date.now() - desde < 15 * 60_000) acompanhar(id, desde)
      else { setEnviando(false); setEnvio({ tipo: 'aviso', texto: 'O envio está demorando; ele continua saindo pela Nay.' }) }
    }, 3000)
  }, [])

  async function enviar() {
    if (!escolhidos.length || enviando) return
    setEnviando(true)
    setProgresso(null)
    setEnvio({ tipo: 'vai', texto: 'Pedindo o envio…' })
    try {
      const r = await fetch('/api/captacao/enviar-imoveis', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ telefone, codigos: escolhidos.map((e) => Number(e.codigo)) }),
      })
      const j = await r.json().catch(() => ({}))
      if (!r.ok || !j?.id) throw new Error(j?.error || 'não consegui pedir o envio')
      setEscolhidos([])
      setRodada((n) => n + 1)
      setEnvio({ tipo: 'vai', texto: 'Na fila da Nay: sai em alguns segundos, um imóvel de cada vez.' })
      acompanhar(Number(j.id), Date.now())
    } catch (e: any) {
      setEnviando(false)
      setEnvio({ tipo: 'erro', texto: e?.message || 'não consegui pedir o envio' })
    }
  }

  return (
    <>
      <EscolherImoveis key={rodada} compacto comParceiro escolhidos={escolhidos}
                       aoMudar={(l) => { setEscolhidos(l); if (!enviando) setEnvio(null) }}
                       teto={tetoDoDisparo} opcoes={opcoesDoDisparo}
                       aoAvisar={(texto) => setEnvio(texto ? { tipo: 'aviso', texto } : null)} />
      <button type="button" onClick={() => void enviar()} disabled={!escolhidos.length || enviando}
              className="mt-3 w-full h-10 rounded-full text-[14px] font-semibold flex items-center justify-center gap-1.5 disabled:opacity-40"
              style={{ background: 'var(--wa-green)', color: 'var(--wa-green-ink)' }}>
        {enviando ? <CircleNotch size={16} className="animate-spin" /> : <PaperPlaneRight size={16} weight="fill" />}
        {escolhidos.length ? `Enviar ${escolhidos.length} imóve${escolhidos.length === 1 ? 'l' : 'is'}` : 'Enviar'}
      </button>
      {/* 04/11 (Pedro): a barrinha até a última mensagem sair */}
      {enviando && <div className="mt-2"><BarraDeCarregamento progresso={progresso} /></div>}
      {envio && (
        <p className="text-[13px] mt-2 flex items-start gap-1.5 whitespace-pre-wrap"
           style={{ color: envio.tipo === 'ok' ? 'var(--wa-green)' : envio.tipo === 'erro' ? 'var(--wa-tag-tel)'
                    : envio.tipo === 'aviso' ? 'var(--wa-tag-prop)' : 'var(--wa-text-2)' }}>
          {envio.tipo === 'vai' ? <CircleNotch size={16} className="mt-px flex-shrink-0 animate-spin" />
            : envio.tipo === 'ok' ? <CheckCircle size={16} className="mt-px flex-shrink-0" />
            : <WarningCircle size={16} className="mt-px flex-shrink-0" />}
          {envio.texto}
        </p>
      )}
      <p className="text-[11px] mt-1" style={{ color: 'var(--wa-text-2)' }}>
        Sai pelo número de captação (8595-6408), card e fotos, um imóvel de cada vez
        {oficial ? ' (o oficial da Meta só manda modelo fora das 24 h)' : ''}. Fora do ar não sai; de parceiro, só a cliente
        final (corretor não recebe).
      </p>
    </>
  )
}
