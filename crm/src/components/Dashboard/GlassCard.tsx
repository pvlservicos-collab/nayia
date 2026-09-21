/**
 * Mantido como fachada fina em cima de <Surface> (src/components/UI) — o
 * dashboard inteiro importa GlassCard, e o vidro de verdade agora mora no
 * design system. Em código novo prefira <Surface>/<SectionTitle> direto.
 */
import type { ReactNode } from 'react'
import { Surface, SectionTitle } from '@/components/UI'

interface GlassCardProps {
  children: ReactNode
  className?: string
  /** Realce de borda/sombra no hover — pra card clicável. */
  interactive?: boolean
  /** Fio amarelo da marca em volta — card em destaque. */
  accent?: boolean
}

export default function GlassCard({
  children,
  className = '',
  interactive = true,
  accent,
}: GlassCardProps) {
  return (
    <Surface interactive={interactive} accent={accent} className={`rounded-3xl ${className}`}>
      {children}
    </Surface>
  )
}

interface SectionHeaderProps {
  icon: ReactNode
  title: string
  subtitle?: string
}

export function SectionHeader({ icon, title, subtitle }: SectionHeaderProps) {
  return <SectionTitle icon={icon} title={title} subtitle={subtitle} className="mb-4" />
}
