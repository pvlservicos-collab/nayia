'use client'

import { useState, useEffect, useCallback } from 'react'
import { useAuth } from './useAuth'

export interface ChatButtonConfig {
  enabled: boolean
  webhook_url: string
  position: 'chat' | 'sidebar'
}

export interface ChatButtonSettings {
  pausar_ia: ChatButtonConfig
  sugerir_passos: ChatButtonConfig
  sinalizar_ajuste: ChatButtonConfig
  resumir_conversa: ChatButtonConfig
}

export type ChatButtonKey = keyof ChatButtonSettings

const DEFAULT_SETTINGS: ChatButtonSettings = {
  pausar_ia: { enabled: true, webhook_url: '', position: 'chat' },
  sugerir_passos: { enabled: true, webhook_url: '', position: 'chat' },
  sinalizar_ajuste: { enabled: false, webhook_url: '', position: 'chat' },
  resumir_conversa: { enabled: false, webhook_url: '', position: 'chat' },
}

const STORAGE_KEY = 'atlas_chat_button_settings'

export function useChatButtonSettings() {
  const { organizationId } = useAuth()
  const [settings, setSettings] = useState<ChatButtonSettings>(DEFAULT_SETTINGS)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    try {
      const key = `${STORAGE_KEY}_${organizationId || 'default'}`
      const stored = typeof window !== 'undefined' ? localStorage.getItem(key) : null
      if (stored) {
        const raw = JSON.parse(stored)
        const parsed: any = {}
        for (const k of Object.keys(DEFAULT_SETTINGS)) {
          const rawVal = raw[k]
          if (typeof rawVal === 'boolean') {
            parsed[k] = { enabled: rawVal, webhook_url: '', position: 'chat' }
          } else if (rawVal && typeof rawVal === 'object') {
            parsed[k] = {
              enabled: !!rawVal.enabled,
              webhook_url: rawVal.webhook_url || '',
              position: rawVal.position === 'sidebar' ? 'sidebar' : 'chat',
            }
          } else {
            parsed[k] = DEFAULT_SETTINGS[k as ChatButtonKey]
          }
        }
        setSettings(parsed as ChatButtonSettings)
      }
    } catch {
      // Use defaults
    } finally {
      setLoading(false)
    }
  }, [organizationId])

  const updateSettings = (updates: Partial<ChatButtonSettings>) => {
    const newSettings = { ...settings, ...updates }
    setSettings(newSettings)
    const key = `${STORAGE_KEY}_${organizationId || 'default'}`
    if (typeof window !== 'undefined') {
      localStorage.setItem(key, JSON.stringify(newSettings))
    }
  }

  const fireWebhook = useCallback(
    async (key: ChatButtonKey, leadData: { id: string; title: string; phone?: string; email?: string; stageName?: string }) => {
      const config = settings[key]
      if (!config.enabled || !config.webhook_url) return false
      try {
        const payload = {
          action: key,
          context: { organization_id: organizationId, timestamp: new Date().toISOString() },
          lead: { id: leadData.id, title: leadData.title, phone: leadData.phone || null, email: leadData.email || null, stage: leadData.stageName || null },
        }
        const res = await fetch(config.webhook_url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        })
        return res.ok
      } catch (err) {
        console.error(`[useChatButtons] Webhook error for "${key}":`, err)
        return false
      }
    },
    [settings, organizationId]
  )

  return { settings, loading, updateSettings, fireWebhook }
}
