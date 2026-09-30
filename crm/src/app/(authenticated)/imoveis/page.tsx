'use client'

/**
 * A ABA IMÓVEIS DO CRM É A DO SITE (Pedro, 30/09/2026): "quero trocar essa aba
 * imóveis do crm pela aba todos os imóveis lá do site, exatamente como está no
 * site, porque essa do crm está ruim ... com todas as funções do site, mas
 * mantendo a otimização, certas coisas podem carregar só quando clicar".
 *
 * Não é cópia: é a própria página do site (Todos, Apartamentos, Casas, Outros,
 * Anúncios, Condomínios, Mapa, exportar, seleção, edição), servida pelo CRM em
 * /admin/imoveis.html -- ver src/lib/painelDoSite.ts. O que mudar no site
 * aparece aqui sem deploy do CRM.
 *
 * O PESO: nada disso entra no pacote do CRM. A página só é buscada quando
 * alguém abre esta aba, e dentro dela as abas e a gaveta já carregam sob
 * demanda, como no site.
 *
 * A aba antiga (a que manda o card para uma conversa) continua em
 * /imoveis/antiga. Mandar imóvel pelo chat segue igual: `/3050` no campo de
 * mensagem.
 */
import Link from 'next/link'
import { useState } from 'react'

export default function ImoveisPage() {
  const [carregou, setCarregou] = useState(false)
  return (
    <div className="h-full flex flex-col">
      <div className="flex items-center justify-end gap-3 px-4 py-1 text-xs text-muted">
        {!carregou && <span className="mr-auto">Abrindo a aba de imóveis do site…</span>}
        <Link href="/imoveis/antiga" className="underline opacity-80 hover:opacity-100">
          Mandar imóvel para uma conversa (tela antiga)
        </Link>
      </div>
      <iframe
        src="/admin/imoveis.html"
        title="Imóveis"
        onLoad={() => setCarregou(true)}
        className="flex-1 w-full border-0 bg-white"
      />
    </div>
  )
}
