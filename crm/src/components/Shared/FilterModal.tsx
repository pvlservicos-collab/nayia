import { X } from '@phosphor-icons/react'
import { useEffect, useRef } from 'react'
import ReactDOM from 'react-dom'

interface FilterModalProps {
    isOpen: boolean
    onClose: () => void
    children: React.ReactNode
}

export default function FilterModal({ isOpen, onClose, children }: FilterModalProps) {
    const modalRef = useRef<HTMLDivElement>(null)

    // Close when clicking outside
    useEffect(() => {
        function handleClickOutside(event: MouseEvent) {
            if (modalRef.current && !modalRef.current.contains(event.target as Node)) {
                onClose()
            }
        }

        if (isOpen) {
            document.addEventListener('mousedown', handleClickOutside)
            return () => document.removeEventListener('mousedown', handleClickOutside)
        }
    }, [isOpen, onClose])

    if (!isOpen) return null

    // Calculate position relative to the button or just standard centered modal?
    // The request says "modal deve 'abraçar' o grid". 
    // Given the reference image looks like a dropdown/popover attached to the button or a floating modal.
    // The original implementation was an absolute div below the button.
    // The requirement says "FilterModal (container + overlay + close)".
    // I will implement it as a centered overlay modal for now as it seems to be a large comprehensive filter.
    // Wait, re-reading prompt: "modal que abre ao clicar em Filtro". "Remover setas laterais flutuantes".
    // The reference image shows a large white card. 
    // Let's stick to the "absolute top-full" approach if it fits, OR a fixed overlay if it's too big.
    // The prompt says "max-width ~1080–1200px". That's very wide for a dropdown.
    // I will make it a fixed overlay centered on screen or slightly below header for better UX.

    return ReactDOM.createPortal(
        <div className="fixed inset-0 z-50 flex items-start justify-center pt-24 px-4 bg-gray-900/20 backdrop-blur-sm">
            <div
                ref={modalRef}
                className="bg-white rounded-2xl shadow-2xl w-full max-w-[1100px] overflow-hidden flex flex-col max-h-[85vh]"
                style={{ animation: 'fadeIn 0.2s ease-out' }}
            >
                <div className="flex-1 overflow-auto">
                    {children}
                </div>
            </div>
        </div>,
        document.body
    )
}
