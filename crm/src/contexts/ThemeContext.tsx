'use client'

import { createContext, useContext, useEffect, useState, ReactNode } from 'react'

interface ThemeContextType {
  isDark: boolean
  toggleTheme: () => void
}

const ThemeContext = createContext<ThemeContextType>({ isDark: false, toggleTheme: () => {} })

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [isDark, setIsDark] = useState(false)
  const [mounted, setMounted] = useState(false)

  useEffect(() => {
    setMounted(true)
    const stored = localStorage.getItem('follem-theme')
    // Marca dark-first: quem nunca escolheu um tema começa no escuro (identidade da
    // marca). O script inline em layout.tsx já aplica a classe antes da hidratação
    // pra não piscar claro→escuro; isto aqui só mantém o estado React em sincronia.
    const shouldBeDark = stored ? stored === 'dark' : true
    setIsDark(shouldBeDark)
    document.documentElement.classList.toggle('dark', shouldBeDark)
  }, [])

  const toggleTheme = () => {
    setIsDark(prev => {
      const next = !prev
      if (next) {
        document.documentElement.classList.add('dark')
        localStorage.setItem('follem-theme', 'dark')
      } else {
        document.documentElement.classList.remove('dark')
        localStorage.setItem('follem-theme', 'light')
      }
      return next
    })
  }

  return (
    <ThemeContext.Provider value={{ isDark, toggleTheme }}>
      {children}
    </ThemeContext.Provider>
  )
}

export const useTheme = () => useContext(ThemeContext)
