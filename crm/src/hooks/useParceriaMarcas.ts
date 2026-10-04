'use client'

/**
 * As marcas da Nay para as conversas da Parceria (proprietário, corretor,
 * visita aberta, o Tel com a conversa) -- ver /api/parceria/marcas.
 *
 * Uma cópia só para a tela inteira: a lista (filtros e marcas de cada linha)
 * e o card do lado leem daqui, e a busca acontece uma vez por minuto (e ao
 * voltar para a aba), não uma por componente.
 *
 * 04/10: a primeira leitura leva a cópia que o servidor tiver (a tela abre já);
 * se ela veio vencida, e nas leituras de fundo, a tela ESPERA a conta nova
 * (`?esperar=1`). Antes ela mostrava sempre a conta da leitura anterior, e a
 * conversa que mudava de dono entrava na aba 1 a 2 minutos depois.
 */
import { useEffect, useState } from 'react'
import type { EstadoDaNay, MarcaDaNay } from '@/lib/tiposNay'

type Estado = { marcas: Record<string, MarcaDaNay>; nay: EstadoDaNay | null; carregado: boolean; erro: string | null }

let estado: Estado = { marcas: {}, nay: null, carregado: false, erro: null }
const ouvintes = new Set<(e: Estado) => void>()
let buscando: Promise<void> | null = null
let relogio: ReturnType<typeof setInterval> | null = null
let ultimaBusca = 0
const CADA_MS = 60_000

function avisar() {
  for (const o of ouvintes) o(estado)
}

export function recarregarMarcasDaParceria(fresco = false, esperar = false): Promise<void> {
  if (buscando) return buscando
  buscando = (async () => {
    let vencida = false
    try {
      const r = await fetch(`/api/parceria/marcas${fresco ? '?fresco=1' : esperar ? '?esperar=1' : ''}`)
      const j = await r.json().catch(() => ({}))
      if (!r.ok) throw new Error(j?.error || `HTTP ${r.status}`)
      estado = { marcas: j.marcas || {}, nay: j.nay ?? null, carregado: true, erro: null }
      vencida = j.vencida === true
    } catch (e: any) {
      estado = { ...estado, carregado: true, erro: e?.message || 'Não consegui ler a Nay' }
    } finally {
      ultimaBusca = Date.now()
      buscando = null
      avisar()
    }
    // veio a cópia vencida (a tela abriu com ela): agora espera a conta nova
    if (vencida && !fresco && !esperar) void recarregarMarcasDaParceria(false, true)
  })()
  return buscando
}

function aoVoltar() {
  if (document.visibilityState === 'visible' && Date.now() - ultimaBusca > 20_000) void recarregarMarcasDaParceria(false, true)
}

export function useParceriaMarcas(ativo = true) {
  const [e, setE] = useState<Estado>(estado)
  useEffect(() => {
    if (!ativo) return
    ouvintes.add(setE)
    setE(estado)
    if (!estado.carregado || Date.now() - ultimaBusca > CADA_MS) void recarregarMarcasDaParceria()
    if (!relogio) {
      relogio = setInterval(() => {
        if (document.visibilityState === 'visible') void recarregarMarcasDaParceria(false, true)
      }, CADA_MS)
      document.addEventListener('visibilitychange', aoVoltar)
    }
    return () => {
      ouvintes.delete(setE)
      if (ouvintes.size === 0 && relogio) {
        clearInterval(relogio)
        relogio = null
        document.removeEventListener('visibilitychange', aoVoltar)
      }
    }
  }, [ativo])
  return { marcas: e.marcas, nay: e.nay, carregado: e.carregado, erro: e.erro, recarregar: recarregarMarcasDaParceria }
}

/**
 * DEPOIS DE MEXER numa conversa (mudar a etapa, soltar): as marcas de AGORA, sem o
 * cache do servidor. Espera a busca que já estiver no ar -- ela pode ter saído
 * antes da mudança -- e busca de novo. É o que deixa a tela dizer na hora onde a
 * conversa ficou, em vez de esperar o minuto da próxima leitura.
 */
export async function marcasDepoisDeMudar(): Promise<Record<string, MarcaDaNay>> {
  // `while`, não `if`: a leitura vencida emenda outra (a que espera a conta nova)
  while (buscando) await buscando
  await recarregarMarcasDaParceria(true)
  return estado.marcas
}
