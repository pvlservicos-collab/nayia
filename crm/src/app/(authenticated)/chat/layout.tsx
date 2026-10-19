import { LeadsProvider } from '@/contexts/LeadsContext'
import DisconnectAlertBanner from '@/components/Chat/DisconnectAlertBanner'

export default function ChatLayout({ children }: { children: React.ReactNode }) {
  return (
    <LeadsProvider escopo="conversas">
      {/* overflow-hidden (19/10): o que passar da altura (o card do contato, a conversa) não deixa a página rolar
          e mostrar o fundo preto embaixo; quem rola é cada lista por dentro */}
      <div className="flex flex-col h-full min-h-0 overflow-hidden">
        <DisconnectAlertBanner />
        <div className="flex-1 min-h-0">{children}</div>
      </div>
    </LeadsProvider>
  )
}
