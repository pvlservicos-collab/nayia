import { LeadsProvider } from '@/contexts/LeadsContext'
import DisconnectAlertBanner from '@/components/Chat/DisconnectAlertBanner'

export default function ChatLayout({ children }: { children: React.ReactNode }) {
  return (
    <LeadsProvider escopo="conversas">
      <div className="flex flex-col h-full min-h-0">
        <DisconnectAlertBanner />
        <div className="flex-1 min-h-0">{children}</div>
      </div>
    </LeadsProvider>
  )
}
