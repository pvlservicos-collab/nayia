export const QUICK_REPLY_VARIABLES = [
  { token: '{{nome}}', label: 'Nome do lead' },
  { token: '{{primeiro_nome}}', label: 'Primeiro nome' },
  { token: '{{telefone}}', label: 'Telefone' },
  { token: '{{atendente}}', label: 'Seu nome' },
] as const

export interface QuickReplyInterpolationContext {
  name?: string | null
  phone?: string | null
  agentName?: string | null
}

/**
 * Substitui os placeholders {{...}} do template pelo valor real do lead/atendente.
 * Placeholder sem valor disponível vira string vazia — nunca deixa "{{nome}}" literal
 * numa mensagem que vai para o cliente.
 */
function replaceAllOccurrences(text: string, token: string, value: string): string {
  return text.split(token).join(value)
}

export function interpolateQuickReply(template: string, ctx: QuickReplyInterpolationContext): string {
  const name = ctx.name?.trim() || ''
  const firstName = name.split(/\s+/)[0] || ''

  let result = template
  result = replaceAllOccurrences(result, '{{nome}}', name)
  result = replaceAllOccurrences(result, '{{primeiro_nome}}', firstName)
  result = replaceAllOccurrences(result, '{{telefone}}', ctx.phone?.trim() || '')
  result = replaceAllOccurrences(result, '{{atendente}}', ctx.agentName?.trim() || '')
  return result
}
