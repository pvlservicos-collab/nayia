'use client'

import Link from 'next/link'
import { ArrowLeft, CheckCircle, CaretUp, CaretDown, BookOpen, ShieldCheck } from '@phosphor-icons/react'
import { useState } from 'react'
import WhatsAppCloudApiForm from '@/components/Settings/WhatsAppCloudApiForm'

const FAQS = [
    {
        question: "Como obter minhas credenciais?",
        answer: "Crie um App no portal Meta for Developers, adicione o produto WhatsApp, configure um número oficial (com verificação de empresa) e gere um System User Token Permanente no Business Manager."
    },
    {
        question: "O que é o WABA ID?",
        answer: "WABA ID é o identificador da sua WhatsApp Business Account. Você encontra no Meta Business Suite, em Configurações > Contas > Contas do WhatsApp."
    },
    {
        question: "E o Phone Number ID?",
        answer: "É o ID do número de telefone registrado dentro da sua WABA. Ele é diferente do número em si e pode ser encontrado no painel de configuração do WhatsApp Cloud API."
    },
    {
        question: "Meu token fica seguro?",
        answer: "O System Token fica guardado no banco de dados da plataforma e nunca é reexibido pelo backend — só os workers autorizados conseguem lê-lo para enviar mensagens."
    }
]

function FAQItem({ question, answer }: { question: string, answer: string }) {
    const [isOpen, setIsOpen] = useState(false)
    return (
        <div className="border border-line rounded-lg bg-panel-2 overflow-hidden transition-all duration-200">
            <button
                onClick={() => setIsOpen(!isOpen)}
                className="w-full flex items-center justify-between p-4 text-left font-medium text-ink focus:outline-none hover:bg-panel transition-colors"
                aria-expanded={isOpen}
            >
                {question}
                {isOpen ? <CaretUp size={16} className="text-muted" /> : <CaretDown size={16} className="text-muted" />}
            </button>
            <div
                className={`overflow-hidden transition-all duration-300 ${isOpen ? 'max-h-40 opacity-100' : 'max-h-0 opacity-0'}`}
            >
                <div className="p-4 pt-0 text-sm text-muted border-t border-line">
                    {answer}
                </div>
            </div>
        </div>
    )
}

export default function WhatsAppCloudAPIPage() {
    return (
        <div className="max-w-5xl pb-12">
            {/* Header */}
            <div className="flex items-center flex-wrap gap-3 justify-between mb-8 pb-6 border-b border-line">
                <div className="flex items-center gap-4">
                    <Link href="/settings/integrations" className="p-2 -ml-2 hover:bg-panel-2 rounded-full transition-colors text-muted">
                        <ArrowLeft size={20} />
                    </Link>
                    <div>
                        <h1 className="text-2xl font-bold text-ink">WhatsApp Cloud API Oficial</h1>
                        <p className="text-muted text-sm mt-1">Integração oficial via Meta Cloud API.</p>
                    </div>
                </div>
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
                {/* Form Credentials */}
                <div className="lg:col-span-2">
                    <WhatsAppCloudApiForm />

                    {/* FAQs */}
                    <div className="bg-panel border border-line rounded-xl p-8 mt-8">
                        <div className="flex items-center gap-3 mb-6">
                            <div className="w-10 h-10 rounded-lg bg-panel-2 flex items-center justify-center text-muted border border-line">
                                <BookOpen size={20} className="text-muted" />
                            </div>
                            <div>
                                <h2 className="text-lg font-bold text-ink">Perguntas Frequentes (FAQ)</h2>
                                <p className="text-sm text-muted">Tire suas dúvidas sobre o funcionamento da API oficial.</p>
                            </div>
                        </div>

                        <div className="space-y-4">
                            {FAQS.map((faq, i) => (
                                <FAQItem key={i} question={faq.question} answer={faq.answer} />
                            ))}
                        </div>
                    </div>
                </div>

                {/* Benefits Side */}
                <div className="lg:col-span-1">
                    <div className="bg-panel-2 rounded-xl p-6 border border-line">
                        <h3 className="font-bold text-ink flex items-center gap-2 mb-6 text-lg">
                            <CheckCircle size={20} weight="fill" className="text-accent-2" />
                            Benefícios da API Oficial
                        </h3>

                        <ul className="space-y-4 text-sm text-ink">
                            <li className="flex gap-3">
                                <CheckCircle size={16} className="text-accent-2 flex-shrink-0 mt-0.5" />
                                <span>Selo oficial de verificação.</span>
                            </li>
                            <li className="flex gap-3">
                                <CheckCircle size={16} className="text-accent-2 flex-shrink-0 mt-0.5" />
                                <span>Zero risco de banimento seguindo as políticas da Meta.</span>
                            </li>
                            <li className="flex gap-3">
                                <CheckCircle size={16} className="text-accent-2 flex-shrink-0 mt-0.5" />
                                <span>Templates HSM aprovados para disparos ativos.</span>
                            </li>
                            <li className="flex gap-3">
                                <CheckCircle size={16} className="text-accent-2 flex-shrink-0 mt-0.5" />
                                <span>Múltiplos atendentes no mesmo número.</span>
                            </li>
                            <li className="flex gap-3">
                                <ShieldCheck size={16} className="text-accent-2 flex-shrink-0 mt-0.5" />
                                <span>Token guardado no banco de dados da plataforma.</span>
                            </li>
                        </ul>
                    </div>

                    <div className="mt-8 text-xs text-muted flex items-center justify-between pt-6 px-2">
                        <div className="flex items-center gap-2">
                            <div className="w-1.5 h-1.5 bg-emerald-400 rounded-full shadow-[0_0_8px_rgba(52,211,153,0.6)] animate-pulse"></div>
                            Ambiente de produção certificado
                        </div>
                    </div>
                </div>
            </div>
        </div>
    )
}
