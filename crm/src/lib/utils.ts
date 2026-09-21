// Relative time formatting
export function formatRelativeTime(date: string | Date): string {
  const d = typeof date === 'string' ? new Date(date) : date
  const now = new Date()
  const diffMs = now.getTime() - d.getTime()
  const diffSecs = Math.floor(diffMs / 1000)
  const diffMins = Math.floor(diffSecs / 60)
  const diffHours = Math.floor(diffMins / 60)
  const diffDays = Math.floor(diffHours / 24)

  if (diffSecs < 60) return 'agora'
  if (diffMins < 60) return `${diffMins}m atrás`
  if (diffHours < 24) return `${diffHours}h atrás`
  if (diffDays < 7) return `${diffDays}d atrás`

  return d.toLocaleDateString('pt-BR')
}

// Format date for display
export function formatDate(date: string | Date): string {
  const d = typeof date === 'string' ? new Date(date) : date
  return d.toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  })
}

// Format time
export function formatTime(date: string | Date): string {
  const d = typeof date === 'string' ? new Date(date) : date
  return d.toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  })
}

// Generate initials for avatar
export function getInitials(name: string): string {
  if (!name) return '?'
  return name
    .split(' ')
    .map((n) => n[0])
    .join('')
    .toUpperCase()
    .slice(0, 2)
}

// Generate color based on string
export function stringToColor(str: string): string {
  if (!str) return '#6B7280'
  const colors = [
    '#FF6B6B',
    '#4ECDC4',
    '#45B7D1',
    '#FFA07A',
    '#98D8C8',
    '#F7DC6F',
    '#BB8FCE',
    '#85C1E2',
  ]
  let hash = 0
  for (let i = 0; i < str.length; i++) {
    hash = str.charCodeAt(i) + ((hash << 5) - hash)
  }
  return colors[Math.abs(hash) % colors.length]
}

// Interest level color
export function getInterestLevelColor(level: 'low' | 'medium' | 'high'): string {
  switch (level) {
    case 'low':
      return '#EF4444'
    case 'medium':
      return '#F59E0B'
    case 'high':
      return '#10B981'
    default:
      return '#6B7280'
  }
}

// Interest level label
export function getInterestLevelLabel(level: 'low' | 'medium' | 'high'): string {
  switch (level) {
    case 'low':
      return 'Baixo Interesse'
    case 'medium':
      return 'Interesse Médio'
    case 'high':
      return 'Alto Interesse'
    default:
      return 'Desconhecido'
  }
}

// Truncate text
export function truncate(text: string, length: number): string {
  return text.length > length ? text.slice(0, length) + '...' : text
}

// Format Phone Number to +55 (XX) 9 XXXX-XXXX or +55 (XX) XXXX-XXXX
export function formatPhone(phone?: string | number): string {
  if (!phone) return ''
  const phoneStr = String(phone)
  const cleaned = phoneStr.replace(/\D/g, '')

  if (cleaned.length < 10) return phoneStr

  let countryCode = '55'
  let ddd = ''
  let number = ''

  if (cleaned.startsWith('55') && cleaned.length >= 12) {
    countryCode = cleaned.substring(0, 2)
    ddd = cleaned.substring(2, 4)
    number = cleaned.substring(4)
  } else if (cleaned.length === 10 || cleaned.length === 11) {
    ddd = cleaned.substring(0, 2)
    number = cleaned.substring(2)
  } else {
    return phoneStr
  }

  if (number.length === 9) {
    return `+${countryCode} (${ddd}) ${number.substring(0, 1)} ${number.substring(1, 5)}-${number.substring(5)}`
  } else if (number.length === 8) {
    return `+${countryCode} (${ddd}) ${number.substring(0, 4)}-${number.substring(4)}`
  }

  return phoneStr
}

// Accent + case normalization mirroring SQL norm_text — used only for locating
// the match position. Output of renderSnippet is HTML-safe.
const stripAccents = (s: string) => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '')
const normalizeForMatch = (s: string) => stripAccents(s).toLowerCase()

const escapeHtml = (s: string) =>
  s.replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')

/**
 * Returns an HTML string with the first occurrence of `query` inside `content`
 * wrapped in <mark>, truncated to a window of ~60 chars around the match.
 * Escapes HTML before wrapping, so the result is safe for dangerouslySetInnerHTML.
 * If no match, returns the content truncated to 60 chars with ellipsis.
 */
export function renderSnippet(content: string, query: string): string {
  if (!content) return ''
  const trimmed = query.trim()
  if (!trimmed) return escapeHtml(content.length > 60 ? content.slice(0, 60) + '…' : content)

  const normContent = normalizeForMatch(content)
  const normQuery = normalizeForMatch(trimmed)
  const idx = normContent.indexOf(normQuery)

  if (idx === -1) {
    return escapeHtml(content.length > 60 ? content.slice(0, 60) + '…' : content)
  }

  const matchEnd = idx + trimmed.length
  const window = 60
  const start = Math.max(0, idx - Math.floor((window - trimmed.length) / 2))
  const end = Math.min(content.length, start + window)

  const before = escapeHtml(content.slice(start, idx))
  const match = escapeHtml(content.slice(idx, matchEnd))
  const after = escapeHtml(content.slice(matchEnd, end))

  const prefix = start > 0 ? '…' : ''
  const suffix = end < content.length ? '…' : ''

  return `${prefix}${before}<mark>${match}</mark>${after}${suffix}`
}
