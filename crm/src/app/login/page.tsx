import LoginForm from '@/components/Auth/LoginForm'

export default function LoginPage() {
    /*
     * 100dvh, nao 100vh: no celular o vh conta a barra do navegador, entao a
     * tela "inteira" e maior que o visivel e o cartao ficava cortado.
     *
     * O padding de area segura e por causa do viewportFit: 'cover' no layout
     * raiz -- sem ele o topo entra embaixo do entalhe.
     *
     * E os campos do formulario sao 16px no celular (ver LoginForm): abaixo
     * disso o iPhone da zoom sozinho ao tocar, a pagina salta e a tela
     * parece quebrada. Era esse o "toda estranha" do Tel.
     */
    return (
        <div
            className="min-h-[100dvh] bg-void relative overflow-hidden flex flex-col items-center justify-center px-4 py-8"
            style={{
                paddingTop: 'max(2rem, env(safe-area-inset-top))',
                paddingBottom: 'max(2rem, env(safe-area-inset-bottom))',
            }}
        >
            {/* Atmosfera: glows radiais azuis sutis */}
            <div className="pointer-events-none absolute inset-0 overflow-hidden" aria-hidden="true">
                <div className="absolute -top-40 left-1/2 -translate-x-1/2 w-[min(700px,150vw)] h-[min(700px,150vw)] rounded-full bg-[radial-gradient(circle,rgba(139,92,246,0.14)_0%,transparent_70%)]" />
            </div>

            <div className="relative w-full max-w-sm">
                <div className="text-center mb-8">
                    {/* A logo dispensa a moldura que o icone generico precisava:
                        ela ja tem forma propria e vive melhor sobre o glow do fundo. */}
                    <img
                        src="/logos/imobeasy-simbolo.svg"
                        alt="Imob Easy"
                        className="w-20 h-20 mx-auto mb-4 object-contain drop-shadow-[0_0_28px_rgba(139,92,246,0.35)]"
                    />
                    <h1 className="text-2xl font-light text-ink tracking-tight">ImobEasy CRM</h1>
                    <p className="text-muted text-sm mt-1">Entre na sua conta</p>
                </div>
                <LoginForm />
            </div>
        </div>
    )
}
