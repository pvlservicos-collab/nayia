// Stage colors mapped by rank (position in pipeline)
// Based on the mockup: ENTRADA (orange), QUALIFICAÇÃO (yellow), EM DESENVOLVIMENTO (blue), PROPOSTA (purple), NEGOCIAÇÃO (green)

export interface StageColor {
  bar: string
  bgLight: string
}

export const STAGE_COLORS: StageColor[] = [
  { bar: '#F97316', bgLight: '#FFF7ED' }, // orange
  { bar: '#EAB308', bgLight: '#FEFCE8' }, // yellow
  { bar: '#3B82F6', bgLight: '#EFF6FF' }, // blue
  { bar: '#A855F7', bgLight: '#FAF5FF' }, // purple
  { bar: '#22C55E', bgLight: '#F0FDF4' }, // green
  { bar: '#EC4899', bgLight: '#FDF2F8' }, // pink (fallback for 6+)
  { bar: '#14B8A6', bgLight: '#F0FDFA' }, // teal
  { bar: '#F43F5E', bgLight: '#FFF1F2' }, // rose
]

export function getStageColor(rank: number): StageColor {
  const idx = Math.max(0, rank - 1) % STAGE_COLORS.length
  return STAGE_COLORS[idx]
}
