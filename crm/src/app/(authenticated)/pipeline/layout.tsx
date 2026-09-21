import { LeadsProvider } from '@/contexts/LeadsContext'

export default function PipelineLayout({ children }: { children: React.ReactNode }) {
  return <LeadsProvider escopo="funil">{children}</LeadsProvider>
}
