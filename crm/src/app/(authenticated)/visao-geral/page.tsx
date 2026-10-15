'use client'

/**
 * VISÃO GERAL (Pedro, 15/10/2026): "uma página nova, tanto no site como no CRM, chama Visão geral, e organize todo o
 * meu projeto e recursos na VPS em um fluxograma conectado, todas as Nays e onde elas estão".
 *
 * Não é cópia: é a página do site (/admin/visao-geral.html), servida pelo CRM como a aba Imóveis
 * (src/lib/painelDoSite.ts), sem o menu do site e no tema claro ou escuro de quem usa o CRM. O mapa e as frases do
 * (i) moram em imob-easy/assets/js/visao-geral.js: mudou lá, muda aqui sem deploy do CRM.
 */
export default function VisaoGeralPage() {
  return (
    <div className="h-full flex flex-col">
      <iframe src="/admin/visao-geral.html" title="Visão geral" className="flex-1 w-full border-0" />
    </div>
  )
}
