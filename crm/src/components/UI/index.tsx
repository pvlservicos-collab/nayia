/**
 * Biblioteca de elementos do TitaCRM.
 *
 * Camada fina em cima das classes de `globals.css` (.glass*, .btn*, .pill,
 * .field, .surface-*). O CSS é a fonte da verdade visual; o que estes
 * componentes acrescentam é só a parte que CSS não resolve sozinho: o mapa
 * variante → classe num lugar só, e o `as`/`href` pra escolher a tag certa.
 *
 * Regra de ouro do design system, pra não se perder ao editar:
 *   - superfície (card, painel, dropdown, modal) → vidro, com degradê cinza
 *   - botão → preenchimento SÓLIDO, sem degradê; o capricho vai na borda
 *
 * Uso: import { Surface, Button, Pill, Field } from '@/components/UI'
 */
import Link from 'next/link'
import type { ReactNode, ButtonHTMLAttributes, InputHTMLAttributes } from 'react'

/* ── Surface ─────────────────────────────────────────────────────────────
   Qualquer superfície de vidro. `tone` é a profundidade (ver escala em
   globals.css), `interactive` liga o realce de hover. */

type SurfaceTone = 'soft' | 'default' | 'raised' | 'sunken'

const SURFACE_TONES: Record<SurfaceTone, string> = {
  soft: 'glass-soft',
  default: 'glass',
  raised: 'glass-raised',
  sunken: 'glass-sunken',
}

interface SurfaceProps {
  children: ReactNode
  tone?: SurfaceTone
  /** Realce de borda/sombra no hover — pra card clicável. */
  interactive?: boolean
  /** Fio amarelo da marca em volta — card em destaque. */
  accent?: boolean
  className?: string
}

export function Surface({
  children,
  tone = 'default',
  interactive,
  accent,
  className = '',
}: SurfaceProps) {
  return (
    <div
      className={[
        SURFACE_TONES[tone],
        interactive ? 'glass-hover' : '',
        accent ? 'glass-accent' : '',
        'rounded-2xl',
        className,
      ]
        .filter(Boolean)
        .join(' ')}
    >
      {children}
    </div>
  )
}

/* ── Button ──────────────────────────────────────────────────────────────
   Preenchimento sólido em todas as variantes — o relevo vem do contorno.
   Vira <Link> quando recebe `href`, senão <button>. */

export type ButtonVariant = 'primary' | 'secondary' | 'outline' | 'ghost' | 'danger'
export type ButtonSize = 'sm' | 'md' | 'lg'

const BUTTON_VARIANTS: Record<ButtonVariant, string> = {
  primary: 'btn-primary',
  secondary: 'btn-secondary',
  outline: 'btn-outline',
  ghost: 'btn-ghost',
  danger: 'btn-danger',
}

const BUTTON_SIZES: Record<ButtonSize, string> = {
  sm: 'btn-sm',
  md: '',
  lg: 'btn-lg',
}

export function buttonClass(
  variant: ButtonVariant = 'secondary',
  size: ButtonSize = 'md',
  className = ''
) {
  return ['btn', BUTTON_VARIANTS[variant], BUTTON_SIZES[size], className]
    .filter(Boolean)
    .join(' ')
}

interface UIButtonProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'className'> {
  variant?: ButtonVariant
  size?: ButtonSize
  href?: string
  className?: string
  children: ReactNode
}

export function Button({
  variant = 'secondary',
  size = 'md',
  href,
  className = '',
  children,
  ...rest
}: UIButtonProps) {
  const classes = buttonClass(variant, size, className)

  if (href) {
    return (
      <Link href={href} className={classes}>
        {children}
      </Link>
    )
  }

  return (
    <button type="button" className={classes} {...rest}>
      {children}
    </button>
  )
}

/* ── IconButton ──────────────────────────────────────────────────────────
   Botão só-ícone. `size` aqui é a caixa em px (área de toque), não a
   tipografia — por isso não reaproveita ButtonSize. */

interface IconButtonProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'className'> {
  children: ReactNode
  /** Lado da caixa em px. 40 é o mínimo confortável no toque. */
  size?: number
  className?: string
}

export function IconButton({ children, size = 36, className = '', ...rest }: IconButtonProps) {
  return (
    <button
      type="button"
      className={`btn-icon app-tap-target ${className}`}
      style={{ width: size, height: size }}
      {...rest}
    >
      {children}
    </button>
  )
}

/* ── Pill ────────────────────────────────────────────────────────────────
   Chip de filtro / aba em formato de pílula. */

interface PillProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'className'> {
  active?: boolean
  children: ReactNode
  className?: string
}

export function Pill({ active, children, className = '', ...rest }: PillProps) {
  return (
    <button
      type="button"
      className={`pill ${active ? 'pill-active' : ''} ${className}`}
      {...rest}
    >
      {children}
    </button>
  )
}

/* ── Field ───────────────────────────────────────────────────────────────
   Input de texto com o contorno padrão do sistema. */

interface FieldProps extends Omit<InputHTMLAttributes<HTMLInputElement>, 'className'> {
  className?: string
}

export function Field({ className = '', ...rest }: FieldProps) {
  return <input className={`field ${className}`} {...rest} />
}

/* ── SectionTitle ────────────────────────────────────────────────────────
   Cabeçalho de seção: ícone em caixa de vidro + título (+ subtítulo). */

interface SectionTitleProps {
  icon: ReactNode
  title: string
  subtitle?: string
  className?: string
}

export function SectionTitle({ icon, title, subtitle, className = '' }: SectionTitleProps) {
  return (
    <div className={`flex items-center gap-2.5 ${className}`}>
      <div className="w-9 h-9 rounded-xl glass-soft flex items-center justify-center text-accent-2 flex-shrink-0">
        {icon}
      </div>
      <div className="min-w-0">
        <h2 className="text-sm font-semibold text-ink truncate">{title}</h2>
        {subtitle && <p className="text-xs text-muted truncate">{subtitle}</p>}
      </div>
    </div>
  )
}

/* ── Divider ─────────────────────────────────────────────────────────────
   Fio com fade nas pontas — mais discreto que uma border reta. */

export function Divider({ className = '' }: { className?: string }) {
  return <div className={`h-px hairline-x ${className}`} />
}

/* ── StatTile ────────────────────────────────────────────────────────────
   Card de número: rótulo em cima, valor grande embaixo. É o formato repetido
   em quase toda seção do dashboard. */

interface StatTileProps {
  label: string
  value: string
  icon?: ReactNode
  /** Marcador colorido antes do rótulo (cor do canal, da etapa etc). */
  dotColor?: string
  hint?: string
  highlight?: boolean
  className?: string
}

export function StatTile({
  label,
  value,
  icon,
  dotColor,
  hint,
  highlight,
  className = '',
}: StatTileProps) {
  return (
    <Surface interactive accent={highlight} className={`p-4 ${className}`}>
      <div className="flex items-center gap-2 mb-3">
        {dotColor && (
          <span
            className="w-2 h-2 rounded-full flex-shrink-0"
            style={{ backgroundColor: dotColor }}
          />
        )}
        {icon && (
          <span className={highlight ? 'text-accent-2' : 'text-muted'}>{icon}</span>
        )}
        <p className="text-xs font-medium text-muted truncate">{label}</p>
      </div>
      <p
        className={`text-2xl font-bold leading-none ${highlight ? 'text-accent-2' : 'text-ink'}`}
      >
        {value}
      </p>
      {hint && <p className="text-[11px] text-muted mt-1.5">{hint}</p>}
    </Surface>
  )
}
