'use client'

/*
 * Aba "Grupos" do menu, ao lado da Captação (Pedro, 03/10/2026): os grupos do número da Parceria --
 * mensagens guardadas, mandar mensagem, participantes com planilha, e editar onde o número é admin.
 * Ver src/components/Chat/GruposDaParceria.tsx e src/lib/gruposParceria.ts.
 */
import GruposDaParceria from '@/components/Chat/GruposDaParceria'

export default function GruposPage() {
  return (
    <div className="chat-theme h-full flex flex-col min-h-0">
      <GruposDaParceria />
    </div>
  )
}
