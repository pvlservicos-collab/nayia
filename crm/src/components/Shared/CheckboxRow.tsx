import { ReactNode } from 'react'

interface CheckboxRowProps {
    label: string
    checked: boolean
    onChange: () => void
    icon?: ReactNode // For avatar or icon
}

export default function CheckboxRow({ label, checked, onChange, icon }: CheckboxRowProps) {
    return (
        <label
            className={`
        flex items-center gap-3 p-2 -ml-2 rounded-lg cursor-pointer transition-all duration-200 group
        ${checked ? 'bg-blue-50/50' : 'hover:bg-gray-50'}
      `}
        >
            <div className="relative flex items-center justify-center w-5 h-5">
                <input
                    type="checkbox"
                    checked={checked}
                    onChange={onChange}
                    className="peer appearance-none w-5 h-5 border-2 border-gray-200 rounded-[6px] checked:bg-blue-600 checked:border-blue-600 transition-all cursor-pointer"
                />
                <svg
                    className="absolute w-3 h-3 text-white opacity-0 peer-checked:opacity-100 pointer-events-none transition-opacity"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                    strokeWidth="3.5"
                >
                    <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                </svg>
            </div>

            {icon && (
                <div className="flex-shrink-0">
                    {icon}
                </div>
            )}

            <span className={`
        text-sm font-medium transition-colors select-none
        ${checked ? 'text-gray-900' : 'text-gray-600 group-hover:text-gray-900'}
      `}>
                {label}
            </span>
        </label>
    )
}
