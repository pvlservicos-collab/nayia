interface DeliveryOrder {
  customer_name: string | null
  customer_phone: string | null
  total_value: string
  items: { product_name: string; quantity: number }[]
}

/**
 * Monta o link wa.me com uma mensagem pronta pro motoboy avisar que o pedido está a caminho.
 * Retorna null se o pedido não tem telefone de contato.
 */
export function buildDeliveryWhatsAppLink(order: DeliveryOrder): string | null {
  if (!order.customer_phone) return null
  let digits = order.customer_phone.replace(/\D/g, '')
  if (!digits) return null
  if (!digits.startsWith('55')) digits = '55' + digits

  const name = order.customer_name?.trim() || 'Cliente'
  const itemsList = order.items
    .map(i => `- ${i.product_name}${i.quantity > 1 ? ` x${i.quantity}` : ''}`)
    .join('\n')
  const total = Number(order.total_value).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })

  const message = `Olá ${name}! Aqui é o motoboy da Natura Belas 🛵\nSeu pedido está a caminho:\n${itemsList}\nTotal: ${total}`

  return `https://wa.me/${digits}?text=${encodeURIComponent(message)}`
}
