'use client'

/**
 * IMÓVEIS JÁ ENVIADOS, NO CARD DO CONTATO (Pedro, 05/10/2026): "ela precisa identificar os
 * imóveis que já mandou para cada corretor para não mandar de novo, inclusive põe isso como
 * um campo lá no card da conversa do corretor".
 *
 * A lista é a mesma que a Nay consulta (crm_imoveis_enviados, migração 292): o que saiu por
 * ela, pela Nay velha ou pelo publicador. Um imóvel por etiqueta, o mais recente primeiro;
 * o que saiu em mais de um dia leva o "2x" em vermelho. Tocar no código põe o imóvel no
 * "Enviar imóvel" do card, como no histórico.
 */
import { useState } from 'react'
import type { ImovelEnviado } from '@/lib/tiposNay'
import { diaEmManaus } from '@/lib/fusoDeManaus'

const PRIMEIROS = 8

function dia(iso: string, hoje: string): string {
  const d = diaEmManaus(new Date(iso))
  if (d === hoje) return 'hoje'
  const [, m, dd] = d.split('-')
  return `${dd}/${m}`
}

export default function ImoveisJaEnviados({ enviados, aoEscolher }: { enviados: ImovelEnviado[]; aoEscolher: (codigo: number) => void }) {
  const [todos, setTodos] = useState(false)
  const hoje = diaEmManaus()
  const lista = todos ? enviados : enviados.slice(0, PRIMEIROS)
  return (
    <div>
      <ul className="flex flex-wrap gap-1.5">
        {lista.map((e) => {
          const nome = (e.imovel || '').replace(/, código \d+$/, '')
          const repetido = e.dias > 1
          return (
            <li key={e.codigo}>
              <button type="button" onClick={() => aoEscolher(e.codigo)}
                      className="inline-flex items-center gap-1.5 max-w-full h-7 px-2.5 rounded-full text-[12.5px]"
                      style={{ background: 'var(--wa-search)', border: '1px solid var(--wa-divider)', color: 'var(--wa-text)' }}
                      title={`${nome || 'Imóvel'} (${e.codigo}): enviado ${e.dias > 1
                        ? `em ${e.dias} dias, de ${dia(e.primeiroEm, hoje)} a ${dia(e.ultimoEm, hoje)}` : dia(e.ultimoEm, hoje)}. Toque para pôr no Enviar imóvel.`}>
                <span className="font-semibold" style={{ color: 'var(--wa-green)' }}>{e.codigo}</span>
                {nome && <span className="truncate max-w-[150px]">{nome}</span>}
                <span style={{ color: 'var(--wa-text-2)' }}>{dia(e.ultimoEm, hoje)}</span>
                {repetido && <span className="font-bold" style={{ color: 'var(--wa-tag-tel)' }}>{e.dias}x</span>}
              </button>
            </li>
          )
        })}
      </ul>
      {enviados.length > PRIMEIROS && (
        <button type="button" onClick={() => setTodos((v) => !v)} className="text-[13px] font-semibold mt-2" style={{ color: 'var(--wa-green)' }}>
          {todos ? 'Mostrar menos' : `Ver todos (${enviados.length})`}
        </button>
      )}
      <p className="text-[11.5px] mt-2 leading-4" style={{ color: 'var(--wa-text-2)' }}>
        A Nay não manda de novo o que já enviou: ela pergunta se a pessoa tem interesse e só reenvia com o sim.
      </p>
    </div>
  )
}
