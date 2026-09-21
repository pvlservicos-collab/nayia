'use client'

import { useState, useEffect, useCallback } from 'react'
import { X, MapPin, WhatsappLogo, IdentificationCard, EnvelopeSimple, Phone, PencilSimple, Motorcycle } from '@phosphor-icons/react'
import { buildDeliveryWhatsAppLink } from './whatsapp'
import { PAYMENT_STATUS_META, DELIVERY_STATUS_META, PAYMENT_METHOD_META, TONE_STYLES, StatusTone } from '@/lib/orderStatus'

function maskCep(v: string) {
  return v.replace(/\D/g, '').slice(0, 8).replace(/(\d{5})(\d)/, '$1-$2')
}

const TONE_CLASSES: Record<StatusTone, string> = {
  warning: 'text-yellow-400 bg-yellow-400/10 border-yellow-400/30',
  success: 'text-green-400 bg-green-400/10 border-green-400/30',
  danger: 'text-red-400 bg-red-400/10 border-red-400/30',
  info: 'text-accent-2 bg-accent/10 border-accent/30',
}

export interface OrderDetailItem {
  id: string
  product_name: string
  quantity: number
  unit_price: string
}

export interface OrderDetail {
  id: string
  customer_name: string | null
  customer_phone: string | null
  customer_email: string | null
  customer_cpf: string | null
  customer_cep: string | null
  customer_address: string | null
  customer_address_number: string | null
  customer_address_complement: string | null
  customer_neighborhood: string | null
  customer_city: string | null
  customer_state: string | null
  payment_method: string
  payment_status: string
  delivery_status: string
  total_value: string
  created_at: string
  delivered_at: string | null
  cash_settled: boolean
  cash_settled_at: string | null
  items: OrderDetailItem[]
}

const PAYMENT_METHOD_LABELS: Record<string, string> = Object.fromEntries(
  Object.entries(PAYMENT_METHOD_META).map(([value, meta]) => [value, meta.label])
)

function formatCurrency(value: string | number) {
  return Number(value).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
}

function formatDateTime(iso: string) {
  return new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })
}

function formatAddress(o: OrderDetail): string | null {
  const parts = [
    o.customer_address ? `${o.customer_address}${o.customer_address_number ? `, ${o.customer_address_number}` : ''}` : null,
    o.customer_address_complement,
    o.customer_neighborhood,
    o.customer_city && o.customer_state ? `${o.customer_city}/${o.customer_state}` : (o.customer_city || o.customer_state),
    o.customer_cep ? `CEP ${o.customer_cep}` : null,
  ].filter(Boolean)
  return parts.length > 0 ? parts.join(' — ') : null
}

interface StatusHistoryEvent {
  id: string
  field: 'payment_status' | 'delivery_status'
  from_status: string | null
  to_status: string
  changed_at: string
  actor_name: string | null
}

function statusLabel(field: StatusHistoryEvent['field'], value: string): string {
  const meta = field === 'payment_status' ? PAYMENT_STATUS_META[value] : DELIVERY_STATUS_META[value]
  return meta?.label || value
}

function statusTone(field: StatusHistoryEvent['field'], value: string): StatusTone {
  const meta = field === 'payment_status' ? PAYMENT_STATUS_META[value] : DELIVERY_STATUS_META[value]
  return meta?.tone || 'warning'
}

interface OrderDetailModalProps {
  order: OrderDetail
  onClose: () => void
  onUpdate?: (orderId: string, updates: Partial<Pick<OrderDetail, 'payment_status' | 'delivery_status' | 'delivered_at'>>) => void
  /** Modo vendedor (Chat): entrega e repasse de dinheiro ficam só-leitura —
   * quem mexe nisso é a Logística, pra não bagunçar o trabalho do motoboy sem querer. */
  sellerView?: boolean
}

export default function OrderDetailModal({ order: initialOrder, onClose, onUpdate, sellerView }: OrderDetailModalProps) {
  const [order, setOrder] = useState(initialOrder)
  const [saving, setSaving] = useState(false)
  const [history, setHistory] = useState<StatusHistoryEvent[]>([])
  const [historyLoading, setHistoryLoading] = useState(true)
  const address = formatAddress(order)
  const whatsappLink = buildDeliveryWhatsAppLink(order)

  const [editingAddress, setEditingAddress] = useState(false)
  const [savingAddress, setSavingAddress] = useState(false)
  const [addrCep, setAddrCep] = useState(order.customer_cep || '')
  const [addrAddress, setAddrAddress] = useState(order.customer_address || '')
  const [addrNumber, setAddrNumber] = useState(order.customer_address_number || '')
  const [addrComplement, setAddrComplement] = useState(order.customer_address_complement || '')
  const [addrNeighborhood, setAddrNeighborhood] = useState(order.customer_neighborhood || '')
  const [addrCity, setAddrCity] = useState(order.customer_city || '')
  const [addrState, setAddrState] = useState(order.customer_state || '')
  const [cepLoading, setCepLoading] = useState(false)
  const [settlingCash, setSettlingCash] = useState(false)

  const handleCepBlur = async () => {
    const cleanCep = addrCep.replace(/\D/g, '')
    if (cleanCep.length !== 8) return
    setCepLoading(true)
    try {
      const res = await fetch(`https://viacep.com.br/ws/${cleanCep}/json/`)
      const data = await res.json()
      if (!data.erro) {
        setAddrAddress(data.logradouro || '')
        setAddrNeighborhood(data.bairro || '')
        setAddrCity(data.localidade || '')
        setAddrState(data.uf || '')
      }
    } catch {}
    setCepLoading(false)
  }

  const handleSaveAddress = async () => {
    setSavingAddress(true)
    try {
      const res = await fetch(`/api/orders/${order.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          customer_cep: addrCep.replace(/\D/g, '') || null,
          customer_address: addrAddress || null,
          customer_address_number: addrNumber || null,
          customer_address_complement: addrComplement || null,
          customer_neighborhood: addrNeighborhood || null,
          customer_city: addrCity || null,
          customer_state: addrState || null,
        }),
      })
      if (res.ok) {
        const { data } = await res.json()
        setOrder(prev => ({
          ...prev,
          customer_cep: data.customer_cep,
          customer_address: data.customer_address,
          customer_address_number: data.customer_address_number,
          customer_address_complement: data.customer_address_complement,
          customer_neighborhood: data.customer_neighborhood,
          customer_city: data.customer_city,
          customer_state: data.customer_state,
        }))
        setEditingAddress(false)
      }
    } finally {
      setSavingAddress(false)
    }
  }

  const handleMarkCashSettled = async () => {
    setSettlingCash(true)
    try {
      const res = await fetch(`/api/orders/${order.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ cash_settled: true }),
      })
      if (res.ok) {
        const { data } = await res.json()
        setOrder(prev => ({ ...prev, cash_settled: data.cash_settled, cash_settled_at: data.cash_settled_at }))
      }
    } finally {
      setSettlingCash(false)
    }
  }

  const fetchHistory = useCallback(async () => {
    setHistoryLoading(true)
    try {
      const res = await fetch(`/api/orders/${order.id}/history`)
      if (res.ok) {
        const { data } = await res.json()
        setHistory(data || [])
      }
    } finally {
      setHistoryLoading(false)
    }
  }, [order.id])

  useEffect(() => { fetchHistory() }, [fetchHistory])

  const handleStatusChange = async (field: 'payment_status' | 'delivery_status', value: string) => {
    setSaving(true)
    try {
      const res = await fetch(`/api/orders/${order.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ [field]: value }),
      })
      if (res.ok) {
        const { data } = await res.json()
        const updates = { [field]: value, ...(field === 'delivery_status' ? { delivered_at: data.delivered_at } : {}) }
        setOrder(prev => ({ ...prev, ...updates }))
        onUpdate?.(order.id, updates)
        fetchHistory()
      }
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4" style={{ backgroundColor: 'rgba(0,0,0,0.5)' }}>
      <div className="bg-panel border border-line rounded-2xl w-full max-w-lg max-h-[90vh] flex flex-col shadow-2xl">
        <div className="flex items-center justify-between p-5 border-b border-line">
          <div>
            <h2 className="text-lg font-bold text-ink">{order.customer_name || 'Cliente'}</h2>
            <p className="text-xs text-muted">Pedido de {formatDateTime(order.created_at)}</p>
          </div>
          <button onClick={onClose} className="text-muted hover:text-muted transition-colors"><X size={20} /></button>
        </div>

        <div className="flex-1 overflow-y-auto p-5 space-y-5">
          {/* Contato */}
          <div className="space-y-2">
            <p className="text-[10px] font-bold uppercase tracking-wider text-muted">Contato</p>
            <div className="flex items-center gap-2 text-sm text-muted">
              <Phone size={14} className="text-muted flex-shrink-0" />
              {order.customer_phone || '—'}
            </div>
            {order.customer_email && (
              <div className="flex items-center gap-2 text-sm text-muted">
                <EnvelopeSimple size={14} className="text-muted flex-shrink-0" />
                {order.customer_email}
              </div>
            )}
            {order.customer_cpf && (
              <div className="flex items-center gap-2 text-sm text-muted">
                <IdentificationCard size={14} className="text-muted flex-shrink-0" />
                {order.customer_cpf}
              </div>
            )}
          </div>

          {/* Endereço */}
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <p className="text-[10px] font-bold uppercase tracking-wider text-muted flex items-center gap-1.5">
                <MapPin size={12} /> Endereço de entrega
              </p>
              {!editingAddress && (
                <button onClick={() => setEditingAddress(true)} className="flex items-center gap-1 text-xs font-medium text-accent-2 hover:text-accent-2">
                  <PencilSimple size={12} /> Editar
                </button>
              )}
            </div>
            {!editingAddress ? (
              <p className="text-sm text-muted">{address || 'Endereço não informado'}</p>
            ) : (
              <div className="space-y-2">
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
                  <div>
                    <label className="text-[10px] text-muted font-medium">CEP</label>
                    <input value={addrCep} onChange={e => setAddrCep(maskCep(e.target.value))} onBlur={handleCepBlur} placeholder="00000-000" className="w-full mt-1 px-2.5 py-1.5 text-sm border border-line rounded-lg focus:outline-none focus:border-accent" />
                    {cepLoading && <span className="text-[10px] text-accent-2">Buscando...</span>}
                  </div>
                  <div className="sm:col-span-2">
                    <label className="text-[10px] text-muted font-medium">Endereço</label>
                    <input value={addrAddress} onChange={e => setAddrAddress(e.target.value)} placeholder="Rua, Av..." className="w-full mt-1 px-2.5 py-1.5 text-sm border border-line rounded-lg focus:outline-none focus:border-accent" />
                  </div>
                  <div>
                    <label className="text-[10px] text-muted font-medium">Número</label>
                    <input value={addrNumber} onChange={e => setAddrNumber(e.target.value)} className="w-full mt-1 px-2.5 py-1.5 text-sm border border-line rounded-lg focus:outline-none focus:border-accent" />
                  </div>
                  <div className="sm:col-span-2">
                    <label className="text-[10px] text-muted font-medium">Complemento</label>
                    <input value={addrComplement} onChange={e => setAddrComplement(e.target.value)} placeholder="Apto, Bloco..." className="w-full mt-1 px-2.5 py-1.5 text-sm border border-line rounded-lg focus:outline-none focus:border-accent" />
                  </div>
                  <div>
                    <label className="text-[10px] text-muted font-medium">Bairro</label>
                    <input value={addrNeighborhood} onChange={e => setAddrNeighborhood(e.target.value)} className="w-full mt-1 px-2.5 py-1.5 text-sm border border-line rounded-lg focus:outline-none focus:border-accent" />
                  </div>
                  <div>
                    <label className="text-[10px] text-muted font-medium">Cidade</label>
                    <input value={addrCity} onChange={e => setAddrCity(e.target.value)} className="w-full mt-1 px-2.5 py-1.5 text-sm border border-line rounded-lg focus:outline-none focus:border-accent" />
                  </div>
                  <div>
                    <label className="text-[10px] text-muted font-medium">Estado</label>
                    <input value={addrState} onChange={e => setAddrState(e.target.value)} maxLength={2} placeholder="SP" className="w-full mt-1 px-2.5 py-1.5 text-sm border border-line rounded-lg focus:outline-none focus:border-accent" />
                  </div>
                </div>
                <div className="flex items-center gap-2 pt-1">
                  <button onClick={handleSaveAddress} disabled={savingAddress} className="px-3 py-1.5 bg-accent text-white rounded-lg text-xs font-medium hover:bg-accent-2 disabled:opacity-50">
                    {savingAddress ? 'Salvando...' : 'Salvar'}
                  </button>
                  <button onClick={() => setEditingAddress(false)} className="px-3 py-1.5 text-xs font-medium text-muted hover:text-muted">
                    Cancelar
                  </button>
                </div>
              </div>
            )}
          </div>

          {/* Itens */}
          <div className="space-y-2">
            <p className="text-[10px] font-bold uppercase tracking-wider text-muted">Itens do pedido</p>
            <div className="divide-y divide-line border border-line rounded-lg overflow-hidden">
              {order.items.map(item => (
                <div key={item.id} className="flex items-center justify-between px-3 py-2 text-sm">
                  <span className="text-muted">{item.product_name} {item.quantity > 1 ? `x${item.quantity}` : ''}</span>
                  <span className="font-medium text-ink">{formatCurrency(Number(item.unit_price) * item.quantity)}</span>
                </div>
              ))}
            </div>
            <div className="flex items-center justify-between px-1 pt-1">
              <span className="text-sm font-semibold text-ink">Total</span>
              <span className="text-base font-bold text-ink">{formatCurrency(order.total_value)}</span>
            </div>
          </div>

          {/* Status */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-sm">
            <div>
              <p className="text-[10px] font-bold uppercase tracking-wider text-muted mb-1">
                Pagamento <span className="normal-case font-normal">({PAYMENT_METHOD_LABELS[order.payment_method] || order.payment_method})</span>
              </p>
              <select
                value={order.payment_status}
                disabled={saving}
                onChange={e => handleStatusChange('payment_status', e.target.value)}
                className={`text-xs font-medium px-2 py-1 rounded-full border bg-transparent focus:outline-none cursor-pointer ${TONE_CLASSES[PAYMENT_STATUS_META[order.payment_status]?.tone || 'warning']}`}
              >
                {Object.entries(PAYMENT_STATUS_META).map(([val, meta]) => (
                  <option key={val} value={val} className="bg-panel text-muted">{meta.label}</option>
                ))}
              </select>
            </div>
            <div>
              <p className="text-[10px] font-bold uppercase tracking-wider text-muted mb-1">Entrega</p>
              {sellerView ? (
                <span
                  title="Status de entrega — só pode ser alterado na Logística"
                  className={`inline-block text-xs font-medium px-2 py-1 rounded-full border ${TONE_CLASSES[DELIVERY_STATUS_META[order.delivery_status]?.tone || 'warning']}`}
                >
                  {DELIVERY_STATUS_META[order.delivery_status]?.label || order.delivery_status}
                </span>
              ) : (
                <select
                  value={order.delivery_status}
                  disabled={saving}
                  onChange={e => handleStatusChange('delivery_status', e.target.value)}
                  className={`text-xs font-medium px-2 py-1 rounded-full border bg-transparent focus:outline-none cursor-pointer ${TONE_CLASSES[DELIVERY_STATUS_META[order.delivery_status]?.tone || 'warning']}`}
                >
                  {Object.entries(DELIVERY_STATUS_META).map(([val, meta]) => (
                    <option key={val} value={val} className="bg-panel text-muted">{meta.label}</option>
                  ))}
                </select>
              )}
              {order.delivered_at && (
                <p className="text-[10px] text-muted mt-1">Entregue em {formatDateTime(order.delivered_at)}</p>
              )}
            </div>
          </div>

          {/* Repasse de dinheiro — só relevante pra pedidos pagos em espécie, que o
              motoboy recebe fisicamente na entrega antes de repassar pra empresa */}
          {order.payment_method === 'dinheiro' && order.payment_status === 'paid' && (
            <div className="flex items-center justify-between bg-orange-50 border border-orange-100 rounded-lg px-3 py-2.5">
              <div className="flex items-center gap-2">
                <Motorcycle size={16} className={order.cash_settled ? 'text-green-600' : 'text-orange-500'} />
                <span className="text-sm text-muted">
                  {order.cash_settled ? 'Dinheiro repassado' : 'Aguardando repasse do motoboy'}
                </span>
              </div>
              {!order.cash_settled && !sellerView && (
                <button onClick={handleMarkCashSettled} disabled={settlingCash} className="text-xs font-medium text-green-600 hover:text-green-700 disabled:opacity-50">
                  {settlingCash ? 'Salvando...' : 'Marcar repassado'}
                </button>
              )}
            </div>
          )}

          {/* Histórico de status — data/hora de cada mudança, tipo rastreamento */}
          <div className="space-y-2">
            <p className="text-[10px] font-bold uppercase tracking-wider text-muted">Histórico</p>
            {historyLoading ? (
              <p className="text-xs text-muted">Carregando...</p>
            ) : history.length === 0 ? (
              <p className="text-xs text-muted">Nenhum evento registrado.</p>
            ) : (
              <div className="space-y-2.5">
                {history.map(event => (
                  <div key={event.id} className="flex items-start gap-2.5">
                    <span
                      className="w-2 h-2 rounded-full flex-shrink-0 mt-1"
                      style={{ backgroundColor: TONE_STYLES[statusTone(event.field, event.to_status)].color }}
                    />
                    <div className="min-w-0">
                      <p className="text-xs text-muted">
                        {event.field === 'payment_status' ? 'Pagamento' : 'Entrega'}: <span className="font-semibold">{statusLabel(event.field, event.to_status)}</span>
                      </p>
                      <p className="text-[10px] text-muted">
                        {formatDateTime(event.changed_at)}{event.actor_name ? ` · ${event.actor_name}` : ' · Sistema'}
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>

        <div className="p-5 border-t border-line">
          {whatsappLink ? (
            <a
              href={whatsappLink}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center justify-center gap-2 w-full px-4 py-2.5 bg-green-600 text-white rounded-lg text-sm font-medium hover:bg-green-700 transition-colors"
            >
              <WhatsappLogo size={18} weight="fill" />
              Avisar cliente no WhatsApp
            </a>
          ) : (
            <p className="text-xs text-muted text-center">Sem telefone cadastrado para avisar o cliente</p>
          )}
        </div>
      </div>
    </div>
  )
}
