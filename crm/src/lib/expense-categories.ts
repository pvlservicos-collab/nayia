export const EXPENSE_CATEGORY_OPTIONS = [
  { value: 'fornecedor', label: 'Fornecedor' },
  { value: 'assinatura_software', label: 'Assinatura / Software' },
  { value: 'frete', label: 'Frete' },
  { value: 'marketing', label: 'Marketing' },
  { value: 'impostos', label: 'Impostos' },
  { value: 'salarios', label: 'Salários' },
  { value: 'outros', label: 'Outros' },
]

export const EXPENSE_CATEGORY_LABELS: Record<string, string> = Object.fromEntries(
  EXPENSE_CATEGORY_OPTIONS.map(c => [c.value, c.label])
)
