'use client'

/**
 * O PUXADOR: arrastar a borda de um painel para alargar ou estreitar (Pedro,
 * 09/10/2026: "quero poder arrastar o canto da barra da direita para o lado").
 * É o mesmo desenho que o card da Parceria já tinha (PainelContatoParceria),
 * posto num lugar só para a lista da esquerda, o card da captação e o card da
 * linha oficial usarem igual.
 *
 * A largura fica no localStorage de quem está usando, por painel (`chave`).
 * `lado` é em que borda do painel o puxador fica: 'esquerda' (o painel está à
 * direita, arrastar para a esquerda alarga) ou 'direita' (o painel está à
 * esquerda, arrastar para a direita alarga).
 */
import { useEffect, useRef, useState } from 'react'

export function usePuxador(chave: string, o: { min: number; max: number; padrao: number; lado: 'esquerda' | 'direita' }) {
  const [largura, setLargura] = useState<number>(o.padrao)
  const [arrastando, setArrastando] = useState(false)
  useEffect(() => {
    try {
      const g = Number(localStorage.getItem(chave))
      if (g >= o.min && g <= o.max) setLargura(g)
    } catch { /* sem localStorage: fica no padrão */ }
  }, [chave, o.min, o.max])

  const inicio = useRef<{ x: number; largura: number } | null>(null)
  const sinal = o.lado === 'esquerda' ? -1 : 1

  const puxador = {
    className: `wa-puxador wa-puxador--${o.lado}${arrastando ? ' wa-puxador--arrastando' : ''}`,
    role: 'separator' as const,
    'aria-orientation': 'vertical' as const,
    title: 'Arraste para alargar ou estreitar',
    onPointerDown: (e: React.PointerEvent) => {
      e.preventDefault()
      inicio.current = { x: e.clientX, largura }
      setArrastando(true)
      ;(e.target as HTMLElement).setPointerCapture?.(e.pointerId)
    },
    onPointerMove: (e: React.PointerEvent) => {
      if (!inicio.current) return
      setLargura(Math.min(o.max, Math.max(o.min, inicio.current.largura + sinal * (e.clientX - inicio.current.x))))
    },
    onPointerUp: () => soltar(),
    onPointerCancel: () => soltar(),
  }
  function soltar() {
    if (!inicio.current) return
    inicio.current = null
    setArrastando(false)
    setLargura((l) => { try { localStorage.setItem(chave, String(l)) } catch { /* vale só até recarregar */ } return l })
  }

  return { largura, arrastando, puxador }
}
