'use client'

/**
 * Os lembretes de uma visita, com "Excluir lembrete" (Pedro, 20/10/2026). Aparece logo depois de agendar (AgendarVisita)
 * e no painel da visita na agenda (VisitasAgendadas). Excluir cancela o lembrete que ainda não saiu; a visita fica.
 */
import { useCallback, useEffect, useState } from 'react'
import { BellSimple, Trash } from '@phosphor-icons/react'

type Lembrete = { id: string; para: string; telefone: string | null; enviar_em: string; estado: string; mensagem: string }

const ESTADO: Record<string, string> = { agendado: 'agendado', enviando: 'saindo agora', enviado: 'enviado', falhou: 'falhou', cancelado: 'excluído' }

function quando(iso: string) {
  return new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', timeZone: 'America/Manaus' })
}

export default function LembretesDaVisita({ visita, compacto }: { visita: number; compacto?: boolean }) {
  const [lista, setLista] = useState<Lembrete[] | null>(null)
  const [erro, setErro] = useState('')
  const [andando, setAndando] = useState<string | null>(null)

  const carregar = useCallback(async () => {
    try {
      const r = await fetch(`/api/parceria/visitas/${visita}/lembretes`)
      const j = await r.json()
      if (!r.ok) throw new Error(j?.error || 'não li os lembretes')
      setLista(j.lembretes || [])
    } catch (e: any) { setErro(e?.message || 'não li os lembretes') }
  }, [visita])
  useEffect(() => { void carregar() }, [carregar])

  const excluir = async (id?: string) => {
    if (!window.confirm(id ? 'Excluir este lembrete? A visita continua na agenda.' : 'Excluir os lembretes desta visita? A visita continua na agenda.')) return
    setAndando(id || 'todos')
    setErro('')
    try {
      const r = await fetch(`/api/parceria/visitas/${visita}/lembretes${id ? `?lembrete=${id}` : ''}`, { method: 'DELETE' })
      const j = await r.json().catch(() => ({}))
      if (!r.ok) throw new Error(j?.error || 'não excluí')
      await carregar()
    } catch (e: any) { setErro(e?.message || 'não excluí') } finally { setAndando(null) }
  }

  if (lista === null && !erro) return null
  const ativos = (lista || []).filter((l) => l.estado === 'agendado')
  return (
    <div className={compacto ? 'mt-2' : ''}>
      {!compacto && <p className="text-[12px] font-semibold uppercase tracking-wider mb-1.5" style={{ color: 'var(--wa-text-2)' }}>Lembretes</p>}
      {erro && <p className="text-[12.5px]" style={{ color: 'var(--wa-tag-tel)' }}>{erro}</p>}
      {lista && !lista.length && <p className="text-[13px]" style={{ color: 'var(--wa-text-2)' }}>Esta visita não tem lembrete.</p>}
      <div className="flex flex-col gap-1.5">
        {(lista || []).map((l) => (
          <div key={l.id} className="flex items-center gap-2 text-[13px] rounded-lg px-2.5 py-1.5"
               style={{ background: 'var(--wa-app)', color: 'var(--wa-text)', opacity: l.estado === 'cancelado' ? 0.55 : 1 }}>
            <BellSimple size={15} style={{ color: '#2563eb', flexShrink: 0 }} />
            <span className="flex-1 min-w-0 truncate" title={l.mensagem}>
              Para <b>{l.para}</b> · {quando(l.enviar_em)} · {ESTADO[l.estado] || l.estado}
            </span>
            {l.estado === 'agendado' && (
              <button type="button" onClick={() => void excluir(l.id)} disabled={!!andando}
                      className="inline-flex items-center gap-1 text-[12.5px] font-semibold disabled:opacity-40" style={{ color: 'var(--wa-tag-tel)' }}>
                <Trash size={13} /> Excluir lembrete
              </button>
            )}
          </div>
        ))}
      </div>
      {ativos.length > 1 && (
        <button type="button" onClick={() => void excluir()} disabled={!!andando}
                className="mt-1.5 text-[12.5px] font-semibold disabled:opacity-40" style={{ color: 'var(--wa-tag-tel)' }}>
          Excluir todos os lembretes desta visita
        </button>
      )}
    </div>
  )
}
