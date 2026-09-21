interface FilterSectionProps {
    title: string
    children: React.ReactNode
    className?: string
}

export default function FilterSection({ title, children, className = '' }: FilterSectionProps) {
    return (
        <div className={`flex flex-col h-full ${className}`}>
            <h4 className="text-[11px] font-bold text-gray-400 uppercase tracking-wider mb-5">
                {title}
            </h4>
            <div className="flex-1">
                {children}
            </div>
        </div>
    )
}
