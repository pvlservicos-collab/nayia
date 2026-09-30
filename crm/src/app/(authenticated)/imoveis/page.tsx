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
 * aparece aqui sem deploy do CRM. Ela vem sem o menu do site e no tema (claro
 * ou escuro) de quem está usando o CRM -- ver src/lib/painelDoSiteTema.ts.
 *
 * O PESO: nada disso entra no pacote do CRM. A página só é buscada quando
 * alguém abre esta aba, e dentro dela as abas e a gaveta já carregam sob
 * demanda, como no site.
 *
 * A tela antiga saiu (Pedro: "já tem a função enviar lá em cima"). Mandar
 * imóvel para uma conversa continua pelo Enviar imóvel e pelo `/3050` no chat.
 */
export default function ImoveisPage() {
  return (
    <div className="h-full flex flex-col">
      <iframe src="/admin/imoveis.html" title="Imóveis" className="flex-1 w-full border-0" />
    </div>
  )
}
