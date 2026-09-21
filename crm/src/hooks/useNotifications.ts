'use client'

import { useEffect, useState, useCallback } from 'react'
import { Notification } from '@/lib/types'
import { useAuth } from './useAuth'

export function useNotifications(limit: number = 20) {
  const { organizationId } = useAuth()
  const [notifications, setNotifications] = useState<Notification[]>([])
  const [loading, setLoading] = useState(true)
  const [unreadCount, setUnreadCount] = useState(0)

  const fetchNotifications = useCallback(async () => {
    if (!organizationId) return
    try {
      const res = await fetch('/api/notifications')
      if (!res.ok) return
      const { data } = await res.json()
      const list = (data || []).slice(0, limit) as Notification[]
      setNotifications(list)
      setUnreadCount(list.filter((n: any) => !n.is_read).length)
    } catch {
      // Silently fail
    } finally {
      setLoading(false)
    }
  }, [organizationId, limit])

  const markAsRead = useCallback(async (notificationId: string) => {
    setNotifications(prev => prev.map(n => n.id === notificationId ? { ...n, is_read: true } : n))
    setUnreadCount(prev => Math.max(0, prev - 1))
    await fetch('/api/notifications', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ids: [notificationId] }),
    })
  }, [])

  const markAllAsRead = useCallback(async () => {
    setNotifications(prev => prev.map(n => ({ ...n, is_read: true })))
    setUnreadCount(0)
    await fetch('/api/notifications', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ markAllAsRead: true }),
    })
  }, [])

  useEffect(() => {
    fetchNotifications()
  }, [fetchNotifications])

  return { notifications, loading, unreadCount, markAsRead, markAllAsRead, refetch: fetchNotifications }
}
