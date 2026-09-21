import LoginForm from '@/components/Auth/LoginForm'

export default function LoginPage() {
    return (
        <div className="min-h-screen bg-void relative overflow-hidden flex flex-col items-center justify-center p-4">
            {/* Atmosfera: glows radiais azuis sutis */}
            <div className="pointer-events-none absolute inset-0 overflow-hidden" aria-hidden="true">
                <div className="absolute -top-40 left-1/2 -translate-x-1/2 w-[700px] h-[700px] rounded-full bg-[radial-gradient(circle,rgba(242,199,68,0.14)_0%,transparent_70%)]" />
            </div>

            <div className="relative w-full max-w-sm">
                <div className="text-center mb-8">
                    {/* A logo dispensa a moldura que o icone generico precisava:
                        ela ja tem forma propria e vive melhor sobre o glow do fundo. */}
                    <img
                        src="/logos/tita-logo.png"
                        alt="TitaCRM"
                        className="w-20 h-20 mx-auto mb-4 object-contain drop-shadow-[0_0_28px_rgba(242,199,68,0.35)]"
                    />
                    <h1 className="text-2xl font-light text-ink tracking-tight">TitaCRM</h1>
                    <p className="text-muted text-sm mt-1">Entre na sua conta</p>
                </div>
                <LoginForm />
            </div>
        </div>
    )
}
