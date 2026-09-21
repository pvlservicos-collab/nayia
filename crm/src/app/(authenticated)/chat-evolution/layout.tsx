import { LeadsProvider } from '@/contexts/LeadsContext'

export default function ChatEvolutionLayout({ children }: { children: React.ReactNode }) {
  return <LeadsProvider escopo="conversas">{children}</LeadsProvider>
}
