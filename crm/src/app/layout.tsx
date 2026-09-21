import type { Metadata, Viewport } from 'next'
import '@/globals.css'
import { SessionProvider } from 'next-auth/react'
import { AuthProvider } from '@/contexts/AuthContext'
import { NotificationProvider } from '@/contexts/NotificationContext'
import { ThemeProvider } from '@/contexts/ThemeContext'

export const metadata: Metadata = {
  title: 'TitaCRM',
  description: 'Sales CRM with AI Insights and Real-time Collaboration',
  appleWebApp: {
    capable: true,
    statusBarStyle: 'black-translucent',
    title: 'TitaCRM',
  },
  icons: {
    // src/app/icon.png ja e detectado pelo Next e vira o favicon sozinho; estes
    // ficam explicitos porque o iOS e a aba do navegador buscam caminhos fixos.
    icon: '/icons/icon-192.png',
    shortcut: '/icons/icon-192.png',
    apple: '/icons/apple-touch-icon.png',
  },
}

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  viewportFit: 'cover',
  themeColor: '#060606',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="pt-BR" suppressHydrationWarning>
      <head>
        {/* Aplica a classe .dark antes da hidratação (dark-first): sem isso, todo
            primeiro carregamento pisca claro e só escurece depois que o ThemeContext
            monta — visível e feio numa marca que depende de atmosfera escura. */}
        <script
          dangerouslySetInnerHTML={{
            __html: "try{if(localStorage.getItem('follem-theme')!=='light')document.documentElement.classList.add('dark')}catch(e){}",
          }}
        />
        <link
          href="https://fonts.googleapis.com/css2?family=Syne:wght@400;500;600;700;800&family=Inter:wght@400;500;600;700&display=swap"
          rel="stylesheet"
        />
      </head>
      <body className="bg-gray-50 dark:bg-void text-gray-900 dark:text-ink font-sans transition-colors duration-200" suppressHydrationWarning>
        <ThemeProvider>
          <SessionProvider>
            <AuthProvider>
              <NotificationProvider>
                {children}
              </NotificationProvider>
            </AuthProvider>
          </SessionProvider>
        </ThemeProvider>
      </body>
    </html>
  )
}
