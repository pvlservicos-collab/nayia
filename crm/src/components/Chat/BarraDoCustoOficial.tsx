'use client'

/**
 * O CONTADOR DA API OFICIAL (Pedro, 16/10/2026: "por contador de mensagens em cima do número de API oficial para
 * sabermos quanto já disparamos, e quanto já mandamos de mensagem de serviço ... e quanto estamos gastando").
 *
 * Os números são os da Meta, do mês (de /api/oficial/custo-meta, que lê o pricing_analytics da conta): os modelos
 * entregues (os disparos), quantos foram cobrados, o custo na moeda da conta e as mensagens de serviço (grátis).
 * Desde 07/2025 não existe mais a franquia de 1.000 grátis: a Meta cobra por modelo entregue, e a resposta dentro das
 * 24 h (e o modelo de utilidade dentro dessa janela) é grátis. Lê de novo a cada 5 min.
 */
import { useEffect, useState } from 'react'

interface Custo {
  mes: string
  moeda: string
  modelos: { total: number; pagos: number; gratis: number }
  servico: number
  custo: number
  categorias: Array<{ rotulo: string; volume: number; pagos: number; custo: number }>
  lidoEm: string
}

const REGRA = 'A Meta cobra por modelo entregue (marketing, utilidade, autenticação). A mensagem de serviço (resposta ' +
  'em até 24 h depois que a pessoa escreve) e o modelo de utilidade dentro dessa janela são grátis. Não existe mais a ' +
  'franquia de 1.000 grátis por mês (acabou em 07/2025). Números aproximados da Meta: a fatura manda.'

export default function BarraDoCustoOficial() {
  const [c, setC] = useState<Custo | null | undefined>(undefined)
  const [erro, setErro] = useState<string | null>(null)

  useEffect(() => {
    let vivo = true
    const ler = async () => {
      try {
        const r = await fetch('/api/oficial/custo-meta')
        const j = await r.json().catch(() => ({}))
        if (!vivo) return
        if (!r.ok) { setErro(j?.error || 'sem os números da Meta'); setC(null); return }
        setErro(null)
        setC(j)
      } catch { /* fica o último número */ }
    }
    void ler()
    const t = setInterval(() => { if (document.visibilityState === 'visible') void ler() }, 5 * 60_000)
    return () => { vivo = false; clearInterval(t) }
  }, [])

  const dinheiro = (v: number, moeda: string) =>
    v.toLocaleString('pt-BR', { style: 'currency', currency: moeda || 'BRL', minimumFractionDigits: 2 })
  const n = (v: number) => v.toLocaleString('pt-BR')

  if (c === undefined) {
    return (
      <div className="barra-calma barra-calma--linha" aria-label="Contador da API oficial">
        <span className="barra-calma__grupo">Meta</span>
        <div className="barra-calma__item"><span className="barra-calma__rotulo">Lendo os números do mês…</span></div>
      </div>
    )
  }
  if (c === null) {
    return (
      <div className="barra-calma barra-calma--linha" aria-label="Contador da API oficial">
        <span className="barra-calma__grupo">Meta</span>
        <div className="barra-calma__item" title={erro || ''}><span className="barra-calma__rotulo">Sem os números da Meta agora</span></div>
      </div>
    )
  }

  const media = c.modelos.pagos ? c.custo / c.modelos.pagos : 0
  return (
    <div className="barra-calma barra-calma--linha" aria-label="Contador da API oficial" title={REGRA}>
      <span className="barra-calma__grupo">Meta · {c.mes}</span>
      <div className="barra-calma__item" title="Modelos entregues no mês (os disparos)">
        <span className="barra-calma__rotulo">Disparos</span>
        <span className="barra-calma__valor">{n(c.modelos.total)}</span>
        <span className="barra-calma__rotulo">
          {n(c.modelos.pagos)} cobrado{c.modelos.pagos === 1 ? '' : 's'}{c.modelos.gratis ? ` · ${n(c.modelos.gratis)} grátis` : ''}
        </span>
      </div>
      <div className="barra-calma__item" title={media ? `Em média ${dinheiro(media, c.moeda)} por modelo cobrado` : REGRA}>
        <span className="barra-calma__rotulo">Gasto no mês</span>
        <span className="barra-calma__valor">{dinheiro(c.custo, c.moeda)}</span>
      </div>
      <div className="barra-calma__item" title="Respostas dentro das 24 h depois que a pessoa escreve: grátis, sem limite">
        <span className="barra-calma__rotulo">Serviço</span>
        <span className="barra-calma__valor">{n(c.servico)}</span>
        <span className="barra-calma__rotulo">grátis</span>
      </div>
      {c.categorias.map((x) => (
        <div key={x.rotulo} className="barra-calma__item" title={`${x.rotulo}: ${n(x.volume)} entregues, ${n(x.pagos)} cobrados`}>
          <span className="barra-calma__rotulo">{x.rotulo}</span>
          <span className="barra-calma__valor">{n(x.volume)}</span>
          <span className="barra-calma__rotulo">{dinheiro(x.custo, c.moeda)}</span>
        </div>
      ))}
      <div className="barra-calma__item" title={REGRA}>
        <span className="barra-calma__rotulo">Franquia de 1.000 grátis: não existe mais</span>
      </div>
    </div>
  )
}
