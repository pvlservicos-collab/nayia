'use client'

import { useState, useEffect } from 'react'
import { X, DownloadSimple, ShareFat } from '@phosphor-icons/react'
import { useIsMobile } from '@/hooks/useIsMobile'

const DISMISS_KEY = 'atlaseye_install_banner_dismissed_at'
const DISMISS_DAYS = 7

interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

function isDismissedRecently() {
  const raw = localStorage.getItem(DISMISS_KEY)
  if (!raw) return false
  const dismissedAt = Number(raw)
  const days = (Date.now() - dismissedAt) / (1000 * 60 * 60 * 24)
  return days < DISMISS_DAYS
}

export default function InstallAppBanner() {
  const isMobile = useIsMobile()
  const [visible, setVisible] = useState(false)
  const [platform, setPlatform] = useState<'ios' | 'android' | null>(null)
  const [installEvent, setInstallEvent] = useState<BeforeInstallPromptEvent | null>(null)

  // Registra o service worker mínimo (só pra habilitar "Instalar app" no Android/Chrome)
  useEffect(() => {
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('/sw.js').catch(() => {})
    }
  }, [])

  useEffect(() => {
    if (!isMobile) return

    const alreadyInstalled =
      window.matchMedia('(display-mode: standalone)').matches ||
      (window.navigator as any).standalone === true
    if (alreadyInstalled) return
    if (isDismissedRecently()) return

    const isIOS = /iphone|ipad|ipod/i.test(navigator.userAgent)
    if (isIOS) {
      setPlatform('ios')
      setVisible(true)
      return
    }

    // Android/Chrome: só mostra depois que o navegador confirma que dá pra instalar
    const handler = (e: Event) => {
      e.preventDefault()
      setInstallEvent(e as BeforeInstallPromptEvent)
      setPlatform('android')
      setVisible(true)
    }
    window.addEventListener('beforeinstallprompt', handler)
    return () => window.removeEventListener('beforeinstallprompt', handler)
  }, [isMobile])

  const dismiss = () => {
    localStorage.setItem(DISMISS_KEY, String(Date.now()))
    setVisible(false)
  }

  const handleInstall = async () => {
    if (!installEvent) return
    await installEvent.prompt()
    await installEvent.userChoice
    setVisible(false)
  }

  if (!visible || !platform) return null

  return (
    <div className="fixed bottom-[calc(64px+env(safe-area-inset-bottom))] left-3 right-3 z-[70] md:hidden">
      <div className="glass-raised rounded-2xl p-4 flex items-start gap-3">
        <div className="w-10 h-10 rounded-xl overflow-hidden flex-shrink-0">
          <img src="/icons/icon-192.png" alt="" className="w-full h-full object-cover" />
        </div>
        <div className="flex-1 min-w-0">
          {platform === 'android' ? (
            <>
              <p className="text-sm font-semibold text-ink">Instalar o TitaCRM</p>
              <p className="text-xs text-muted mt-0.5">Adicione à tela de início pra abrir como um app, em tela cheia.</p>
              <button
                onClick={handleInstall}
                className="btn btn-primary btn-sm mt-2.5"
              >
                <DownloadSimple size={14} weight="bold" />
                Instalar app
              </button>
            </>
          ) : (
            <>
              <p className="text-sm font-semibold text-ink">Adicione o TitaCRM à tela de início</p>
              <p className="text-xs text-muted mt-1 flex items-center gap-1 flex-wrap">
                Toque em <ShareFat size={14} weight="bold" className="text-accent-2" /> Compartilhar e depois em "Adicionar à Tela de Início"
              </p>
            </>
          )}
        </div>
        <button onClick={dismiss} className="btn-icon w-8 h-8 flex-shrink-0" aria-label="Fechar">
          <X size={18} />
        </button>
      </div>
    </div>
  )
}
