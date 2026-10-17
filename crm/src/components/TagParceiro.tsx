/**
 * A ETIQUETA DO IMÓVEL DE PARCEIRO (400, Pedro 17/10/2026: "que fique sempre claro que esses são de parceiros ... deixe
 * uma tag de cor diferente"). A mesma do admin do site: azul-petróleo sólido, cor que nenhuma outra etiqueta usa.
 * Regra que ela lembra: nunca vai a corretor (número Parceria); vai só a cliente final do número de captação (OLX).
 */
export default function TagParceiro({ className = '' }: { className?: string }) {
  return (
    <span
      className={`inline-flex items-center gap-1 rounded-full px-2 py-[1px] align-middle text-[10px] font-bold uppercase tracking-wider text-white ${className}`}
      style={{ background: '#0e7490' }}
      title="Imóvel de parceiro: nunca vai a corretor (número Parceria); só a cliente final do número de captação (OLX)"
    >
      ⇄ Parceiro
    </span>
  )
}
