'use client'

import React, { createContext, useContext, useState, useCallback, ReactNode } from 'react'
import ToastContainer from '@/components/Shared/Toast/ToastContainer'
import { useAuth } from '@/hooks'

export type NotificationType = 'success' | 'warning' | 'error' | 'info' | 'message'

export interface Notification {
  id: string
  type: NotificationType
  title: string
  message: string
  actionText?: string
  onAction?: () => void
  duration?: number
  linkUrl?: string
  customColor?: string
  customIcon?: React.ElementType
  skipPersist?: boolean
}

interface NotificationContextProps {
  notifications: Notification[]
  addNotification: (notification: Omit<Notification, 'id'>) => void
  removeNotification: (id: string) => void
}

const NotificationContext = createContext<NotificationContextProps | undefined>(undefined)

export function NotificationProvider({ children }: { children: ReactNode }) {
  const [notifications, setNotifications] = useState<Notification[]>([])
  const { organizationId, currentOrganization } = useAuth()

  const addNotification = useCallback((notification: Omit<Notification, 'id'>) => {
    const id = Math.random().toString(36).substring(2, 9)
    const isTest = notification.skipPersist === true

    const newNotification = {
      ...notification,
      id,
      duration: notification.duration || 5000,
      actionText: isTest ? notification.actionText : (notification.actionText || 'Ver chat'),
      linkUrl: isTest ? notification.linkUrl : (notification.linkUrl || '/chat'),
    }

    setNotifications(prev => [...prev, newNotification])

    // Persist to database
    if (!notification.skipPersist) {
      const memberId = currentOrganization?.id
      if (organizationId && memberId) {
        fetch('/api/notifications', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            recipient_member_id: memberId,
            type: newNotification.type || 'info',
            title: newNotification.title || '',
            body: newNotification.message || '',
            metadata: { linkUrl: newNotification.linkUrl },
          }),
        }).catch(err => console.error('[NotificationContext] Failed to persist notification:', err))
      }
    }
  }, [organizationId, currentOrganization])

  const removeNotification = useCallback((id: string) => {
    setNotifications(prev => prev.filter(n => n.id !== id))
  }, [])

  return (
    <NotificationContext.Provider value={{ notifications, addNotification, removeNotification }}>
      {children}
      <ToastContainer notifications={notifications} removeNotification={removeNotification} />
    </NotificationContext.Provider>
  )
}

export function useNotification() {
  const context = useContext(NotificationContext)
  if (context === undefined) throw new Error('useNotification must be used within a NotificationProvider')
  return context
}
