'use client'

/**
 * GUIA DE ATENDIMENTO (Pedro, 31/10/2026): "analise todo atendimento e cria um documento como regras do Tel, um documento
 * de inteligência ... focado em ser um guia de atendimento para aumentar nossa conversão, e analise os imóveis que tiveram
 * a maior visita e veja os componentes das conversas ... salve isso em um menu do CRM lá dentro do +".
 *
 * O conteúdo mora em lib/guiaDeAtendimento.ts (a leitura das conversas de 10/09 a 31/10). ?s=<seção> abre numa seção,
 * ?q= já chega pesquisado.
 */
import { Suspense, useMemo, useState } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { Lightbulb, MagnifyingGlass, X, Quotes } from '@phosphor-icons/react'
import { DATA_DA_LEITURA, FONTE_DA_LEITURA, MAIS_VISITADOS, NUMEROS, SECOES, buscarNoGuia, type Regra } from '@/lib/guiaDeAtendimento'

function CartaoDeRegra({ r }: { r: Regra }) {
  return (
    <div className="panel rounded-xl border border-line p-4">
      <div className="font-semibold text-ink leading-6">{r.titulo}</div>
      {r.quando && <p className="text-sm text-muted mt-1"><span className="font-semibold text-ink">Quando:</span> {r.quando}</p>}
      <p className="text-[15px] text-ink mt-1 leading-6"><span className="font-semibold text-accent">Faça:</span> {r.faca}</p>
      {r.exemplo && (
        <p className="mt-2 flex gap-2 text-sm text-ink bg-accent/10 rounded-lg px-3 py-2">
          <Quotes size={16} weight="fill" className="flex-shrink-0 mt-0.5 text-accent" /> <span>{r.exemplo}</span>
        </p>
      )}
      {r.por && <p className="text-xs text-muted mt-2">Por quê: {r.por}</p>}
    </div>
  )
}

function TabelaDosMaisVisitados() {
  return (
    <div className="overflow-x-auto rounded-xl border border-line">
      <table className="w-full text-sm">
        <thead>
          <tr className="text-left text-xs uppercase tracking-wide text-muted border-b border-line">
            <th className="px-3 py-2">Imóvel</th><th className="px-3 py-2">Bairro</th><th className="px-3 py-2">Valor</th>
            <th className="px-3 py-2 text-right">Visitas</th><th className="px-3 py-2 text-right">Fechou</th><th className="px-3 py-2">Por que puxa visita</th>
          </tr>
        </thead>
        <tbody>
          {MAIS_VISITADOS.map((m) => (
            <tr key={m.codigo} className="border-b border-line last:border-0 align-top">
              <td className="px-3 py-2 text-ink"><div className="font-semibold">{m.nome}</div><div className="text-xs text-muted">#{m.codigo} · {m.ficha}</div></td>
              <td className="px-3 py-2 text-ink whitespace-nowrap">{m.bairro}</td>
              <td className="px-3 py-2 text-ink whitespace-nowrap">{m.valor}</td>
              <td className="px-3 py-2 text-ink text-right">{m.visitas}</td>
              <td className="px-3 py-2 text-ink text-right">{m.fechamentos || '–'}</td>
              <td className="px-3 py-2 text-muted min-w-[220px]">{m.porque}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function Guia() {
  const router = useRouter()
  const params = useSearchParams()
  const [busca, setBusca] = useState(params.get('q') || '')
  const [secao, setSecao] = useState(params.get('s') || SECOES[0].id)
  const achados = useMemo(() => buscarNoGuia(busca), [busca])
  const buscando = busca.trim().length >= 2
  const aberta = SECOES.find((s) => s.id === secao) || SECOES[0]

  const escolher = (id: string) => {
    setSecao(id)
    router.replace(`/guia-de-atendimento?s=${id}`, { scroll: false })
  }

  return (
    <div className="p-4 md:p-6 max-w-[1040px] mx-auto">
      <h1 className="text-xl md:text-2xl font-bold text-ink flex items-center gap-2">
        <Lightbulb size={24} weight="fill" className="text-accent" /> Guia de atendimento
      </h1>
      <p className="text-sm text-muted mt-1">
        As regras do Tel e o que faz a conversa virar visita e negócio. Leitura de {DATA_DA_LEITURA}: {FONTE_DA_LEITURA}
      </p>

      <div className="mt-4 grid grid-cols-2 md:grid-cols-4 gap-3">
        {NUMEROS.map((n) => (
          <div key={n.rotulo} className="panel rounded-xl border border-line p-3">
            <div className="text-2xl font-bold text-ink">{n.valor}</div>
            <div className="text-sm font-semibold text-ink leading-5">{n.rotulo}</div>
            <div className="text-xs text-muted mt-0.5">{n.detalhe}</div>
          </div>
        ))}
      </div>

      <label className="mt-5 flex items-center gap-2 h-11 px-3 rounded-xl border border-line panel focus-within:border-accent/60">
        <MagnifyingGlass size={18} className="text-muted" />
        <input value={busca} onChange={(e) => setBusca(e.target.value)}
               placeholder="Pesquisar: pet, andar, condomínio novo, caução, negociar valor, demora"
               aria-label="Pesquisar no guia" className="flex-1 bg-transparent outline-none text-[15px] text-ink" />
        {busca && <button type="button" onClick={() => setBusca('')} aria-label="Limpar"><X size={16} className="text-muted" /></button>}
      </label>

      {buscando ? (
        achados.length ? (
          <div className="mt-5 space-y-5">
            {achados.map(({ secao: s, regras }) => (
              <section key={s.id}>
                <h2 className="text-xs font-semibold uppercase tracking-wide text-muted mb-2">{s.titulo}</h2>
                <div className="grid md:grid-cols-2 gap-3">{regras.map((r) => <CartaoDeRegra key={r.titulo} r={r} />)}</div>
              </section>
            ))}
          </div>
        ) : (
          <div className="mt-8 text-center text-sm text-muted">Nada com “{busca.trim()}”. Tente outra palavra.</div>
        )
      ) : (
        <>
          <div className="mt-5 flex flex-wrap gap-2">
            {SECOES.map((s) => (
              <button key={s.id} type="button" onClick={() => escolher(s.id)}
                      className={`h-9 px-3 rounded-full border text-sm font-semibold transition-colors ${s.id === aberta.id
                        ? 'bg-accent border-accent text-white' : 'border-line text-ink hover:border-accent/60'}`}>
                {s.titulo}
              </button>
            ))}
          </div>
          <section className="mt-5">
            <h2 className="text-lg font-bold text-ink">{aberta.titulo}</h2>
            <p className="text-sm text-muted mt-0.5">{aberta.resumo}</p>
            {aberta.id === 'mais-visitados' && <div className="mt-4"><TabelaDosMaisVisitados /></div>}
            <div className="mt-4 grid md:grid-cols-2 gap-3">{aberta.regras.map((r) => <CartaoDeRegra key={r.titulo} r={r} />)}</div>
          </section>
        </>
      )}
    </div>
  )
}

export default function PaginaGuiaDeAtendimento() {
  return <Suspense fallback={null}><Guia /></Suspense>
}
