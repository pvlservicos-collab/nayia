interface ModalFooterProps {
    onClear: () => void
    onApply: () => void
}

export default function ModalFooter({ onClear, onApply }: ModalFooterProps) {
    return (
        <div className="flex items-center justify-end gap-6 px-8 py-6 border-t border-line mt-auto bg-panel">
            <button
                onClick={onClear}
                className="text-xs font-bold text-muted hover:text-ink transition-colors uppercase tracking-wide"
            >
                Limpar Filtros
            </button>
            <button
                onClick={onApply}
                className="px-8 py-3 bg-accent hover:bg-accent-2 active:bg-accent-2 text-white text-sm font-bold rounded-2xl shadow-glow transition-all transform active:scale-95"
            >
                APLICAR FILTROS
            </button>
        </div>
    )
}
