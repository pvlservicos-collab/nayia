'use client'

import { useState, useRef, useEffect } from 'react'
import Link from 'next/link'
import { usePathname, useRouter, useSearchParams } from 'next/navigation'
import {
  ChartBar,
  Kanban,
  WhatsappLogo,
  InstagramLogo,
  Users,
  MagnifyingGlass,
  Plus,
  CaretDown,
  Gear,
  SignOut,
  Buildings,
  FlowArrow,
  IdentificationBadge,
  Sun,
  Moon,
  List,
  X,
  ShieldCheck,
  PaperPlaneTilt,
  UsersThree,
  ChatsCircle,
  Graph,
  ChatTeardropText,
  BookOpenText,
} from '@phosphor-icons/react'
import { useAuth, usePipeline } from '@/hooks'
import { useTheme } from '@/contexts/ThemeContext'
import { signOut } from 'next-auth/react'
import FilterButton from '@/components/Shared/FilterButton'
import GlobalSearch from '@/components/Shared/GlobalSearch'
import ContatoNovo from '@/components/Shared/ContatoNovo'
import TamanhoDasConversas from '@/components/Shared/TamanhoDasConversas'
import { usePipelineFilters } from '@/contexts/FilterContext'

/* O MENU (Pedro, 08/10/2026): "retire a aba início, deixe quando a pessoa logar já abre no whatsapp parceria,
   e coloca grupos, corretores e configuração em um só menu + Mais e coloca uma nova aba chamada Chat OLX".
   A aba Início saiu (o endereço "/" leva à Parceria; o painel de números ficou em /inicio). Os itens com
   `mais: true` moram atrás do botão "+ Mais" na barra do computador; na gaveta do celular aparecem todos. */
const NAV_ITEMS = [
  { label: 'Pipeline', href: '/pipeline', icon: Kanban },
  // TRES LINHAS DE WHATSAPP, uma aba cada (Tel, 28/09/2026): "São 3 WhatsApp,
  // cada um em uma tab lá no CRM... não misturando contatos". Mesma tela,
  // conversas separadas por linha. `curto` é o nome na barra do celular.
  { label: 'WhatsApp Oficial', curto: 'Oficial', href: '/chat', icon: WhatsappLogo },
  { label: 'WhatsApp Parceria', curto: 'Parceria', href: '/chat/parceria', icon: WhatsappLogo },
  // 19/10 (Pedro: "lá em cima, de WhatsApp Captação para WhatsApp Leads"); a rota e a linha continuam 'captacao'
  { label: 'WhatsApp Leads', curto: 'Leads', href: '/chat/captacao', icon: WhatsappLogo },
  // CHAT OLX (08/10, Pedro): "troca a página conversa por um redirect em outra aba para https://chat.olx.com.br/".
  // O item abre o chat da própria OLX numa aba nova do navegador (`externo`). A página de conversas do CRM
  // (/chat/olx: as duas contas e as consultas do bot) continua existindo, sem link no menu -- é para lá que a
  // OLX devolve quem conecta uma conta.
  // 13/10 (Pedro: "quando clico em chat olx ainda me redireciona para a olx ao invés de abrir a tela com as funções que
  // pedi"): com o aplicativo homologado, o item volta a abrir a tela do CRM (chat, anúncios e informações de cada conta).
  // O chat da própria OLX ficou num botão dentro dela.
  { label: 'Chat OLX', curto: 'OLX', href: '/chat/olx', icon: ChatsCircle, externo: false },
  // OS GRUPOS DO NÚMERO DA PARCERIA (Pedro, 03/10/2026: "pode ficar do lado de captação, aba Grupos"):
  // mensagens guardadas, participantes, planilha, e editar onde o número é admin.
  { label: 'Grupos', curto: 'Grupos', href: '/chat/grupos', icon: UsersThree, mais: true },
  // A ABA IMOVEIS (Tel, 27/09/2026): o mesmo acervo da tela do site, aqui dentro,
  // para achar imovel e mandar direto numa conversa.
  { label: 'Imóveis', href: '/imoveis', icon: Buildings },
  // CHAT CHAVES NA MÃO (Pedro, 21/10/2026: "no lugar de visitantes que vai pra dentro do menu, Chat Chaves na Mão igual o
  // olx mesmas coisas"): os leads do portal, os imóveis do XML e as informações da integração (458/459)
  { label: 'Chat Chaves na Mão', curto: 'Chaves', href: '/chat/chavesnamao', icon: ChatsCircle },
  // VISITANTES (Pedro, 20/10/2026): quem já visitou com a gente (corretores e clientes), por dia, mês, trimestre e total.
  // 21/10: foi para dentro do "+ Mais" (o lugar dela ficou com o Chat Chaves na Mão)
  { label: 'Visitantes', href: '/visitantes', icon: Users, mais: true },
  // BUSCAR IMÓVEL OLX (Pedro, 19/10/2026): a busca da OLX aberta à mão com os dados do cliente (422); o mesmo caminho da Nay
  { label: 'Buscar imóvel OLX', curto: 'Buscar OLX', href: '/buscar-imovel-olx', icon: MagnifyingGlass, mais: true },
  // CORRETORES (Pedro, 30/09/2026): "cria mais uma aba ali no CRM ... Corretores,
  // com vários quadradinhos, cada um um corretor, com as métricas". O Funil de
  // Mensagens foi para dentro de Configurações.
  { label: 'Corretores', href: '/corretores', icon: IdentificationBadge, mais: true },
  // VISÃO GERAL (Pedro, 15/10/2026: "uma página nova, tanto no site como no CRM, chama Visão geral"): o mapa do projeto
  // nas duas VPS. É a página do site (/admin/visao-geral.html) servida aqui dentro, como a aba Imóveis.
  { label: 'Visão geral', href: '/visao-geral', icon: Graph, mais: true },
  // TUTORIAIS (Pedro, 29/10/2026): "uma pasta no menu Mais, TUTORIAIS, tipo uma documentação" -- os passos de cada função
  // com prints (lib/tutoriais.ts); a busca do alto também acha
  { label: 'Tutoriais', href: '/tutoriais', icon: BookOpenText, mais: true },
  { label: 'Configurações', href: '/settings/organization', icon: Gear, mais: true },
]

/** Onde o CRM abre: depois do login, no logo e no endereço "/". */
const PAGINA_INICIAL = '/chat/parceria'

// Destinos mais usados — ficam sempre à mão na barra inferior do celular.
// Os demais (Configurações, Funil de Mensagens, Métricas) ficam atrás do "Mais",
// que abre a mesma gaveta lateral — só um sistema de navegação por vez no celular.
const MOBILE_TAB_LABELS = ['WhatsApp Oficial', 'WhatsApp Parceria', 'WhatsApp Leads', 'Pipeline', 'Imóveis']

export default function Navbar() {
  const pathname = usePathname()
  const router = useRouter()
  const { organizationId, permissions, isMaster, roleName, user, profileName, loading: authLoading } = useAuth()
  const { isDark, toggleTheme } = useTheme()
  const searchParams = useSearchParams()
  const pipelineIdParam = searchParams.get('pipelineId')
  const { pipelines, selectedPipelineId } = usePipeline(organizationId || '')
  const activePipelineId = pipelineIdParam || selectedPipelineId

  /* A aba acesa e a de caminho MAIS LONGO que casa com o endereco. Sem
     isto, /chat/parceria acenderia tambem a aba /chat (captacao), porque
     '/chat' e prefixo de '/chat/parceria'. */
  const hrefAtivo = NAV_ITEMS
    .map((i) => i.href)
    .filter((h) => pathname === h || (h !== '/' && pathname.startsWith(h)))
    .sort((a, b) => b.length - a.length)[0]

  const { setFilters } = usePipelineFilters()
  const [showPipelineDropdown, setShowPipelineDropdown] = useState(false)
  const [showUserDropdown, setShowUserDropdown] = useState(false) // Added
  const [showMobileMenu, setShowMobileMenu] = useState(false)
  const [showMais, setShowMais] = useState(false)

  useEffect(() => { setShowMobileMenu(false); setShowMais(false) }, [pathname])

  // RESPOSTAS TEL (527): quantas dúvidas da Nay esperam o Tel; o botão brilha enquanto houver alguma
  const [duvidasDoTel, setDuvidasDoTel] = useState(0)
  useEffect(() => {
    let vivo = true
    const ler = () => fetch('/api/respostas-tel?n=1').then((r) => r.json()).then((j) => { if (vivo) setDuvidasDoTel(j.n || 0) }).catch(() => undefined)
    ler()
    const t = setInterval(ler, 60000)
    return () => { vivo = false; clearInterval(t) }
  }, [pathname])

  const userDropdownRef = useRef<HTMLDivElement>(null) // Added
  const maisRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      // Assuming there's a ref for pipeline dropdown if needed, but the original code uses onMouseEnter/onMouseLeave
      // For user dropdown:
      if (userDropdownRef.current && !userDropdownRef.current.contains(event.target as Node)) {
        setShowUserDropdown(false)
      }
      if (maisRef.current && !maisRef.current.contains(event.target as Node)) {
        setShowMais(false)
      }
    }

    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [])

  const handleLogout = async () => {
    await signOut({ callbackUrl: '/login', redirect: false })
    router.push('/login')
  }

  // Get user name or email for display
  const displayName = profileName || user?.name || user?.email || 'Usuário'

  // Create initials for avatar (e.g. "Mariana Silva" -> "MS")
  const getInitials = (name: string) => {
    const parts = name.split(' ')
    if (parts.length >= 2) {
      return `${parts[0][0]}${parts[1][0]}`.toUpperCase()
    }
    return name.substring(0, 2).toUpperCase()
  }
  const initials = getInitials(displayName)
  const avatarUrl = user?.image

  const isItemVisible = (label: string): boolean => {
    // Painel /admin (plataforma inteira) — só profiles.isSuperadmin de verdade, nunca
    // via permissions?.['*'] (papel de organização). Um tenant pode criar um papel
    // "Admin" com wildcard; isso não pode abrir a porta pro painel de todas as orgs.
    if (label === 'Admin') return isMaster

    // Superadmins e Admins de organização veem tudo. O papel "Admin" criado pelo fluxo
    // padrão (POST /api/admin/create-workspace) usa permissions: {"*": true} — sem esse
    // check, contas Admin novas ficavam sem menu nenhum (só reconhecia roleName
    // "administrador"/"owner", que não é o valor real usado em lugar nenhum do app).
    if (isMaster || roleName?.toLowerCase() === 'administrador' || roleName?.toLowerCase() === 'owner' || permissions?.['*']) return true

    // TEMPORÁRIO: com o bypass de login (AuthGuard/middleware), não existe sessão
    // real então `permissions` nunca carrega — sem isso o menu só mostrava Início.
    // Reativar: voltar pra `if (!permissions) return false`.
    if (!permissions) return true

    // If permissions aren't loaded yet, default to false (except Dashboard maybe, but safer to hide until loaded)
    if (!permissions) return false

    // Evaluate based on the JSON settings
    switch (label) {
      case 'Dashboard': return !!permissions.settings?.view_dashboard
      case 'Leads': return !!permissions.settings?.view_leads
      case 'Pipeline': return !!permissions.settings?.view_pipeline
      case 'WhatsApp Oficial': return !!permissions.settings?.view_chat
      case 'WhatsApp Parceria': return !!permissions.settings?.view_chat
      case 'WhatsApp Leads': return !!permissions.settings?.view_chat
      case 'Chat OLX': return !!permissions.settings?.view_chat
      // 30/10 (Pedro: "ele não tem acesso à parte da OLX no CRM dele, precisa ter, libera para ele e para a Rayssa"):
      // a busca da OLX vale para quem atende o chat (o Lucas e a Rayssa são SDR); antes só o Admin via
      case 'Buscar imóvel OLX': return !!permissions.settings?.view_chat
      case 'Grupos': return !!permissions.settings?.view_chat
      case 'DM Instagram': return !!permissions.settings?.view_chat
      case 'Funil de Mensagens': return !!permissions.settings?.view_funnels
      case 'Logs': return !!permissions.settings?.view_logs
      case 'Métricas': return !!permissions.settings?.view_metrics
      case 'Configurações': return !!permissions.settings?.view_settings
      case 'Visão geral': return true
      default: return false
    }
  }

  return (
    <>
    <nav className="app-safe-top glass-soft rounded-none border-x-0 border-t-0 px-4 md:px-3 xl:px-6 h-14 flex items-center justify-between gap-2 sticky top-0 z-50">
      {/* Left: Logo + Nav */}
      {/* gap menor ate 1280px: com a aba nova da Parceria sao seis itens,
          e em notebook eles espremiam a busca e o nome do usuario. */}
      <div className="flex items-center gap-3 xl:gap-6 min-[1800px]:gap-8 min-w-0">
        {/* Logo */}
        <Link href={PAGINA_INICIAL} className="flex items-center gap-2">
          <img src="/logos/imobeasy-simbolo.svg" alt="Imob Easy" className="h-7 w-7 object-contain" />
          {/* o nome escrito só em tela bem larga: o menu ganhou a aba Grupos (03/10) */}
          <span className="font-display font-bold text-ink hidden min-[1800px]:inline">ImobEasy CRM</span>
        </Link>

        {/* Nav Tabs (desktop) */}
        <div className="hidden md:flex items-center gap-0.5 xl:gap-1 min-w-0">
          {NAV_ITEMS.filter(item => !item.mais && isItemVisible(item.label)).map((item) => {
            const isActive = item.href === hrefAtivo
            const Icon = item.icon

            // Special handling for Pipeline with multiple pipelines
            if (item.label === 'Pipeline' && pipelines.length > 1) {
              return (
                <div
                  key={item.href}
                  className="relative"
                  onMouseEnter={() => setShowPipelineDropdown(true)}
                  onMouseLeave={() => setShowPipelineDropdown(false)}
                >
                  <Link
                    href={item.href}
                    className={`flex items-center gap-1.5 px-1.5 lg:px-2 xl:px-3 py-1.5 rounded-lg text-[13px] xl:text-sm font-medium transition-colors border ${isActive
                      ? 'bg-graphite-6 border-white/15 text-accent-2'
                      : 'border-transparent text-muted hover:bg-white/[0.06] hover:text-ink'
                      }`}
                  >
                    <Icon size={16} weight={isActive ? 'fill' : 'regular'} className="hidden min-[1800px]:block" />
                    {item.label}
                    <CaretDown size={12} className="ml-1" />
                  </Link>

                  {/* Dropdown */}
                  {showPipelineDropdown && (
                    <div className="absolute top-full left-0 pt-2 w-48 z-50">
                      <div className="glass-raised rounded-xl py-1">
                        {pipelines.map((pipeline) => (
                          <button
                            key={pipeline.id}
                            onClick={() => {
                              router.push(`/pipeline?pipelineId=${pipeline.id}`)
                              setShowPipelineDropdown(false)
                            }}
                            className={`w-full text-left px-4 py-2 text-sm hover:bg-white/[0.06] transition-colors ${activePipelineId === pipeline.id
                              ? 'text-accent-2 font-semibold'
                              : 'text-ink'
                              }`}
                          >
                            {pipeline.name}
                          </button>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              )
            }

            // Default rendering for other nav items
            return (
              <Link
                key={item.href}
                href={item.href}
                target={item.externo ? '_blank' : undefined}
                rel={item.externo ? 'noopener noreferrer' : undefined}
                className={`flex items-center gap-1.5 px-1.5 lg:px-2 xl:px-3 py-1.5 rounded-lg text-[13px] xl:text-sm font-medium whitespace-nowrap transition-colors border ${isActive
                  ? 'bg-graphite-6 border-white/15 text-accent-2'
                  : 'border-transparent text-muted hover:bg-white/[0.06] hover:text-ink'
                  }`}
                title={item.label}
              >
                {/* 29/10: o ícone só em tela larga; em notebook o espaço é do texto (o menu estourava e cortava a direita) */}
                <Icon size={16} weight={isActive ? 'fill' : 'regular'} className="hidden min-[1800px]:block" />
                {/* o nome curto ("Parceria") até telas bem largas: com a aba Grupos, o menu não cabia (03/10) */}
                <span className="min-[2200px]:hidden">{item.curto ?? item.label}</span>
                <span className="hidden min-[2200px]:inline">{item.label}</span>
              </Link>
            )
          })}

          {/* "+ Mais" (08/10): Grupos, Corretores e Configurações num menu só */}
          {(() => {
            const itensMais = NAV_ITEMS.filter(item => item.mais && isItemVisible(item.label))
            if (!itensMais.length) return null
            const aceso = showMais || itensMais.some(item => item.href === hrefAtivo)
            return (
              <div className="relative" ref={maisRef}>
                <button
                  type="button"
                  onClick={() => setShowMais(v => !v)}
                  aria-haspopup="menu"
                  aria-expanded={showMais}
                  className={`flex items-center gap-1.5 px-1.5 lg:px-2 xl:px-3 py-1.5 rounded-lg text-[13px] xl:text-sm font-medium whitespace-nowrap transition-colors border ${aceso
                    ? 'bg-graphite-6 border-white/15 text-accent-2'
                    : 'border-transparent text-muted hover:bg-white/[0.06] hover:text-ink'
                    }`}
                >
                  <Plus size={16} weight="bold" />
                  Mais
                  <CaretDown size={12} className={`transition-transform ${showMais ? 'rotate-180' : ''}`} />
                </button>
                {showMais && (
                  <div role="menu" className="absolute top-full left-0 mt-2 w-52 glass-raised rounded-xl py-1 z-50">
                    {itensMais.map((item) => {
                      const Icon = item.icon
                      const isActive = item.href === hrefAtivo
                      return (
                        <Link
                          key={item.href}
                          href={item.href}
                          role="menuitem"
                          onClick={() => setShowMais(false)}
                          className={`flex items-center gap-2 px-4 py-2 text-sm transition-colors hover:bg-white/[0.06] ${isActive
                            ? 'text-accent-2 font-semibold'
                            : 'text-muted hover:text-ink'
                            }`}
                        >
                          <Icon size={16} weight={isActive ? 'fill' : 'regular'} />
                          {item.label}
                        </Link>
                      )
                    })}
                  </div>
                )}
              </div>
            )
          })()}

          {/* Conditional Filter Button for Pipeline */}
          {pathname.startsWith('/pipeline') && organizationId && (
            <>
              <div className="w-[1px] h-4 hairline-y mx-1"></div>
              <FilterButton organizationId={organizationId} onFilterChange={setFilters} />
            </>
          )}
        </div>
      </div>

      {/* Right: Search + Notifications + User + Button */}
      <div className="flex items-center gap-1.5 lg:gap-2 min-[1800px]:gap-4 flex-shrink-0">
        {/* ENVIAR IMOVEL (Tel, 28/09/2026): "coloca o enviar imovel do lado do n8n
            la em cima e no crm". Botao no alto, fora das abas -- a mesma tela do
            admin do site. No celular tambem vai escrito (Pedro, 29/09: "quero nao
            so o aviaozinho de enviar imovel e sim um botao Enviar imovel"). */}
        <Link
          href="/disparo"
          title="Enviar imóvel"
          className={`app-tap-target flex items-center justify-center gap-1.5 h-9 px-2.5 lg:px-3 rounded-lg text-[13px] sm:text-sm font-semibold whitespace-nowrap border transition-colors ${pathname.startsWith('/disparo')
            ? 'bg-graphite-6 border-white/15 text-accent-2'
            : 'border-line text-ink hover:border-accent/60'
            }`}
        >
          <PaperPlaneTilt size={16} weight={pathname.startsWith('/disparo') ? 'fill' : 'regular'} />
          <span>Enviar imóvel</span>
        </Link>

        {/* RESPOSTAS TEL (Pedro, 29/10/2026): "um botão brilhante do lado de enviar imóvel" com as dúvidas da Nay que
            esperam o Tel; o número é quantas faltam. */}
        <Link
          href="/respostas-tel"
          title="Respostas Tel: dúvidas da Nay esperando o Tel"
          className={`respostas-tel-brilho respostas-tel-roxo relative app-tap-target flex items-center justify-center gap-1.5 h-9 px-2.5 lg:px-3 rounded-lg text-[13px] sm:text-sm font-semibold whitespace-nowrap border transition-colors ${pathname.startsWith('/respostas-tel')
            ? 'ring-2 ring-white/40'
            : 'hover:brightness-110'
            } ${duvidasDoTel > 0 ? 'respostas-tel-tem' : ''}`}
        >
          <ChatTeardropText size={16} weight={duvidasDoTel > 0 || pathname.startsWith('/respostas-tel') ? 'fill' : 'regular'} />
          <span className="hidden min-[2000px]:inline">Respostas Tel</span>
          {duvidasDoTel > 0 && (
            <span className="min-w-[18px] h-[18px] px-1 rounded-full bg-white text-[#6d28d9] text-[11px] leading-[18px] text-center">{duvidasDoTel}</span>
          )}
        </Link>

        {/* CONTATO NOVO (Pedro, 29/10/2026): o "Criar conversa" da lupa, aqui no alto */}
        <ContatoNovo />

        {/* Busca — input+dropdown no desktop, ícone que abre overlay de tela cheia no celular */}
        <GlobalSearch />

        {/* O sino saiu (Pedro, 09/10): no lugar, + e - do tamanho das conversas,
            para a Rayssa organizar a lista do jeito dela. As notificações
            continuam em /notifications. */}
        <TamanhoDasConversas />

        {/* Dark mode toggle */}
        <button
          onClick={toggleTheme}
          title={isDark ? 'Modo claro' : 'Modo escuro'}
          className="app-tap-target btn-icon w-11 h-11"
        >
          {isDark ? <Sun size={18} weight="fill" className="text-yellow-400" /> : <Moon size={18} />}
        </button>

        {/* User Dropdown */}
        <div className="relative" ref={userDropdownRef}>
          <div
            onClick={() => setShowUserDropdown(!showUserDropdown)}
            className="flex items-center gap-2 cursor-pointer rounded-lg px-2 py-1 border border-transparent hover:border-glass-edge hover:bg-white/[0.06] transition-colors"
          >
            {avatarUrl ? (
              <div className="w-8 h-8 rounded-full flex items-center justify-center overflow-hidden border border-line">
                <img src={avatarUrl} alt={displayName} className="w-full h-full object-cover" />
              </div>
            ) : (
              <div className="w-8 h-8 bg-purple-500/20 rounded-full flex items-center justify-center">
                <span className="text-purple-300 text-xs font-bold">{initials}</span>
              </div>
            )}
            <span className="hidden min-[2000px]:inline text-sm font-medium text-ink truncate max-w-[120px]">{displayName}</span>
            <CaretDown size={14} className={`hidden min-[2000px]:block text-muted transition-transform ${showUserDropdown ? 'rotate-180' : ''}`} />
          </div>

          {/* User Menu Popup */}
          {showUserDropdown && (
            <div className="absolute right-0 top-full mt-2 w-48 glass-raised rounded-xl py-1 z-50 animate-in fade-in slide-in-from-top-2">
              {/* 29/10 (Pedro: "clico no botão do meu nome para ver lá e não aparece as mensagens Tel"): abaixo de
                  2000 px o botão roxo é só o ícone; aqui vai escrito, com quantas faltam */}
              <Link
                href="/respostas-tel"
                onClick={() => setShowUserDropdown(false)}
                className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-[#7c3aed] hover:bg-white/[0.06] transition-colors w-full text-left"
              >
                <ChatTeardropText size={16} weight="fill" />
                <span>Respostas Tel</span>
                {duvidasDoTel > 0 && (
                  <span className="ml-auto min-w-[18px] h-[18px] px-1 rounded-full bg-[#7c3aed] text-white text-[11px] leading-[18px] text-center">{duvidasDoTel}</span>
                )}
              </Link>
              <div className="h-px hairline-x my-1 mx-2"></div>
              <Link
                href="/workspaces"
                onClick={() => setShowUserDropdown(false)}
                className="flex items-center gap-2 px-4 py-2 text-sm text-muted hover:text-ink hover:bg-white/[0.06] transition-colors w-full text-left"
              >
                <Buildings size={16} />
                <span>Organizações</span>
              </Link>
              <Link
                href="/settings/profile"
                onClick={() => setShowUserDropdown(false)}
                className="flex items-center gap-2 px-4 py-2 text-sm text-muted hover:text-ink hover:bg-white/[0.06] transition-colors w-full text-left"
              >
                <Gear size={16} />
                <span>Configurações do Perfil</span>
              </Link>
              <div className="h-px hairline-x my-1 mx-2"></div>
              <button
                onClick={handleLogout}
                className="flex items-center gap-2 px-4 py-2 text-sm text-red-400 hover:text-red-300 hover:bg-red-500/10 transition-colors w-full text-left"
              >
                <SignOut size={16} />
                <span>Sair da conta</span>
              </button>
            </div>
          )}
        </div>
      </div>
    </nav>

    {/* Menu mobile — mesmos NAV_ITEMS da barra desktop, em lista vertical */}
    {showMobileMenu && (
      <div className="md:hidden fixed inset-0 z-[60]">
        <div
          className="absolute inset-0 bg-black/50 backdrop-blur-sm"
          onClick={() => setShowMobileMenu(false)}
        />
        <div className="absolute left-0 top-0 bottom-0 w-72 max-w-[85vw] glass-raised rounded-none border-y-0 border-l-0 flex flex-col">
          <div className="flex items-center justify-between h-14 px-4 relative">
            <Link href={PAGINA_INICIAL} className="flex items-center gap-2" onClick={() => setShowMobileMenu(false)}>
              <img src="/logos/imobeasy-simbolo.svg" alt="Imob Easy" className="h-7 w-7 object-contain" />
              <span className="font-display font-bold text-ink">ImobEasy CRM</span>
            </Link>
            <button
              onClick={() => setShowMobileMenu(false)}
              className="btn-icon w-8 h-8"
              aria-label="Fechar menu"
            >
              <X size={20} />
            </button>
            <div className="absolute bottom-0 left-0 right-0 h-px hairline-x" />
          </div>
          <div className="flex-1 overflow-y-auto p-2">
            {NAV_ITEMS.filter(item => isItemVisible(item.label)).map(item => {
              const isActive = item.href === hrefAtivo
              const Icon = item.icon
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  target={item.externo ? '_blank' : undefined}
                  rel={item.externo ? 'noopener noreferrer' : undefined}
                  onClick={() => setShowMobileMenu(false)}
                  className={`flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors border ${isActive
                    ? 'bg-graphite-6 border-white/15 text-accent-2'
                    : 'border-transparent text-muted hover:bg-white/[0.06]'
                    }`}
                >
                  <Icon size={18} weight={isActive ? 'fill' : 'regular'} />
                  {item.label}
                </Link>
              )
            })}
          </div>
        </div>
      </div>
    )}

    {/* Barra de navegação inferior (celular) — destinos mais usados sempre à mão,
        sem precisar abrir o menu. Padrão de app nativo (Instagram, WhatsApp etc). */}
    <div className="app-safe-bottom md:hidden fixed bottom-0 left-0 right-0 z-50 glass-raised rounded-none border-x-0 border-b-0">
      <div className="h-16 flex items-stretch">
        {NAV_ITEMS.filter(item => MOBILE_TAB_LABELS.includes(item.label) && isItemVisible(item.label)).map(item => {
          // A mesma regra da barra de cima: sem ela, /chat/captacao acenderia
          // também a aba /chat (a oficial), que é prefixo do endereço.
          const isActive = item.href === hrefAtivo
          const Icon = item.icon
          return (
            <Link
              key={item.href}
              href={item.href}
              className={`app-tap-target flex-1 flex flex-col items-center justify-center gap-0.5 transition-colors ${isActive ? 'text-accent-2' : 'text-muted'
                }`}
            >
              <Icon size={22} weight={isActive ? 'fill' : 'regular'} />
              <span className="text-[10px] font-medium leading-none">{item.curto ?? item.label}</span>
            </Link>
          )
        })}
        {/* "Mais" — único outro jeito de navegar no celular; abre a mesma gaveta lateral
            (Configurações, Funil de Mensagens, Métricas etc), nunca os dois ao mesmo tempo. */}
        <button
          onClick={() => setShowMobileMenu(true)}
          className="app-tap-target flex-1 flex flex-col items-center justify-center gap-0.5 text-muted transition-colors"
        >
          <List size={22} />
          <span className="text-[10px] font-medium leading-none">Mais</span>
        </button>
      </div>
    </div>
    </>
  )
}
