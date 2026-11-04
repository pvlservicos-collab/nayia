'use client'

/**
 * A BARRA DE CARREGAMENTO (Pedro, 04/11/2026: "na opção Enviar imóvel, em todas as versões e números, está lento para aparecer
 * o imóvel e lento para mandar; faz uma barrinha de carregamento até enviar a mensagem").
 *
 *   sem `progresso`  vai e volta (não se sabe quanto falta: buscando o imóvel, pedindo o envio)
 *   com `progresso`  enche de 0 a 1 (o envio pelo Leads: "2 de 3 imóveis enviados")
 *
 * O desenho está no globals.css (.barra-carregando). useAcompanharPedidoDaCaptacao: o mesmo acompanhamento do painel do Leads
 * (/api/captacao/enviar-imoveis?id=), para quem pede o envio pelo 8595 de outra tela.
 */
import { useCallback, useEffect, useRef, useState } from 'react'

export default function BarraDeCarregamento({ rotulo, progresso }: { rotulo?: string | null; progresso?: number | null }) {
  const p = typeof progresso === 'number' && Number.isFinite(progresso) ? Math.max(0.04, Math.min(1, progresso)) : null
  return (
    <div className="flex flex-col gap-1" role="progressbar" aria-busy="true" aria-label={rotulo || 'Carregando'}
         {...(p !== null ? { 'aria-valuenow': Math.round(p * 100), 'aria-valuemin': 0, 'aria-valuemax': 100 } : {})}>
      <div className={`barra-carregando ${p === null ? 'barra-carregando--indeterminada' : ''}`}>
        <span style={p !== null ? { width: `${p * 100}%` } : undefined} />
      </div>
      {rotulo && <span className="text-[11.5px]" style={{ color: 'var(--wa-text-2, #8696a0)' }}>{rotulo}</span>}
    </div>
  )
}

export type AcompanhamentoDoEnvio = { andando: boolean; progresso: number | null; texto: string | null; fim: 'enviado' | 'falhou' | 'demorou' | null }

/** acompanha um pedido de envio pelo 8595 até sair (de 3 em 3 s, até 15 min) */
export function useAcompanharPedidoDaCaptacao() {
  const [estado, setEstado] = useState<AcompanhamentoDoEnvio>({ andando: false, progresso: null, texto: null, fim: null })
  const vigia = useRef<ReturnType<typeof setTimeout> | null>(null)
  useEffect(() => () => { if (vigia.current) clearTimeout(vigia.current) }, [])
  const passo = useCallback((id: number, desde: number) => {
    vigia.current = setTimeout(async () => {
      try {
        const r = await fetch(`/api/captacao/enviar-imoveis?id=${id}`)
        const e = await r.json().catch(() => ({}))
        if (e?.estado === 'enviado' || e?.estado === 'falhou') {
          setEstado({ andando: false, progresso: 1, texto: e.resultado || (e.estado === 'enviado' ? 'Enviado.' : 'Não saiu.'), fim: e.estado })
          return
        }
        const feitos = Array.isArray(e?.enviados) ? e.enviados.length : 0
        const total = Array.isArray(e?.codigos) ? e.codigos.length : 0
        setEstado({ andando: true, progresso: total ? feitos / total : null, texto: total ? `Enviando pelo 8595… ${feitos} de ${total}` : 'Na fila da Nay…', fim: null })
      } catch { /* sem rede: tenta de novo */ }
      if (Date.now() - desde < 15 * 60_000) passo(id, desde)
      else setEstado({ andando: false, progresso: null, texto: 'O envio está demorando; ele continua saindo pela Nay.', fim: 'demorou' })
    }, 3000)
  }, [])
  const iniciar = useCallback((id: number) => {
    if (vigia.current) clearTimeout(vigia.current)
    setEstado({ andando: true, progresso: null, texto: 'Na fila da Nay: sai em alguns segundos, um imóvel de cada vez.', fim: null })
    passo(id, Date.now())
  }, [passo])
  return { ...estado, iniciar }
}
