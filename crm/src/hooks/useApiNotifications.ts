'use client'

import { useState, useEffect, useCallback } from 'react'

export interface ApiNotificationEvent {
  id: string
  eventId: string
  label: string
  description?: string
  iconName: string
  enabled: boolean
  color: string
}

const STORAGE_KEY = 'atlas_api_notifications'

export function useApiNotifications() {
  const [events, setEvents] = useState<ApiNotificationEvent[]>([])
  const [loading, setLoading] = useState(true)

  const fetchSettings = useCallback(() => {
    try {
      const stored = typeof window !== 'undefined' ? localStorage.getItem(STORAGE_KEY) : null
      if (stored) {
        const parsed = JSON.parse(stored)
        if (Array.isArray(parsed)) setEvents(parsed)
      }
    } catch {
      // Use defaults
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    fetchSettings()
  }, [fetchSettings])

  const saveEvents = (newEvents: ApiNotificationEvent[]) => {
    setEvents(newEvents)
    if (typeof window !== 'undefined') {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(newEvents))
    }
  }

  return { events, loading, saveEvents }
}
