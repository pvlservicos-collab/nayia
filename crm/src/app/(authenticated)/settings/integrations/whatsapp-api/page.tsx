'use client'

import Link from 'next/link'
import { ArrowLeft, Copy, Eye, EyeClosed, WhatsappLogo, CheckCircle, Info, Lightning, CaretUp, CaretDown, BookOpen } from '@phosphor-icons/react'
import { useState } from 'react'

const FAQS = [
    {
        question: "Como obter minha API Key?",
        answer: "Você precisa criar um App no portal Meta for Developers, adicionar o produto WhatsApp, configurar um número oficial (com verificação de empresa) e gerar um Token de Acesso Permanente."
    },
    {
        question: "Quais os custos por mensagem?",
        answer: "A Meta cobra por conversa baseada em categorias (Marketing, Utilidade, Autenticação, Serviço). Consulte a tabela de preços oficial do WhatsApp Cloud API para o Brasil."
    },
    {
        question: "Posso usar modelos de mensagem (HSM)?",
        answer: "Sim! Porém eles exigem aprovação prévia no Gerenciador do WhatsApp. Após aprovados, você poderá dispará-los via automações no TitaCRM."
    }
]

function FAQItem({ question, answer }: { question: string, answer: string }) {
    const [isOpen, setIsOpen] = useState(false)
    return (
        <div className="border rounded-lg bg-panel overflow-hidden transition-all duration-200">
            <button
                onClick={() => setIsOpen(!isOpen)}
                className="w-full flex items-center justify-between p-4 text-left font-medium text-ink focus:outline-none hover:bg-void transition-colors"
                aria-expanded={isOpen}
            >
                {question}
                {isOpen ? <CaretUp size={16} className="text-muted" /> : <CaretDown size={16} className="text-muted" />}
            </button>
            <div
                className={`overflow-hidden transition-all duration-300 ${isOpen ? 'max-h-40 opacity-100' : 'max-h-0 opacity-0'}`}
            >
                <div className="p-4 pt-0 text-sm text-muted border-t">
                    {answer}
                </div>
            </div>
        </div>
    )
}

export default function WhatsAppAPIPage() {
    const [showKey, setShowKey] = useState(false)
    const [hasCopied, setHasCopied] = useState(false)
    const webhookUrl = "https://api.atlaseye.com.br/webhooks/whatsapp/v1/client_8a2b5c..."

    const handleCopy = () => {
        navigator.clipboard.writeText(webhookUrl)
        setHasCopied(true)
        setTimeout(() => setHasCopied(false), 2000)
    }

    return (
        <div className="max-w-5xl pb-12">
            {/* Header Status */}
            <div className="flex items-center flex-wrap gap-3 justify-between mb-8 pb-6 border-b">
                <div className="flex items-center gap-4">
                    <Link href="/settings/integrations" className="p-2 -ml-2 hover:bg-panel-2 rounded-full transition-colors text-muted">
                        <ArrowLeft size={20} />
                    </Link>
                    <div>
                        <h1 className="text-2xl font-bold text-ink">Configuração WhatsApp Business API (On-Premises)</h1>
                        <p className="text-muted text-sm mt-1">Gerencie sua integração oficial do WhatsApp Business via API local/externa.</p>
                    </div>
                </div>
                <div className="flex items-center gap-2 text-sm font-semibold text-muted uppercase tracking-wider">
                    Status: <span className="flex items-center gap-1.5 text-red-500 bg-red-50 px-2.5 py-1 rounded-full"><div className="w-1.5 h-1.5 rounded-full bg-red-500"></div> Desconectado</span>
                </div>
            </div>

            {/* Main Info Card */}
            <div className="bg-panel border rounded-xl p-6 mb-8 flex flex-col md:flex-row items-start md:items-center justify-between gap-6 shadow-sm">
                <div className="flex items-center gap-4">
                    <div className="w-12 h-12 rounded-full bg-green-50 flex items-center justify-center flex-shrink-0">
                        <WhatsappLogo size={28} weight="fill" className="text-green-500" />
                    </div>
                    <div>
                        <h2 className="font-bold text-ink flex items-center gap-2 text-lg">
                            WhatsApp Business API
                            <span className="bg-green-500 text-white text-[10px] uppercase font-bold px-2 py-0.5 rounded-full tracking-wider">Oficial</span>
                        </h2>
                        <p className="text-sm text-muted mt-1">A conexão oficial On-Premises para empresas com servidores próprios.</p>
                    </div>
                </div>
                <div className="text-right whitespace-nowrap">
                    <p className="text-xs text-muted mb-1">Última tentativa de conexão</p>
                    <p className="font-medium text-ink text-sm">Nunca conectado</p>
                </div>
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
                {/* Form Credentials */}
                <div className="lg:col-span-2">
                    <div className="bg-panel border rounded-xl p-8 mb-8 shadow-sm">
                        <div className="flex items-center gap-3 mb-6">
                            <div className="w-8 h-8 rounded-lg bg-green-50 flex items-center justify-center text-green-600">
                                <Lightning size={18} weight="fill" className="rotate-45" />
                            </div>
                            <h3 className="font-bold text-ink text-lg">Configuração de Credenciais</h3>
                        </div>

                        <div className="space-y-5">
                            <div>
                                <label className="block text-sm font-semibold text-muted mb-2">ID da Conta do WhatsApp Business</label>
                                <div className="relative">
                                    <input
                                        type="text"
                                        placeholder="Ex: 10928374650123"
                                        className="w-full border border-line rounded-lg px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-accent focus:border-transparent transition-all"
                                    />
                                    <div className="absolute right-3 top-1/2 -translate-y-1/2 text-muted cursor-help" title="Você encontra este ID no portal Meta for Developers">
                                        <Info size={16} weight="fill" />
                                    </div>
                                </div>
                            </div>

                            <div>
                                <label className="block text-sm font-semibold text-muted mb-2">API Key (Token de Acesso Permanente)</label>
                                <div className="relative">
                                    <input
                                        type={showKey ? "text" : "password"}
                                        placeholder="EAAW..."
                                        className="w-full border border-line rounded-lg px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-accent focus:border-transparent transition-all pr-10"
                                    />
                                    <button
                                        type="button"
                                        onClick={() => setShowKey(!showKey)}
                                        className="absolute right-3 top-1/2 -translate-y-1/2 text-muted hover:text-muted transition-colors"
                                    >
                                        {showKey ? <EyeClosed size={18} /> : <Eye size={18} />}
                                    </button>
                                </div>
                            </div>

                            <div className="pt-4 mt-2">
                                <label className="block text-sm font-semibold text-muted mb-2">Webhook URL</label>
                                <div className="flex items-stretch gap-2">
                                    <input
                                        type="text"
                                        value={webhookUrl}
                                        readOnly
                                        className="w-full bg-void border border-line text-muted rounded-lg px-4 py-2 text-sm focus:outline-none"
                                    />
                                    <button
                                        onClick={handleCopy}
                                        className="flex-shrink-0 flex items-center justify-center gap-2 bg-panel-2 hover:bg-panel-2 text-muted px-4 py-2 rounded-lg text-sm font-medium transition-colors border border-line"
                                    >
                                        <Copy size={16} />
                                        {hasCopied ? 'Copiado!' : 'Copiar'}
                                    </button>
                                </div>
                                <p className="text-xs text-muted italic mt-2">Configure esta URL nas definições do seu App no Facebook Developers.</p>
                            </div>
                        </div>

                        <div className="mt-8">
                            <button className="w-full flex items-center justify-center gap-2 bg-green-600 hover:bg-green-700 text-white font-medium py-3 rounded-lg shadow-sm transition-all shadow-green-500/20 hover:shadow-green-500/40">
                                <Lightning size={16} weight="fill" /> Conectar via API Oficial
                            </button>
                        </div>
                    </div>

                    {/* FAQs */}
                    <div className="bg-panel border rounded-xl p-8 shadow-sm mb-8">
                        <div className="flex items-center gap-3 mb-6">
                            <div className="w-10 h-10 rounded-lg bg-void flex items-center justify-center text-muted border border-line">
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
                    <div className="bg-panel-2 rounded-xl p-6 border border-accent-line shadow-sm">
                        <h3 className="font-bold text-accent-2 flex items-center gap-2 mb-6 text-lg">
                            <CheckCircle size={20} weight="fill" className="text-accent-2" />
                            Benefícios da API
                        </h3>

                        <ul className="space-y-4 text-sm text-accent-2">
                            <li className="flex gap-3">
                                <CheckCircle size={16} className="text-accent-2 flex-shrink-0 mt-0.5" />
                                <span>Selo oficial de verificação.</span>
                            </li>
                            <li className="flex gap-3">
                                <CheckCircle size={16} className="text-accent-2 flex-shrink-0 mt-0.5" />
                                <span>Zero risco de banimento por automação se seguir as políticas.</span>
                            </li>
                            <li className="flex gap-3">
                                <CheckCircle size={16} className="text-accent-2 flex-shrink-0 mt-0.5" />
                                <span>Suporte a Modelos de Mensagem (HSM - envios ativos).</span>
                            </li>
                            <li className="flex gap-3">
                                <CheckCircle size={16} className="text-accent-2 flex-shrink-0 mt-0.5" />
                                <span>Múltiplos atendentes usando o mesmo número simultaneamente.</span>
                            </li>
                            <li className="flex gap-3">
                                <CheckCircle size={16} className="text-accent-2 flex-shrink-0 mt-0.5" />
                                <span>Estatísticas avançadas e painel de análise.</span>
                            </li>
                        </ul>
                    </div>

                    {/* Fake Footer */}
                    <div className="mt-8 text-xs text-muted flex items-center justify-between pt-6 px-2">
                        <div className="flex items-center gap-2">
                            <div className="w-1.5 h-1.5 bg-green-500 rounded-full shadow-[0_0_8px_rgba(34,197,94,0.6)] animate-pulse"></div>
                            Ambiente de produção certificado
                        </div>
                        <div className="flex items-center gap-4">
                            <a href="#" className="hover:text-muted">Termos de Uso</a>
                            <a href="#" className="hover:text-muted">Suporte ATLAS</a>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    )
}
