'use client'

import { useEffect, useState } from 'react'

const MOBILE_QUERY = '(max-width: 767px)'

/**
 * true abaixo do breakpoint `md` do Tailwind (768px). No primeiro render (servidor
 * e primeira pintura no cliente) sempre retorna false — evita layout mobile piscando
 * antes do JS montar; a tela corrige pro valor real logo em seguida.
 */
export function useIsMobile(): boolean {
  const [isMobile, setIsMobile] = useState(false)

  useEffect(() => {
    const mql = window.matchMedia(MOBILE_QUERY)
    setIsMobile(mql.matches)

    const handleChange = (e: MediaQueryListEvent) => setIsMobile(e.matches)
    mql.addEventListener('change', handleChange)
    return () => mql.removeEventListener('change', handleChange)
  }, [])

  return isMobile
}
