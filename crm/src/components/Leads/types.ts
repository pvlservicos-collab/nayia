import type { LeadSourceColumn } from '@/lib/leadSources'

/** Uma linha do log — o que GET /api/lead-sources/{source}/submissions devolve. */
export interface Submission {
  id: string
  external_id: string | null
  name: string | null
  email: string | null
  phone: string | null
  instagram: string | null
  /** Campos específicos da fonte. O que existe aqui depende do `source`. */
  payload: Record<string, any>
  lead_id: string | null
  /** Preenchido na primeira vez que alguém abriu a conversa por esta lista. */
  contacted_at: string | null
  received_at: string
  updated_at: string
  /** Etapa do lead no pipeline — vem do join, alimenta o filtro por etapa. */
  stage_id: string | null
  stage_name: string | null
  stage_color: string | null
}

/** Uma aba — o que GET /api/lead-sources devolve. */
export interface LeadSourceTab {
  key: string
  label: string
  description: string
  columns: LeadSourceColumn[]
  required: string[]
  total: number
  last_received_at: string | null
}

/** Chip de filtro por etapa, já com quantos leads estão nela. */
export interface EtapaFiltro {
  id: string
  name: string
  color: string | null
  total: number
}

/** Contagem por momento da jornada, pros chips de filtro (ver src/lib/momentos.ts). */
export interface MomentoFiltro {
  key: string
  total: number
}
