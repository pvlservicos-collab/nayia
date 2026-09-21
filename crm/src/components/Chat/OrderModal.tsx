'use client'

import { useState, useEffect, useMemo } from 'react'
import ReactDOM from 'react-dom'
import { X, Plus, Minus, MapPin, Check, Copy, ClipboardText, CaretDown, CaretUp, MagicWand } from '@phosphor-icons/react'
import { LeadWithOwner } from '@/lib/types'

interface Product {
  id: string
  name: string
  price: string
  description?: string
}

interface OrderItem {
  product_id: string | null
  product_name: string
  quantity: number
  unit_price: number
}

interface OrderModalProps {
  lead: LeadWithOwner
  organizationId: string
  onClose: () => void
  onSuccess?: (order: any) => void
}

const PAYMENT_METHODS: { value: string; label: string; color: string; bg: string; border: string }[] = [
  { value: 'pix',         label: 'PIX',             color: '#4ade80', bg: 'rgba(34,197,94,0.15)',   border: 'rgba(34,197,94,0.4)'  },
  { value: 'credit_card', label: 'Cartão de Crédito', color: '#60a5fa', bg: 'rgba(59,130,246,0.15)', border: 'rgba(59,130,246,0.4)' },
  { value: 'boleto',      label: 'Boleto',           color: '#fb923c', bg: 'rgba(251,146,60,0.15)',  border: 'rgba(251,146,60,0.4)' },
  { value: 'dinheiro',    label: 'Dinheiro',         color: '#34d399', bg: 'rgba(52,211,153,0.15)',  border: 'rgba(52,211,153,0.4)' },
]

const PAYMENT_STATUS: { value: string; label: string; color: string; bg: string; border: string }[] = [
  { value: 'pending', label: 'Pendente', color: '#facc15', bg: 'rgba(234,179,8,0.15)',  border: 'rgba(234,179,8,0.4)'  },
  { value: 'paid',    label: 'Pago',     color: '#4ade80', bg: 'rgba(34,197,94,0.15)',  border: 'rgba(34,197,94,0.4)'  },
]

function maskCpf(v: string) {
  return v.replace(/\D/g, '').slice(0, 11)
    .replace(/(\d{3})(\d)/, '$1.$2')
    .replace(/(\d{3})(\d)/, '$1.$2')
    .replace(/(\d{3})(\d{1,2})$/, '$1-$2')
}

function maskCep(v: string) {
  return v.replace(/\D/g, '').slice(0, 8).replace(/(\d{5})(\d)/, '$1-$2')
}

// Reconhece o template fixo que o funil automatizado pede pro cliente preencher
// ("DADOS PARA ENVIO: NOME COMPLETO, CPF, CEP, ENDEREÇO...") — usado tanto pra saber
// se vale destacar uma mensagem do histórico quanto pra extrair os campos quando o
// vendedor pede pra preencher (sempre sob revisão dele, nunca automático sem clique).
const TEMPLATE_LABELS = ['NOME COMPLETO', 'CPF', 'CEP', 'ENDEREÇO', 'COMPLEMENTO', 'PRODUTO', 'PAGAMENTO', 'VALOR', 'E-MAIL', 'TELEFONE']

interface ParsedCustomerData {
  name?: string
  cpf?: string
  cep?: string
  address?: string
  complement?: string
  email?: string
  paymentMethod?: string
  value?: number
}

function countMatchedLabels(text: string): number {
  const upper = text.toUpperCase()
  return TEMPLATE_LABELS.filter(l => upper.includes(l)).length
}

function normalizeLine(line: string): string {
  return line.replace(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/gu, '').trim()
}

function matchLabelValue(line: string, label: string): string | null {
  const upper = line.toUpperCase()
  const idx = upper.indexOf(label)
  if (idx === -1) return null
  const rest = line.slice(idx + label.length).replace(/^[:\s]+/, '').trim()
  return rest || null
}

function parseCustomerDataMessage(text: string): ParsedCustomerData {
  const result: ParsedCustomerData = {}
  for (const rawLine of text.split('\n')) {
    const line = normalizeLine(rawLine)
    if (!line || line.startsWith('(')) continue // linha de dica do próprio template
    if (!result.name) { const v = matchLabelValue(line, 'NOME COMPLETO'); if (v) result.name = v }
    if (!result.cpf) { const v = matchLabelValue(line, 'CPF'); if (v) result.cpf = v }
    if (!result.cep) { const v = matchLabelValue(line, 'CEP'); if (v) result.cep = v }
    if (!result.address) { const v = matchLabelValue(line, 'ENDEREÇO'); if (v) result.address = v }
    if (!result.complement) { const v = matchLabelValue(line, 'COMPLEMENTO'); if (v) result.complement = v }
    if (!result.email) { const v = matchLabelValue(line, 'E-MAIL'); if (v) result.email = v }
    if (result.value === undefined) {
      const v = matchLabelValue(line, 'VALOR')
      if (v) {
        const num = parseFloat(v.replace(/[^\d,.-]/g, '').replace(',', '.'))
        if (!isNaN(num)) result.value = num
      }
    }
  }
  const upperText = text.toUpperCase()
  if (upperText.includes('PIX')) result.paymentMethod = 'pix'
  else if (upperText.includes('CART')) result.paymentMethod = 'credit_card'
  else if (upperText.includes('BOLETO')) result.paymentMethod = 'boleto'
  else if (upperText.includes('DINHEIRO')) result.paymentMethod = 'dinheiro'
  return result
}

export default function OrderModal({ lead, organizationId, onClose, onSuccess }: OrderModalProps) {
  const [products, setProducts] = useState<Product[]>([])
  const [items, setItems] = useState<OrderItem[]>([{ product_id: null, product_name: '', quantity: 1, unit_price: 0 }])
  // Allow selecting up to 2 payment methods
  const [selectedMethods, setSelectedMethods] = useState<string[]>(['pix'])
  const [paymentStatus, setPaymentStatus] = useState('pending')
  const [notes, setNotes] = useState('')
  const [customerName, setCustomerName] = useState(lead.title || '')
  const [customerPhone, setCustomerPhone] = useState(lead.phone || '')
  const [customerEmail, setCustomerEmail] = useState(lead.email || '')
  const [cpf, setCpf] = useState('')
  // Pré-preenche com o endereço salvo do último pedido do lead, se já tiver —
  // evita o cliente ter que reinformar tudo numa segunda compra.
  const [cep, setCep] = useState(lead.cep ? maskCep(lead.cep) : '')
  const [address, setAddress] = useState(lead.address || '')
  const [addressNumber, setAddressNumber] = useState(lead.address_number || '')
  const [addressComplement, setAddressComplement] = useState(lead.address_complement || '')
  const [neighborhood, setNeighborhood] = useState(lead.neighborhood || '')
  const [city, setCity] = useState(lead.city || '')
  const [state, setState] = useState(lead.state || '')
  const [cepLoading, setCepLoading] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [productSearch, setProductSearch] = useState<Record<number, string>>({})
  const [showProductDropdown, setShowProductDropdown] = useState<Record<number, boolean>>({})
  const [sourceMessage, setSourceMessage] = useState('')
  const [showSourceMessage, setShowSourceMessage] = useState(true)
  const [copied, setCopied] = useState(false)
  const [autoFilled, setAutoFilled] = useState(false)

  // Reparseia toda vez que o texto muda (seja preenchido sozinho, colado ou editado à mão)
  const parsedData = useMemo(() => parseCustomerDataMessage(sourceMessage), [sourceMessage])
  const parsedFieldsCount = Object.keys(parsedData).length

  useEffect(() => {
    fetch('/api/products?include_inactive=false')
      .then(r => r.ok ? r.json() : { data: [] })
      .then(({ data }) => setProducts(data || []))
      .catch(() => {})
  }, [])

  useEffect(() => {
    fetch(`/api/leads/${lead.id}/messages`)
      .then(r => r.ok ? r.json() : { data: [] })
      .then(({ data }) => {
        const messages: { content: string }[] = data || []
        for (let i = messages.length - 1; i >= 0; i--) {
          const content = messages[i]?.content || ''
          if (countMatchedLabels(content) >= 3) {
            setSourceMessage(content)
            break
          }
        }
      })
      .catch(() => {})
  }, [lead.id])

  const resolveCep = async (cleanCep: string) => {
    if (cleanCep.length !== 8) return
    setCepLoading(true)
    try {
      // Sem timeout, uma rede móvel instável deixa "Buscando..." pendurado indefinidamente
      const res = await fetch(`https://viacep.com.br/ws/${cleanCep}/json/`, { signal: AbortSignal.timeout(8000) })
      const data = await res.json()
      if (!data.erro) {
        setAddress(data.logradouro || '')
        setNeighborhood(data.bairro || '')
        setCity(data.localidade || '')
        setState(data.uf || '')
      }
    } catch {}
    setCepLoading(false)
  }

  // Trava o scroll do body enquanto o modal está aberto — no iOS, sem isso o fundo da
  // conversa pode "roubar" o toque por trás do overlay fixo.
  useEffect(() => {
    const prev = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => { document.body.style.overflow = prev }
  }, [])

  const handleCepBlur = () => resolveCep(cep.replace(/\D/g, ''))

  const handleCopySourceMessage = async () => {
    if (!sourceMessage) return
    try {
      await navigator.clipboard.writeText(sourceMessage)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch {}
  }

  const handleAutoFill = () => {
    if (parsedData.name) setCustomerName(parsedData.name)
    if (parsedData.cpf) setCpf(maskCpf(parsedData.cpf))
    if (parsedData.email) setCustomerEmail(parsedData.email)
    if (parsedData.address) setAddress(parsedData.address)
    if (parsedData.complement) setAddressComplement(parsedData.complement)
    if (parsedData.paymentMethod) setSelectedMethods([parsedData.paymentMethod])
    if (parsedData.value && items.length === 1 && items[0].unit_price === 0) {
      setItems(prev => prev.map((it, i) => i === 0 ? { ...it, unit_price: parsedData.value! } : it))
    }
    if (parsedData.cep) {
      const cleanCep = parsedData.cep.replace(/\D/g, '')
      if (cleanCep.length === 8) {
        setCep(maskCep(parsedData.cep))
        if (!parsedData.address) resolveCep(cleanCep)
      }
    }
    setAutoFilled(true)
    setTimeout(() => setAutoFilled(false), 2000)
  }

  const toggleMethod = (value: string) => {
    setSelectedMethods(prev => {
      if (prev.includes(value)) {
        // Always keep at least 1
        if (prev.length === 1) return prev
        return prev.filter(m => m !== value)
      }
      // Max 2 methods
      if (prev.length >= 2) return [prev[1], value]
      return [...prev, value]
    })
  }

  const totalValue = items.reduce((sum, item) => sum + item.unit_price * item.quantity, 0)

  const handleItemProductSelect = (idx: number, product: Product) => {
    setItems(prev => prev.map((item, i) => i === idx ? {
      ...item, product_id: product.id, product_name: product.name, unit_price: Number(product.price),
    } : item))
    setProductSearch(prev => ({ ...prev, [idx]: product.name }))
    setShowProductDropdown(prev => ({ ...prev, [idx]: false }))
  }

  const handleSubmit = async () => {
    if (items.some(item => !item.product_name.trim())) {
      setError('Preencha o nome do produto em todos os itens.'); return
    }
    setSaving(true); setError(null)
    try {
      const primaryMethod = selectedMethods[0]
      const res = await fetch('/api/orders', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          lead_id: lead.id,
          payment_method: primaryMethod,
          payment_status: paymentStatus,
          delivery_status: 'pending',
          total_value: totalValue,
          notes: selectedMethods.length > 1 ? `Pagamento: ${selectedMethods.map(m => PAYMENT_METHODS.find(p => p.value === m)?.label).join(' + ')}${notes ? '\n' + notes : ''}` : (notes || null),
          customer_name: customerName,
          customer_phone: customerPhone,
          customer_email: customerEmail,
          customer_cpf: cpf.replace(/\D/g, '') || null,
          customer_cep: cep.replace(/\D/g, '') || null,
          customer_address: address || null,
          customer_address_number: addressNumber || null,
          customer_address_complement: addressComplement || null,
          customer_neighborhood: neighborhood || null,
          customer_city: city || null,
          customer_state: state || null,
          items: items.map(item => ({
            product_id: item.product_id,
            product_name: item.product_name,
            quantity: item.quantity,
            unit_price: item.unit_price,
          })),
        }),
      })
      if (!res.ok) { const d = await res.json(); throw new Error(d.error || 'Erro ao salvar pedido') }
      const { data } = await res.json()
      if (onSuccess) onSuccess(data)
      onClose()
    } catch (err: any) { setError(err.message) }
    finally { setSaving(false) }
  }

  const modal = (
    <div className="fixed inset-0 z-[9999] flex items-center justify-center p-4" style={{ backgroundColor: 'rgba(0,0,0,0.75)' }}>
      <div className="bg-[#1a2730] border border-[var(--chat-border)] rounded-2xl w-full max-w-2xl max-h-[90dvh] flex flex-col shadow-2xl">
        {/* Header */}
        <div className="flex items-center justify-between p-5 border-b border-[var(--chat-border)]">
          <h2 className="text-lg font-bold text-[var(--chat-text-primary)]">Registrar Venda</h2>
          <button onClick={onClose} className="text-[var(--chat-text-muted)] hover:text-[var(--chat-text-primary)] transition-colors"><X size={20} /></button>
        </div>

        <div className="flex-1 overflow-y-auto p-5 space-y-5 chat-dark-scroll">
          {/* Mensagem do cliente — preenche sozinho quando reconhece o template, mas também
              dá pra colar/editar na mão (ex: se a detecção não achar ou vier de outra conversa) */}
          <div className="rounded-xl border border-[var(--chat-border)] bg-[var(--chat-bg-panel)] overflow-hidden">
            <div className="flex items-center justify-between gap-2 px-4 py-3">
              <div className="flex items-center gap-2 text-[var(--chat-accent)]">
                <ClipboardText size={16} weight="bold" />
                <p className="text-xs font-bold uppercase tracking-wide">Mensagem do cliente</p>
              </div>
              <div className="flex items-center gap-3">
                <button onClick={handleCopySourceMessage} className="flex items-center gap-1 text-xs font-medium text-[var(--chat-text-muted)] hover:text-[var(--chat-text-primary)] transition-colors">
                  {copied ? <Check size={14} className="text-green-400" /> : <Copy size={14} />}
                  {copied ? 'Copiado' : 'Copiar'}
                </button>
                <button onClick={() => setShowSourceMessage(v => !v)} className="text-[var(--chat-text-muted)] hover:text-[var(--chat-text-primary)] transition-colors" aria-label={showSourceMessage ? 'Recolher' : 'Expandir'}>
                  {showSourceMessage ? <CaretUp size={16} /> : <CaretDown size={16} />}
                </button>
              </div>
            </div>

            {showSourceMessage && (
              <div className="px-4 pb-4 space-y-3">
                <textarea
                  value={sourceMessage}
                  onChange={e => setSourceMessage(e.target.value)}
                  placeholder="Cole aqui a mensagem que o cliente mandou com os dados de entrega..."
                  rows={6}
                  className="w-full text-xs leading-relaxed text-[var(--chat-text-secondary)] bg-[var(--chat-bg-base)] rounded-lg p-3 max-h-48 overflow-y-auto resize-y focus:outline-none focus:ring-1 focus:ring-[var(--chat-accent)] placeholder-[var(--chat-text-tertiary)]"
                />
                {parsedFieldsCount > 0 && (
                  <button
                    onClick={handleAutoFill}
                    className="w-full flex items-center justify-center gap-2 px-4 py-2 rounded-lg text-sm font-bold transition-colors"
                    style={{ backgroundColor: 'rgba(83,189,235,0.12)', border: '1px solid rgba(83,189,235,0.4)', color: 'var(--chat-accent)' }}
                  >
                    {autoFilled ? <Check size={16} weight="bold" /> : <MagicWand size={16} weight="bold" />}
                    {autoFilled ? 'Campos preenchidos!' : `Preencher ${parsedFieldsCount} campo${parsedFieldsCount !== 1 ? 's' : ''} identificado${parsedFieldsCount !== 1 ? 's' : ''}`}
                  </button>
                )}
              </div>
            )}
          </div>

          {/* Produtos */}
          <div>
            <p className="text-[10px] font-bold uppercase tracking-wider text-[var(--chat-text-muted)] mb-3">Produtos</p>
            <div className="space-y-2">
              {items.map((item, idx) => {
                const filtered = products.filter(p => p.name.toLowerCase().includes((productSearch[idx] || '').toLowerCase()))
                return (
                  <div key={idx} className="flex items-start gap-2">
                    <div className="flex-1 relative">
                      <input
                        type="text"
                        placeholder="Nome do produto..."
                        value={productSearch[idx] !== undefined ? productSearch[idx] : item.product_name}
                        onChange={e => {
                          setProductSearch(prev => ({ ...prev, [idx]: e.target.value }))
                          setItems(prev => prev.map((it, i) => i === idx ? { ...it, product_name: e.target.value, product_id: null } : it))
                          setShowProductDropdown(prev => ({ ...prev, [idx]: true }))
                        }}
                        onFocus={() => setShowProductDropdown(prev => ({ ...prev, [idx]: true }))}
                        onBlur={() => setTimeout(() => setShowProductDropdown(prev => ({ ...prev, [idx]: false })), 150)}
                        className="w-full px-3 py-2 text-sm bg-[var(--chat-bg-field)] border border-[var(--chat-border)] rounded-lg text-[var(--chat-text-primary)] placeholder-[var(--chat-text-tertiary)] focus:outline-none focus:border-[var(--chat-accent)]"
                      />
                      {showProductDropdown[idx] && filtered.length > 0 && (
                        <div className="absolute top-full left-0 right-0 mt-1 bg-[var(--chat-bg-menu)] border border-[var(--chat-border)] rounded-lg shadow-lg z-10 max-h-40 overflow-y-auto">
                          {filtered.map(p => (
                            <button key={p.id} onMouseDown={() => handleItemProductSelect(idx, p)} className="w-full text-left px-3 py-2 text-sm text-[var(--chat-text-secondary)] hover:bg-[var(--chat-bg-hover)] flex items-center justify-between">
                              <span>{p.name}</span>
                              <span className="text-[var(--chat-accent)] text-xs">R$ {Number(p.price).toFixed(2)}</span>
                            </button>
                          ))}
                        </div>
                      )}
                    </div>
                    <div className="flex items-center gap-1 flex-shrink-0">
                      <button onClick={() => setItems(prev => prev.map((it, i) => i === idx ? { ...it, quantity: Math.max(1, it.quantity - 1) } : it))} className="w-7 h-7 rounded bg-[var(--chat-bg-field)] border border-[var(--chat-border)] flex items-center justify-center text-[var(--chat-text-muted)] hover:text-[var(--chat-text-primary)]">
                        <Minus size={12} />
                      </button>
                      <span className="w-8 text-center text-sm text-[var(--chat-text-primary)]">{item.quantity}</span>
                      <button onClick={() => setItems(prev => prev.map((it, i) => i === idx ? { ...it, quantity: it.quantity + 1 } : it))} className="w-7 h-7 rounded bg-[var(--chat-bg-field)] border border-[var(--chat-border)] flex items-center justify-center text-[var(--chat-text-muted)] hover:text-[var(--chat-text-primary)]">
                        <Plus size={12} />
                      </button>
                    </div>
                    <div className="w-28 flex-shrink-0">
                      <input type="number" step="0.01" min="0" value={item.unit_price || ''} onChange={e => setItems(prev => prev.map((it, i) => i === idx ? { ...it, unit_price: Number(e.target.value) } : it))} placeholder="R$ 0,00" className="w-full px-3 py-2 text-sm bg-[var(--chat-bg-field)] border border-[var(--chat-border)] rounded-lg text-[var(--chat-text-primary)] placeholder-[var(--chat-text-tertiary)] focus:outline-none focus:border-[var(--chat-accent)]" />
                    </div>
                    {items.length > 1 && (
                      <button onClick={() => setItems(prev => prev.filter((_, i) => i !== idx))} className="w-8 h-8 flex items-center justify-center text-[var(--chat-text-tertiary)] hover:text-red-400 flex-shrink-0 mt-0.5"><X size={16} /></button>
                    )}
                  </div>
                )
              })}
            </div>
            <button onClick={() => setItems(prev => [...prev, { product_id: null, product_name: '', quantity: 1, unit_price: 0 }])} className="mt-2 flex items-center gap-1.5 text-sm text-[var(--chat-accent)] hover:text-[var(--chat-accent-hover)]">
              <Plus size={14} /> Adicionar produto
            </button>
          </div>

          {/* Pagamento — Forma e Status como tags coloridas */}
          <div className="space-y-4">
            <div>
              <p className="text-[10px] font-bold uppercase tracking-wider text-[var(--chat-text-muted)] mb-2">
                Forma de Pagamento <span className="text-[var(--chat-text-tertiary)] normal-case font-normal">(selecione até 2)</span>
              </p>
              <div className="flex flex-wrap gap-2">
                {PAYMENT_METHODS.map(m => {
                  const selected = selectedMethods.includes(m.value)
                  return (
                    <button
                      key={m.value}
                      onClick={() => toggleMethod(m.value)}
                      className="flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-bold border transition-all duration-150"
                      style={selected
                        ? { backgroundColor: m.bg, color: m.color, borderColor: m.border, boxShadow: `0 0 0 1px ${m.border}` }
                        : { backgroundColor: 'rgba(255,255,255,0.03)', color: 'var(--chat-text-muted)', borderColor: 'var(--chat-border)' }
                      }
                    >
                      {selected && <Check size={10} weight="bold" />}
                      {m.label}
                    </button>
                  )
                })}
              </div>
              {selectedMethods.length === 2 && (
                <p className="text-[10px] text-[var(--chat-text-muted)] mt-1.5">
                  Pagamento dividido: {selectedMethods.map(m => PAYMENT_METHODS.find(p => p.value === m)?.label).join(' + ')}
                </p>
              )}
            </div>

            <div>
              <p className="text-[10px] font-bold uppercase tracking-wider text-[var(--chat-text-muted)] mb-2">Status do Pagamento</p>
              <div className="flex gap-2">
                {PAYMENT_STATUS.map(s => {
                  const selected = paymentStatus === s.value
                  return (
                    <button
                      key={s.value}
                      onClick={() => setPaymentStatus(s.value)}
                      className="flex items-center gap-1.5 px-4 py-2 rounded-full text-xs font-bold border transition-all duration-150"
                      style={selected
                        ? { backgroundColor: s.bg, color: s.color, borderColor: s.border, boxShadow: `0 0 0 1px ${s.border}` }
                        : { backgroundColor: 'rgba(255,255,255,0.03)', color: 'var(--chat-text-muted)', borderColor: 'var(--chat-border)' }
                      }
                    >
                      {selected && <Check size={10} weight="bold" />}
                      {s.label}
                    </button>
                  )
                })}
              </div>
            </div>
          </div>

          {/* Dados do cliente */}
          <div>
            <p className="text-[10px] font-bold uppercase tracking-wider text-[var(--chat-text-muted)] mb-3">Dados do Cliente</p>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div>
                <label className="text-[10px] text-[var(--chat-text-muted)] font-medium">Nome</label>
                <input value={customerName} onChange={e => setCustomerName(e.target.value)} className="w-full mt-1 px-3 py-2 text-sm bg-[var(--chat-bg-field)] border border-[var(--chat-border)] rounded-lg text-[var(--chat-text-primary)] focus:outline-none focus:border-[var(--chat-accent)]" />
              </div>
              <div>
                <label className="text-[10px] text-[var(--chat-text-muted)] font-medium">Telefone</label>
                <input value={customerPhone} onChange={e => setCustomerPhone(e.target.value)} className="w-full mt-1 px-3 py-2 text-sm bg-[var(--chat-bg-field)] border border-[var(--chat-border)] rounded-lg text-[var(--chat-text-primary)] focus:outline-none focus:border-[var(--chat-accent)]" />
              </div>
              <div>
                <label className="text-[10px] text-[var(--chat-text-muted)] font-medium">E-mail</label>
                <input value={customerEmail} onChange={e => setCustomerEmail(e.target.value)} className="w-full mt-1 px-3 py-2 text-sm bg-[var(--chat-bg-field)] border border-[var(--chat-border)] rounded-lg text-[var(--chat-text-primary)] focus:outline-none focus:border-[var(--chat-accent)]" />
              </div>
              <div>
                <label className="text-[10px] text-[var(--chat-text-muted)] font-medium">CPF</label>
                <input value={cpf} onChange={e => setCpf(maskCpf(e.target.value))} placeholder="000.000.000-00" className="w-full mt-1 px-3 py-2 text-sm bg-[var(--chat-bg-field)] border border-[var(--chat-border)] rounded-lg text-[var(--chat-text-primary)] placeholder-[var(--chat-text-tertiary)] focus:outline-none focus:border-[var(--chat-accent)]" />
              </div>
            </div>
          </div>

          {/* Endereço */}
          <div>
            <p className="text-[10px] font-bold uppercase tracking-wider text-[var(--chat-text-muted)] mb-3 flex items-center gap-1.5">
              <MapPin size={12} /> Endereço de Entrega
            </p>
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
              <div>
                <label className="text-[10px] text-[var(--chat-text-muted)] font-medium">CEP</label>
                <input value={cep} onChange={e => setCep(maskCep(e.target.value))} onBlur={handleCepBlur} placeholder="00000-000" className="w-full mt-1 px-3 py-2 text-sm bg-[var(--chat-bg-field)] border border-[var(--chat-border)] rounded-lg text-[var(--chat-text-primary)] placeholder-[var(--chat-text-tertiary)] focus:outline-none focus:border-[var(--chat-accent)]" />
                {cepLoading && <span className="text-[10px] text-[var(--chat-accent)]">Buscando...</span>}
              </div>
              <div className="col-span-2">
                <label className="text-[10px] text-[var(--chat-text-muted)] font-medium">Endereço</label>
                <input value={address} onChange={e => setAddress(e.target.value)} placeholder="Rua, Av..." className="w-full mt-1 px-3 py-2 text-sm bg-[var(--chat-bg-field)] border border-[var(--chat-border)] rounded-lg text-[var(--chat-text-primary)] placeholder-[var(--chat-text-tertiary)] focus:outline-none focus:border-[var(--chat-accent)]" />
              </div>
              <div>
                <label className="text-[10px] text-[var(--chat-text-muted)] font-medium">Número</label>
                <input value={addressNumber} onChange={e => setAddressNumber(e.target.value)} className="w-full mt-1 px-3 py-2 text-sm bg-[var(--chat-bg-field)] border border-[var(--chat-border)] rounded-lg text-[var(--chat-text-primary)] focus:outline-none focus:border-[var(--chat-accent)]" />
              </div>
              <div className="col-span-2">
                <label className="text-[10px] text-[var(--chat-text-muted)] font-medium">Complemento</label>
                <input value={addressComplement} onChange={e => setAddressComplement(e.target.value)} placeholder="Apto, Bloco..." className="w-full mt-1 px-3 py-2 text-sm bg-[var(--chat-bg-field)] border border-[var(--chat-border)] rounded-lg text-[var(--chat-text-primary)] placeholder-[var(--chat-text-tertiary)] focus:outline-none focus:border-[var(--chat-accent)]" />
              </div>
              <div>
                <label className="text-[10px] text-[var(--chat-text-muted)] font-medium">Bairro</label>
                <input value={neighborhood} onChange={e => setNeighborhood(e.target.value)} className="w-full mt-1 px-3 py-2 text-sm bg-[var(--chat-bg-field)] border border-[var(--chat-border)] rounded-lg text-[var(--chat-text-primary)] focus:outline-none focus:border-[var(--chat-accent)]" />
              </div>
              <div>
                <label className="text-[10px] text-[var(--chat-text-muted)] font-medium">Cidade</label>
                <input value={city} onChange={e => setCity(e.target.value)} className="w-full mt-1 px-3 py-2 text-sm bg-[var(--chat-bg-field)] border border-[var(--chat-border)] rounded-lg text-[var(--chat-text-primary)] focus:outline-none focus:border-[var(--chat-accent)]" />
              </div>
              <div>
                <label className="text-[10px] text-[var(--chat-text-muted)] font-medium">Estado</label>
                <input value={state} onChange={e => setState(e.target.value)} maxLength={2} placeholder="SP" className="w-full mt-1 px-3 py-2 text-sm bg-[var(--chat-bg-field)] border border-[var(--chat-border)] rounded-lg text-[var(--chat-text-primary)] placeholder-[var(--chat-text-tertiary)] focus:outline-none focus:border-[var(--chat-accent)]" />
              </div>
            </div>
          </div>

          {/* Observações */}
          <div>
            <label className="text-[10px] font-bold uppercase tracking-wider text-[var(--chat-text-muted)]">Observações</label>
            <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2} placeholder="Notas internas..." className="w-full mt-2 px-3 py-2 text-sm bg-[var(--chat-bg-field)] border border-[var(--chat-border)] rounded-lg text-[var(--chat-text-primary)] focus:outline-none focus:border-[var(--chat-accent)] placeholder-[var(--chat-text-tertiary)] resize-none" />
          </div>

          {error && <div className="px-4 py-2.5 bg-red-500/10 border border-red-500/30 rounded-lg text-sm text-red-700 dark:text-red-300">{error}</div>}
        </div>

        {/* Footer */}
        <div className="p-5 border-t border-[var(--chat-border)] flex items-center justify-between">
          <div>
            {/* Show selected payment tags */}
            <div className="flex items-center gap-1.5 mb-1">
              {selectedMethods.map(m => {
                const pm = PAYMENT_METHODS.find(p => p.value === m)
                if (!pm) return null
                return (
                  <span key={m} className="text-[9px] font-bold uppercase tracking-wide px-1.5 py-0.5 rounded-full" style={{ backgroundColor: pm.bg, color: pm.color }}>
                    {pm.label}
                  </span>
                )
              })}
              {(() => {
                const ps = PAYMENT_STATUS.find(s => s.value === paymentStatus)
                return ps ? (
                  <span className="text-[9px] font-bold uppercase tracking-wide px-1.5 py-0.5 rounded-full" style={{ backgroundColor: ps.bg, color: ps.color }}>
                    {ps.label}
                  </span>
                ) : null
              })()}
            </div>
            <p className="text-xl font-bold text-[var(--chat-accent)]">
              R$ {totalValue.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}
            </p>
          </div>
          <div className="flex items-center gap-3">
            <button onClick={onClose} className="px-5 py-2 rounded-lg text-sm font-medium text-[var(--chat-text-muted)] hover:text-[var(--chat-text-primary)] transition-colors">Cancelar</button>
            <button onClick={handleSubmit} disabled={saving} className="px-6 py-2 rounded-lg text-sm font-bold bg-[var(--chat-accent)] text-[var(--chat-bg-conversation)] hover:bg-[var(--chat-accent-hover)] disabled:opacity-50 disabled:cursor-wait transition-colors">
              {saving ? 'Salvando...' : 'Confirmar Venda'}
            </button>
          </div>
        </div>
      </div>
    </div>
  )

  return typeof window !== 'undefined' ? ReactDOM.createPortal(modal, document.body) : null
}
