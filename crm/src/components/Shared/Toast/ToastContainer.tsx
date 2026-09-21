'use client'

import React from 'react'
import { Notification } from '@/contexts/NotificationContext'
import Toast from './Toast'

interface ToastContainerProps {
    notifications: Notification[]
    removeNotification: (id: string) => void
}

export default function ToastContainer({ notifications, removeNotification }: ToastContainerProps) {
    return (
        <div className="fixed bottom-6 left-6 z-[9999] flex flex-col items-start gap-3 pointer-events-none">
            {notifications.map((notification) => (
                <div key={notification.id} className="pointer-events-auto">
                    <Toast notification={notification} onClose={removeNotification} />
                </div>
            ))}
        </div>
    )
}
