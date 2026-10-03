'use client'

/**
 * O IMÓVEL DA VISITA, PELO CÓDIGO OU PELO NOME (Pedro, 03/10/2026): "nessa parte de
 * código coloca por nome de condomínio também, ao aparecer a gente ver as opções,
 * porque lembrar do código e ir lá ver no site nos toma tempo... e coloca essa mesma
 * função em todas as partes da visita".
 *
 * Um campo só: digita o código, ou um pedaço do nome do condomínio (ou do bairro), e
 * a lista desce; clicou, está escolhido, com o nome ao lado do código para conferir.
 * Código digitado inteiro continua valendo sem clicar em nada, como era antes.
 *
 * A busca mora em src/lib/imovelDaVisita.ts (a mesma fonte do "Enviar imóvel"): os
 * nossos disponíveis vêm primeiro; o resto do acervo vem depois, com a situação
 * escrita ao lado -- nada é escondido de quem agenda à mão.
 *
 * Usado no formulário azul de agendar (card do contato e + da agenda) e no lápis do
 * imóvel, no painel da visita.
 */
import { useEffect, useRef, useState } from 'react'
import { CircleNotch, X } from '@phosphor-icons/react'
import { buscarImoveisDaVisita, imovelPeloCodigo, resumoDoImovel as resumo, type ImovelDaBusca } from '@/lib/imovelDaVisita'

/** O que avisar ao lado do nome: o que não é nosso disponível vem com a situação escrita. */
function Etiquetas({ i }: { i: ImovelDaBusca }) {
  const fora = i.status && i.status !== 'Disponível'
  if (!fora && !i.parceiro) return null
  return (
    <span className="flex-shrink-0 flex gap-1">
      {fora && <span className="wa-marca" style={{ color: 'var(--wa-tag-tel)' }}>{i.status}</span>}
      {i.parceiro && <span className="wa-marca" style={{ color: 'var(--wa-tag-prop)' }}>parceiro</span>}
    </span>
  )
}

export default function EscolherImovelDaVisita({ codigo, aoMudar, estilo, autoFocus }: {
  /** o código que vale agora (o que o formulário manda); vazio = nenhum */
  codigo: string
  aoMudar: (codigo: string) => void
  /** o mesmo estilo dos outros campos de quem usa */
  estilo: React.CSSProperties
  autoFocus?: boolean
}) {
  const [texto, setTexto] = useState(codigo)
  const [escolhido, setEscolhido] = useState<ImovelDaBusca | null>(null)
  const [opcoes, setOpcoes] = useState<ImovelDaBusca[]>([])
  const [aberta, setAberta] = useState(false)
  const [procurando, setProcurando] = useState(false)
  const [ativo, setAtivo] = useState(0)
  /* false enquanto o campo só tem o valor com que abriu (editar uma visita): aí
     procura-se o NOME daquele código, sem abrir lista nenhuma */
  const mexeu = useRef(false)
  const campo = useRef<HTMLInputElement>(null)

  useEffect(() => {
    const q = texto.trim()
    if (escolhido || q.length < 2) { setOpcoes([]); setProcurando(false); return }
    const ctl = new AbortController()
    const t = setTimeout(async () => {
      setProcurando(true)
      try {
        if (!mexeu.current) {
          const dele = await imovelPeloCodigo(q, ctl.signal)
          if (!ctl.signal.aborted && dele) setEscolhido(dele)
          return
        }
        const lista = await buscarImoveisDaVisita(q, ctl.signal)
        if (ctl.signal.aborted) return
        setOpcoes(lista); setAtivo(0); setAberta(true)
      } catch {
        if (!ctl.signal.aborted) setOpcoes([])
      } finally {
        if (!ctl.signal.aborted) setProcurando(false)
      }
    }, mexeu.current ? 280 : 0)
    return () => { clearTimeout(t); ctl.abort() }
  }, [texto, escolhido])

  function pegar(i: ImovelDaBusca) {
    setEscolhido(i); setTexto(i.codigo); setAberta(false); setOpcoes([])
    aoMudar(i.codigo)
  }
  function trocar() {
    mexeu.current = true
    setEscolhido(null); setTexto(''); setOpcoes([])
    aoMudar('')
    requestAnimationFrame(() => campo.current?.focus())
  }
  function digitar(v: string) {
    mexeu.current = true
    setTexto(v)
    // o código inteiro vale sem clicar em nada; nome solto ainda não é imóvel nenhum
    aoMudar(/^\d{1,6}$/.test(v.trim()) ? v.trim() : '')
  }

  if (escolhido) {
    return (
      <div className="flex items-center gap-2 min-h-8 rounded-lg px-2.5 py-1 text-[13.5px]" style={estilo}>
        <span className="flex-1 min-w-0">
          <span className="block truncate"><b>#{escolhido.codigo}</b> {escolhido.nome}</span>
          {resumo(escolhido) && <span className="block truncate text-[12px]" style={{ color: 'var(--wa-text-2)' }}>{resumo(escolhido)}</span>}
        </span>
        <Etiquetas i={escolhido} />
        <button type="button" onClick={trocar} aria-label="Trocar o imóvel" title="Trocar o imóvel" className="flex-shrink-0"><X size={14} /></button>
      </div>
    )
  }

  const q = texto.trim()
  const soNumero = /^\d+$/.test(q)
  return (
    <div>
      <div className="relative">
        <input ref={campo} value={texto} autoFocus={autoFocus}
               onChange={(e) => digitar(e.target.value.slice(0, 60))}
               onFocus={() => { if (opcoes.length) setAberta(true) }}
               onKeyDown={(e) => {
                 if (e.key === 'ArrowDown') { e.preventDefault(); setAberta(true); setAtivo((a) => Math.min(a + 1, Math.max(opcoes.length - 1, 0))) }
                 else if (e.key === 'ArrowUp') { e.preventDefault(); setAtivo((a) => Math.max(a - 1, 0)) }
                 else if (e.key === 'Enter' && aberta && opcoes[ativo]) { e.preventDefault(); pegar(opcoes[ativo]) }
                 else if (e.key === 'Escape' && aberta) { e.stopPropagation(); setAberta(false) }
               }}
               placeholder="código, ou o nome do condomínio" aria-label="Imóvel: código ou nome do condomínio"
               role="combobox" aria-expanded={aberta && opcoes.length > 0} aria-autocomplete="list"
               className="w-full h-8 rounded-lg px-2.5 pr-7 text-[13.5px]" style={estilo} />
        {procurando && <CircleNotch size={14} className="animate-spin absolute right-2 top-2" style={{ color: 'var(--wa-text-2)' }} />}
      </div>
      {aberta && opcoes.length > 0 && (
        <ul role="listbox" className="mt-1 rounded-lg overflow-y-auto wa-rolagem max-h-[232px]" style={estilo}>
          {opcoes.map((i, k) => (
            <li key={i.codigo} role="option" aria-selected={k === ativo}>
              <button type="button" onMouseDown={(e) => e.preventDefault()} onClick={() => pegar(i)} onMouseEnter={() => setAtivo(k)}
                      className="w-full text-left px-2.5 py-1.5 flex items-center gap-2"
                      style={{ borderBottom: '1px solid var(--wa-divider)', background: k === ativo ? 'color-mix(in srgb, #2563eb 14%, transparent)' : undefined }}>
                <span className="flex-1 min-w-0">
                  <span className="block truncate text-[13px]"><b>#{i.codigo}</b> {i.nome}</span>
                  {resumo(i) && <span className="block truncate text-[12px]" style={{ color: 'var(--wa-text-2)' }}>{resumo(i)}</span>}
                </span>
                <Etiquetas i={i} />
              </button>
            </li>
          ))}
        </ul>
      )}
      {mexeu.current && q.length >= 2 && !procurando && aberta && opcoes.length === 0 && (
        <p className="text-[11.5px] mt-1" style={{ color: 'var(--wa-text-2)' }}>
          {soNumero ? 'Não achei esse código na lista: vale o número digitado, e o sistema confere ao salvar.' : 'Nenhum imóvel com esse nome. Tente outro pedaço do nome, o bairro ou o código.'}
        </p>
      )}
    </div>
  )
}
