'use client'

/**
 * TUTORIAIS (Pedro, 29/10/2026): "uma pasta no menu Mais, TUTORIAIS, tipo uma documentação, um campo em cima de
 * pesquisar, e embaixo tutoriais rápidos das funções do CRM ... com prints das funções, onde ir clicando, bem didático
 * mas sem muitos textões".
 *
 * O conteúdo mora em lib/tutoriais.ts; os prints em public/tutoriais/. ?t=<id> abre um tutorial direto (é o link que a
 * busca do alto usa), ?q= já chega pesquisado.
 */
import { Suspense, useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { useRouter, useSearchParams } from 'next/navigation'
import { BookOpenText, MagnifyingGlass, X, ArrowLeft, ArrowRight, MagnifyingGlassPlus } from '@phosphor-icons/react'
import { GRUPOS_DE_TUTORIAL, TUTORIAIS, buscarTutoriais, type Tutorial } from '@/lib/tutoriais'

function Passos({ t, aoVoltar }: { t: Tutorial; aoVoltar: () => void }) {
  const [ampliada, setAmpliada] = useState<string | null>(null)
  useEffect(() => {
    if (!ampliada) return
    const esc = (e: KeyboardEvent) => { if (e.key === 'Escape') setAmpliada(null) }
    window.addEventListener('keydown', esc)
    return () => window.removeEventListener('keydown', esc)
  }, [ampliada])

  return (
    <div>
      <button type="button" onClick={aoVoltar} className="flex items-center gap-1.5 text-sm text-muted hover:text-ink">
        <ArrowLeft size={16} /> Todos os tutoriais
      </button>
      <div className="mt-3 flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="text-xs font-semibold uppercase tracking-wide text-accent">{t.grupo}</div>
          <h2 className="text-xl md:text-2xl font-bold text-ink">{t.titulo}</h2>
          <p className="text-sm text-muted mt-0.5">{t.resumo}</p>
        </div>
        {t.onde && (
          <Link href={t.onde} className="flex items-center gap-1.5 h-9 px-3 rounded-lg bg-accent text-white text-sm font-semibold hover:bg-accent-2">
            Ir para lá <ArrowRight size={16} />
          </Link>
        )}
      </div>

      <ol className="mt-5 space-y-6">
        {t.passos.map((p, i) => (
          <li key={i} className="flex gap-3">
            <span className="flex-shrink-0 w-7 h-7 rounded-full bg-accent text-white text-sm font-bold flex items-center justify-center">{i + 1}</span>
            <div className="min-w-0 flex-1">
              <p className="text-[15px] text-ink leading-7">{p.texto}</p>
              {p.foto && (
                <button type="button" onClick={() => setAmpliada(p.foto!)} title="Ampliar"
                        className="group relative mt-2 block w-full rounded-xl overflow-hidden border border-line bg-black/40">
                  <img src={`/tutoriais/${p.foto}.webp`} alt={p.texto} loading="lazy" className="block w-full h-auto" />
                  <span className="absolute right-2 bottom-2 w-8 h-8 rounded-full bg-black/60 text-white flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity">
                    <MagnifyingGlassPlus size={18} />
                  </span>
                </button>
              )}
              {p.itens && (
                <ul className="mt-2 space-y-1.5">
                  {p.itens.map((item, j) => (
                    <li key={j} className="flex gap-2 text-sm text-ink">
                      <span className="flex-shrink-0 w-5 h-5 mt-0.5 rounded-full bg-orange-500 text-white text-[11px] font-bold flex items-center justify-center">{j + 1}</span>
                      <span>{item}</span>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </li>
        ))}
      </ol>

      {ampliada && (
        <div className="fixed inset-0 z-[80] bg-black/85 flex items-center justify-center p-4" onClick={() => setAmpliada(null)}>
          <button type="button" aria-label="Fechar" className="absolute top-4 right-4 w-10 h-10 rounded-full bg-white/10 text-white flex items-center justify-center">
            <X size={22} />
          </button>
          <img src={`/tutoriais/${ampliada}.webp`} alt="" className="max-w-full max-h-full rounded-lg" />
        </div>
      )}
    </div>
  )
}

function Tutoriais() {
  const router = useRouter()
  const params = useSearchParams()
  const [busca, setBusca] = useState(params.get('q') || '')
  const aberto = TUTORIAIS.find((t) => t.id === params.get('t')) || null
  const achados = useMemo(() => buscarTutoriais(busca), [busca])
  const buscando = busca.trim().length >= 2

  const abrir = (id: string | null) => {
    const q = new URLSearchParams()
    if (id) q.set('t', id)
    if (!id && busca.trim()) q.set('q', busca.trim())
    router.push(`/tutoriais${q.toString() ? `?${q}` : ''}`)
    window.scrollTo(0, 0)
  }

  const cartao = (t: Tutorial) => (
    <button key={t.id} type="button" onClick={() => abrir(t.id)}
            className="panel text-left rounded-xl border border-line p-3 hover:border-accent/60 transition-colors flex gap-3">
      {t.passos.find((p) => p.foto) && (
        <img src={`/tutoriais/${t.passos.find((p) => p.foto)!.foto}.webp`} alt="" loading="lazy"
             className="w-24 h-16 flex-shrink-0 rounded-lg object-cover object-left-top border border-line" />
      )}
      <div className="min-w-0">
        <div className="font-semibold text-ink leading-5">{t.titulo}</div>
        <div className="text-xs text-muted mt-1">{t.resumo}</div>
        <div className="text-[11px] text-muted mt-1">{t.passos.length} passo{t.passos.length > 1 ? 's' : ''}</div>
      </div>
    </button>
  )

  return (
    <div className="p-4 md:p-6 max-w-[920px] mx-auto">
      {aberto ? (
        <Passos t={aberto} aoVoltar={() => abrir(null)} />
      ) : (
        <>
          <h1 className="text-xl md:text-2xl font-bold text-ink flex items-center gap-2">
            <BookOpenText size={24} weight="fill" className="text-accent" /> Tutoriais
          </h1>
          <p className="text-sm text-muted mt-1">Como usar cada função do CRM, em poucos passos.</p>

          <label className="mt-4 flex items-center gap-2 h-11 px-3 rounded-xl border border-line panel focus-within:border-accent/60">
            <MagnifyingGlass size={18} className="text-muted" />
            <input autoFocus value={busca} onChange={(e) => setBusca(e.target.value)}
                   placeholder="O que você quer fazer? Ex.: enviar imóvel, parar a Nay, etiqueta"
                   aria-label="Pesquisar nos tutoriais"
                   className="flex-1 bg-transparent outline-none text-[15px] text-ink" />
            {busca && <button type="button" onClick={() => setBusca('')} aria-label="Limpar"><X size={16} className="text-muted" /></button>}
          </label>

          {buscando ? (
            achados.length ? (
              <div className="mt-5 grid sm:grid-cols-2 gap-3">{achados.map(cartao)}</div>
            ) : (
              <div className="mt-8 text-center text-sm text-muted">Nada com “{busca.trim()}”. Tente outra palavra.</div>
            )
          ) : (
            GRUPOS_DE_TUTORIAL.map((g) => {
              const doGrupo = TUTORIAIS.filter((t) => t.grupo === g)
              if (!doGrupo.length) return null
              return (
                <section key={g} className="mt-6">
                  <h2 className="text-xs font-semibold uppercase tracking-wide text-muted mb-2">{g}</h2>
                  <div className="grid sm:grid-cols-2 gap-3">{doGrupo.map(cartao)}</div>
                </section>
              )
            })
          )}
        </>
      )}
    </div>
  )
}

export default function PaginaTutoriais() {
  return <Suspense fallback={null}><Tutoriais /></Suspense>
}
