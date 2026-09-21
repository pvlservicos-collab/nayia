'use client'

import Link from 'next/link'
import { ArrowLeft, ArrowsClockwise, Info, MonitorPlay, DeviceMobile, Users, ShieldCheck, CaretDown, CaretUp, CheckCircle, Warning, MagnifyingGlassPlus, UsersThree } from '@phosphor-icons/react'
import { useState, useEffect, useRef } from 'react'
import { getInstanceStatus, disconnectInstance, createInstance, connectInstanceWithToken, setWebhook } from '@/app/actions/uazapi'
import { useAuth, usePipeline } from '@/hooks'

const FAQS = [
    {
        question: "O celular precisa estar ligado?",
        answer: "Sim, na modalidade Lite a conexão depende do estado do seu aparelho celular. Se o celular estiver offline por muito tempo, a conexão será perdida."
    },
    {
        question: "Quantos aparelhos posso conectar?",
        answer: "Cada instância do TitaCRM permite a conexão de um único aparelho Lite por vez para garantir a estabilidade das automações."
    },
    {
        question: "Como funciona a estabilidade do Lite?",
        answer: "A estabilidade é baseada na tecnologia do WhatsApp Web. É ideal para fluxos de baixo e médio volume e atendimento humano direto."
    },
    {
        question: "Tem limite de mensagens por dia?",
        answer: "Não há limite técnico pela plataforma, mas recomendamos seguir as boas práticas do WhatsApp para evitar bloqueios por spam."
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
                <div className="p-4 text-sm text-muted border-t border-line">
                    {answer}
                </div>
            </div>
        </div>
    )
}

export default function WhatsAppLitePage() {
    const { organizationId } = useAuth();
    const { pipelines } = usePipeline(organizationId || '');
    const [instanceName, setInstanceName] = useState<string | null>(null);
    const [instanceToken, setInstanceToken] = useState<string>(''); // Salva o token da instância
    const [defaultPipelineId, setDefaultPipelineId] = useState<string>('');
    const [connectionState, setConnectionState] = useState<string>('loading'); // loading, not_created, created, connecting, connected, disconnected
    const [qrCodeBase64, setQrCodeBase64] = useState<string | null>(null);
    const [error, setError] = useState<string | null>(null);
    const [isCreating, setIsCreating] = useState(false);
    const [listenGroups, setListenGroups] = useState(false);
    const pollingRef = useRef<NodeJS.Timeout | null>(null);

    // 1. Identificar o usuário e definir o nome da instância baseada na org
    useEffect(() => {
        const fetchOrgDetails = async () => {
            if (organizationId) {
                const orgRes = await fetch('/api/organizations')
                const { data } = orgRes.ok ? await orgRes.json() : { data: null }

                const orgName = data?.name ? data.name.replace(/[^a-zA-Z0-9]/g, '').toLowerCase() : 'atlas';
                const idPrefix = organizationId.replace(/-/g, '').substring(0, 6);
                setInstanceName(`${orgName}_${idPrefix}`);
            } else {
                setConnectionState('loading');
            }
        };

        fetchOrgDetails();
    }, [organizationId]);

    // Salvar integração no banco de dados quando conectar com sucesso
    const saveIntegrationToDb = async (name: string, token: string) => {
        if (!organizationId) return;

        try {
            // 1. Verifica se já existe uma integração WhatsApp Lite para esta organização
            const existingRes = await fetch('/api/integrations?name=WhatsApp+Lite')
            const existingData = existingRes.ok ? await existingRes.json() : { data: [] }
            const existingIntegration = existingData.data?.[0]

            if (existingIntegration) {
                await fetch('/api/integrations', {
                    method: 'PATCH',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ id: existingIntegration.id, status: 'active', config: { ...existingIntegration.config, instanceName: name, instanceToken: token }, mergeConfig: true }),
                })
            } else {
                await fetch('/api/integrations', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ name: 'WhatsApp Lite', type: 'whatsapp_lite', status: 'active', config: { instanceName: name, instanceToken: token } }),
                })
            }

            // FALLBACK ROBUSTO: Salva localmente também, para sobreviver ao F5 caso o DB falhe
            localStorage.setItem(`whatsapp_token_${organizationId}`, token);

        } catch (err) {
            console.error('Failed to save integration to DB', err);
        }
    };

    // 2. Controlar a carga da Instância
    const initializeInstance = async (name: string) => {
        setConnectionState('loading');
        setError(null);

        let currentToken = instanceToken;

        // Verifica se a integração já está no BD para setar o token
        if (organizationId) {
            const dbRes = await fetch('/api/integrations?name=WhatsApp+Lite')
            const dbData = dbRes.ok ? await dbRes.json() : { data: [] }
            const dbIntegration = dbData.data?.[0]

            if (dbIntegration?.config) {
                if (dbIntegration.config.instanceToken) {
                    currentToken = dbIntegration.config.instanceToken;
                    setInstanceToken(currentToken);
                }
                if (dbIntegration.config.defaultPipelineId) {
                    setDefaultPipelineId(dbIntegration.config.defaultPipelineId);
                }
                if (dbIntegration.config.listenGroups !== undefined) {
                    setListenGroups(dbIntegration.config.listenGroups);
                }
            } else {
                const localToken = localStorage.getItem(`whatsapp_token_${organizationId}`);
                if (localToken) {
                    currentToken = localToken;
                    setInstanceToken(currentToken);
                }
            }
        }

        if (!currentToken) {
            setConnectionState('not_created');
            return;
        }

        const res = await getInstanceStatus(currentToken);

        if (res.success) {
            let normalizedState = res.state;
            if (normalizedState === 'open') normalizedState = 'connected';
            if (normalizedState === 'close') normalizedState = 'disconnected';

            setConnectionState(normalizedState || 'not_created');
            // OBS: Não chamamos fetchQrCode aqui para evitar 404. Deixamos o polling lidar com isso.
        } else {
            setError(res.error || "Erro ao inicializar instância");
            setConnectionState('error');
        }
    };

    const handleCreateInstance = async () => {
        if (!instanceName || !organizationId) return;
        setIsCreating(true);
        setError(null);

        // Se já tem um token salvo no estado OU no localStorage, tenta deletar a instância antiga na Uazapi para evitar lixo
        const oldToken = instanceToken || localStorage.getItem(`whatsapp_token_${organizationId}`);
        if (oldToken) {
            try {
                const { deleteInstance } = await import('@/app/actions/uazapi');
                await deleteInstance(oldToken);
            } catch (err) {
                console.warn('Erro ao deletar instância antiga:', err);
            }
        }

        const res = await createInstance(instanceName);

        if (res.success) {
            // Tenta obter o token gerado (Pode vir como hash ou token)
            const newToken = res.instance?.token || res.instance?.hash || res.instance?.instance?.token || '';
            setInstanceToken(newToken);
            setConnectionState('created');
            saveIntegrationToDb(instanceName, newToken);
            // Deixamos a obtenção do QR Code para o polling (para garantir que a instância subiu)
        } else {
            setError(res.error || "Erro ao criar instância");
            setConnectionState('error');
        }
        setIsCreating(false);
    };

    // Usando o token para buscar o QR Code como desejado
    const fetchQrCode = async (token: string) => {
        const res = await connectInstanceWithToken(token);
        if (res.success && res.base64Url) {
            setQrCodeBase64(res.base64Url);
        } else {
            console.error(res.error);
        }
    };

    // 3. Inicializar a instância APENAS quando o instanceName for definido (1 vez)
    useEffect(() => {
        if (!instanceName) return;

        // Inicia a instância (isso deve rodar apenas uma vez ao entrar com nome válido)
        initializeInstance(instanceName);

    }, [instanceName]); // Remover connectionState daqui para evitar loop infinito

    // 4. Efeito para Polling do Status (Assiste connectionState mas não chama initializeInstance inteiro de novo)
    useEffect(() => {
        if (!instanceName || !instanceToken) return;
        if (connectionState === 'loading' || connectionState === 'error' || connectionState === 'connected' || connectionState === 'not_created') {
            // Não faz polling nessas fases (connected já tem o QR, loading ainda tá criando, error deve ser parado)
            return;
        }

        // Se está em 'created' ou 'disconnected' ou 'connecting', e ainda não estourou o timeout, faz polling.
        const checkStatus = async () => {
            const res = await getInstanceStatus(instanceToken);
            if (res.success) {
                let normalizedState = res.state;
                if (normalizedState === 'open') normalizedState = 'connected';
                if (normalizedState === 'close') normalizedState = 'disconnected';

                // Se a instância estiver esperando conexão e não temos QR, buscamos
                if ((normalizedState === 'connecting' || normalizedState === 'disconnected' || normalizedState === 'created') && !qrCodeBase64 && instanceToken) {
                    fetchQrCode(instanceToken);
                }

                // Só atualiza o state se houver mudança, para evitar renders desnecessários
                setConnectionState(prevState => {
                    if (prevState !== normalizedState) {
                        return normalizedState || 'disconnected';
                    }
                    return prevState;
                });
            }
        };

        const interval = setInterval(checkStatus, 3000);

        return () => clearInterval(interval);

    }, [instanceName, connectionState, instanceToken, qrCodeBase64]); // Depende do connectionState para saber se deve iniciar/parar o polling

    // 5. Efeito para registrar Webhook de maneira infalível quando a conexão estiver ativa
    useEffect(() => {
        if (connectionState === 'connected' && instanceToken && organizationId && instanceName) {
            console.log("Triggering saveIntegration and setWebhook via useEffect...");
            saveIntegrationToDb(instanceName, instanceToken);

            const webhookUrl = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/chat-webhook-inbound?org_id=${organizationId}`;
            setWebhook(instanceToken, webhookUrl)
                .then(res => console.log('Webhook registration result:', res))
                .catch(err => console.error('Error setting webhook:', err));
        }
    }, [connectionState, instanceToken, organizationId, instanceName]);

    // Handle logout (Apenas desconecta o aparelho)
    const handleLogout = async () => {
        if (!instanceName || !organizationId || !instanceToken) return;
        setConnectionState('loading');
        setQrCodeBase64(null);

        await disconnectInstance(instanceToken);
        // Volta para state 'disconnected' que aciona o polling/qrcode de novo
        setConnectionState('disconnected');
    };

    // Handle delete (Exclui a instância do painel e do backend)
    const handleDelete = async () => {
        if (!instanceName || !organizationId || !instanceToken) return;
        setConnectionState('loading');
        setQrCodeBase64(null);

        await fetch('/api/integrations', {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ name: 'WhatsApp Lite', status: 'disabled', config: { instanceName: '', instanceToken: '', defaultPipelineId: '' } }),
        });

        const { deleteInstance } = await import('@/app/actions/uazapi');
        await deleteInstance(instanceToken);

        localStorage.removeItem(`whatsapp_token_${organizationId}`);

        setDefaultPipelineId('');
        setInstanceToken('');
        setConnectionState('not_created');
    };

    const handlePipelineChange = async (e: React.ChangeEvent<HTMLSelectElement>) => {
        const newPipelineId = e.target.value;
        setDefaultPipelineId(newPipelineId);

        if (!organizationId) return;

        await fetch('/api/integrations', {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ name: 'WhatsApp Lite', config: { defaultPipelineId: newPipelineId }, mergeConfig: true }),
        });
    };

    const handleToggleListenGroups = async () => {
        const newValue = !listenGroups;
        setListenGroups(newValue);

        if (!organizationId) return;

        await fetch('/api/integrations', {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ name: 'WhatsApp Lite', config: { listenGroups: newValue }, mergeConfig: true }),
        });
    };

    return (
        <div className="max-w-5xl pb-12">
            {/* Header */}
            <div className="flex items-center gap-4 mb-8">
                <Link href="/settings/integrations" className="p-2 -ml-2 hover:bg-panel-2 rounded-full transition-colors text-muted">
                    <ArrowLeft size={20} />
                </Link>
                <div>
                    <h1 className="text-2xl font-bold text-ink">Conexão WhatsApp Lite</h1>
                    <p className="text-muted text-sm mt-1">Conecte sua conta pessoal ou de equipe via QR Code.</p>
                </div>
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-5 gap-6 mb-8">
                {/* Left side: QR Code / Initialization*/}
                <div className="bg-panel border rounded-xl p-4 sm:p-8 flex flex-col items-center justify-center lg:col-span-3 min-h-[400px]">
                    {connectionState === 'loading' && (
                        <div className="flex flex-col items-center justify-center">
                            <div className="w-12 h-12 border-4 border-accent-line border-t-blue-500 rounded-full animate-spin mb-4" />
                            <p className="text-muted">Preparando conexão...</p>
                        </div>
                    )}

                    {connectionState === 'error' && (
                        <div className="flex flex-col items-center justify-center text-center">
                            <div className="w-16 h-16 bg-red-50 text-red-500 rounded-full flex items-center justify-center mb-4">
                                <Warning size={32} />
                            </div>
                            <h3 className="text-lg font-bold text-ink mb-2">Erro de Conexão</h3>
                            <p className="text-muted text-sm mb-6 max-w-sm">{error}</p>
                            <button
                                onClick={() => instanceName && initializeInstance(instanceName)}
                                className="px-4 py-2 bg-panel-2 text-accent-2 rounded-lg font-medium hover:bg-panel-2 transition-colors"
                            >
                                Tentar Novamente
                            </button>
                        </div>
                    )}

                    {connectionState === 'not_created' && (
                        <div className="flex flex-col items-center justify-center text-center w-full max-w-sm">
                            <div className="w-16 h-16 bg-panel-2 text-accent-2 rounded-full flex items-center justify-center mb-6">
                                <DeviceMobile size={32} weight="fill" />
                            </div>
                            <h3 className="text-xl font-bold text-ink mb-2">Configurar Whatsapp Lite</h3>
                            <p className="text-muted mb-8 text-sm">
                                Sua organização ainda não possui uma instância conectada. Clique no botão abaixo para gerar uma agora e em seguida escaneie o código QR com seu celular.
                            </p>

                            <button
                                onClick={handleCreateInstance}
                                disabled={isCreating}
                                className="w-full flex items-center justify-center py-3 bg-accent hover:bg-accent-2 disabled:bg-accent text-white rounded-lg font-medium transition-colors"
                            >
                                {isCreating ? 'Gerando Instância...' : 'Criar Instância & Gerar QR Code'}
                            </button>
                        </div>
                    )}

                    {connectionState === 'connected' && (
                        <div className="flex flex-col items-center justify-center text-center">
                            <div className="w-20 h-20 bg-green-50 text-green-500 rounded-full flex items-center justify-center mb-4">
                                <CheckCircle size={40} weight="fill" />
                            </div>
                            <h3 className="text-xl font-bold text-ink mb-2">Aparelho Conectado!</h3>
                            <p className="text-muted text-sm mb-8 max-w-sm">
                                Seu WhatsApp Lite está operando normalmente. Não desconecte o celular da internet para manter as automações.
                            </p>
                            <div className="flex gap-4">
                                <button
                                    onClick={handleLogout}
                                    className="px-6 py-2.5 bg-yellow-50 text-yellow-700 hover:bg-yellow-100 rounded-lg font-medium transition-colors"
                                >
                                    Desconectar Aparelho
                                </button>
                                <button
                                    onClick={handleDelete}
                                    className="px-6 py-2.5 bg-red-50 text-red-600 hover:bg-red-100 rounded-lg font-medium transition-colors"
                                >
                                    Excluir Instância
                                </button>
                            </div>

                            <div className="mt-8 pt-8 border-t border-line w-full text-left">
                                <h4 className="text-sm font-bold text-ink mb-2 mt-4">Funil de Destino</h4>
                                <p className="text-xs text-muted mb-4">Selecione para qual funil os novos leads que entrarem por este WhatsApp devem ser enviados automaticamente.</p>
                                <select
                                    value={defaultPipelineId}
                                    onChange={handlePipelineChange}
                                    className="w-full bg-void border border-line text-ink text-sm rounded-lg focus:ring-accent focus:border-accent block p-2.5 outline-none transition-colors"
                                >
                                    <option value="">Selecione um Funil</option>
                                    {pipelines.map(p => (
                                        <option key={p.id} value={p.id}>{p.name}</option>
                                    ))}
                                </select>
                            </div>

                            <div className="mt-6 pt-6 border-t border-line w-full text-left">
                                <div className="flex items-center justify-between">
                                    <div className="flex items-center gap-3">
                                        <div className="w-8 h-8 rounded-lg bg-indigo-50 flex items-center justify-center">
                                            <UsersThree size={18} className="text-indigo-500" weight="fill" />
                                        </div>
                                        <div>
                                            <h4 className="text-sm font-bold text-ink">Escutar Grupos</h4>
                                            <p className="text-xs text-muted">Receber mensagens de grupos do WhatsApp no chat.</p>
                                        </div>
                                    </div>
                                    <button
                                        onClick={handleToggleListenGroups}
                                        className={`relative w-11 h-6 rounded-full transition-colors duration-200 ${listenGroups ? 'bg-indigo-500' : 'bg-panel-2'}`}
                                    >
                                        <span
                                            className={`absolute top-0.5 left-0.5 w-5 h-5 rounded-full bg-panel shadow transition-transform duration-200 ${listenGroups ? 'translate-x-5' : 'translate-x-0'}`}
                                        />
                                    </button>
                                </div>
                            </div>
                        </div>
                    )}

                    {(connectionState === 'created' || connectionState === 'disconnected' || connectionState === 'connecting') && (
                        <>
                            <div className="relative w-48 h-48 sm:w-64 sm:h-64 bg-void border-2 border-dashed border-line rounded-xl flex items-center justify-center mb-8 overflow-hidden">
                                {/* Placeholder / QR Code render */}
                                {qrCodeBase64 ? (
                                    <img src={qrCodeBase64} alt="WhatsApp QR Code" className="w-full h-full object-cover" />
                                ) : (
                                    <div className="w-32 h-32 sm:w-48 sm:h-48 bg-panel-2 rounded-lg animate-pulse" />
                                )}

                                <div className="absolute top-0 bottom-0 left-1/2 w-[2px] bg-accent opacity-50 -ml-[1px]" />
                                <div className="absolute left-0 right-0 top-1/2 h-[2px] bg-accent opacity-50 -mt-[1px]" />
                            </div>

                            <div className="flex items-center justify-center gap-2 px-4 py-2 bg-yellow-50 text-yellow-700 text-sm font-medium rounded-full mb-6">
                                <div className="w-2 h-2 rounded-full bg-yellow-500 animate-pulse" />
                                {qrCodeBase64 ? 'Aguardando leitura' : 'Gerando qrcode... aguardando leitura'}
                            </div>

                            <button
                                onClick={() => instanceToken && fetchQrCode(instanceToken)}
                                className="flex items-center justify-center gap-2 bg-accent hover:bg-accent-2 text-white px-6 py-2.5 rounded-lg font-medium transition-colors w-full sm:w-auto"
                            >
                                <ArrowsClockwise size={18} weight="bold" />
                                Gerar Novo QR Code
                            </button>
                        </>
                    )}
                </div>

                {/* Right side: Instructions */}
                <div className="bg-panel border rounded-xl p-4 sm:p-8 lg:col-span-2 shadow-sm">
                    <div className="flex items-center gap-3 mb-6">
                        <div className="w-8 h-8 rounded-full bg-panel-2 flex items-center justify-center text-accent-2">
                            <Info size={18} weight="bold" />
                        </div>
                        <h3 className="font-semibold text-ink text-lg">Como conectar?</h3>
                    </div>

                    <div className="space-y-6">
                        <div className="flex gap-4">
                            <div className="flex-shrink-0 w-8 h-8 rounded-full bg-panel-2 flex items-center justify-center text-muted font-semibold text-sm">
                                1
                            </div>
                            <div>
                                <p className="font-medium text-ink text-sm">Abra o WhatsApp no seu celular</p>
                                <p className="text-xs text-muted mt-1">Certifique-se de que seu celular está com conexão ativa à internet.</p>
                            </div>
                        </div>

                        <div className="flex gap-4">
                            <div className="flex-shrink-0 w-8 h-8 rounded-full bg-panel-2 flex items-center justify-center text-muted font-semibold text-sm">
                                2
                            </div>
                            <div>
                                <p className="font-medium text-ink text-sm">Toque em Aparelhos Conectados</p>
                                <p className="text-xs text-muted mt-1">Vá em Configurações (ou no menu de três pontos) e selecione &quot;Aparelhos Conectados&quot;.</p>
                            </div>
                        </div>

                        <div className="flex gap-4">
                            <div className="flex-shrink-0 w-8 h-8 rounded-full bg-panel-2 flex items-center justify-center text-muted font-semibold text-sm">
                                3
                            </div>
                            <div>
                                <p className="font-medium text-ink text-sm">Aponte a câmera para este QR Code</p>
                                <p className="text-xs text-muted mt-1">Toque em &quot;Conectar um Aparelho&quot; e aponte a câmera para o código ao lado.</p>
                            </div>
                        </div>
                    </div>

                    <div className="mt-8 bg-panel-2 rounded-lg p-4 flex gap-3 border border-accent-line">
                        <Info size={18} className="text-accent-2 flex-shrink-0 mt-0.5" />
                        <p className="text-xs leading-relaxed text-accent-2">
                            <span className="font-semibold">Dica:</span> Para maior estabilidade, desative as opções de economia de bateria para o WhatsApp no seu smartphone.
                        </p>
                    </div>
                </div>
            </div>

            {/* FAQs */}
            <div className="bg-panel border rounded-xl p-4 sm:p-8">
                <div className="flex items-center gap-3 mb-6">
                    <div className="w-10 h-10 rounded-lg bg-panel-2 flex items-center justify-center text-accent-2">
                        <MonitorPlay size={20} weight="fill" className="opacity-50 absolute" />
                        <Info size={16} weight="bold" />
                    </div>
                    <div>
                        <h2 className="text-lg font-bold text-ink">Perguntas Frequentes (FAQ)</h2>
                        <p className="text-sm text-muted">Tire suas dúvidas sobre a conexão WhatsApp Lite.</p>
                    </div>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    {FAQS.map((faq, i) => (
                        <FAQItem key={i} question={faq.question} answer={faq.answer} />
                    ))}
                </div>
            </div>
        </div >
    )
}
