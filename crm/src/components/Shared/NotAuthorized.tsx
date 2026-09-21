'use client'

import { ShieldWarning } from '@phosphor-icons/react'
import Link from 'next/link'

export default function NotAuthorized() {
    return (
        <div className="flex flex-col items-center justify-center min-h-[60vh] text-center px-4 animate-in fade-in zoom-in duration-300">
            <div className="bg-red-50 text-red-500 p-4 rounded-full mb-6">
                <ShieldWarning weight="duotone" className="w-12 h-12" />
            </div>
            <h1 className="text-2xl font-bold text-gray-900 mb-2">Acesso Negado</h1>
            <p className="text-gray-500 max-w-md mb-8">
                Você não tem autorização para visualizar esse conteúdo. Consulte seu administrador do sistema se acreditar que isso é um erro.
            </p>
            <Link
                href="/dashboard"
                className="px-6 py-2.5 bg-blue-600 text-white font-semibold rounded-lg shadow-sm hover:bg-blue-700 transition-colors"
            >
                Voltar ao Início
            </Link>
        </div>
    )
}
