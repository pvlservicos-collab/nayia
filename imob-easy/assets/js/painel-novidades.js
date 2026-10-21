/* NOVIDADES DOS ÚLTIMOS 30 DIAS (Pedro, 16/10/2026: "separe todas as ações novas que fizemos nos últimos 30 dias de
   forma organizada, e com leves tags de cor para facilitar a visualização para um humano").
   Tirado do histórico do repositório (git log) e das migrações. Quando entrar coisa nova no ar, acrescente a linha aqui
   no mesmo commit: { d: data, a: área, t: o que é, x: o detalhe, n: migração }. O painel mostra só os últimos 30 dias. */
window.PAINEL_AREAS = {
  nay:      { rotulo: "Nay da Parceria", cor: "#b877d9" },
  captacao: { rotulo: "Captação",        cor: "#73bf69" },
  olx:      { rotulo: "OLX",             cor: "#ff9830" },
  visitas:  { rotulo: "Visitas",         cor: "#4fc4cf" },
  grupos:   { rotulo: "Grupos",          cor: "#8ab8ff" },
  disparos: { rotulo: "Disparos e Meta", cor: "#fade2a" },
  crm:      { rotulo: "CRM",             cor: "#5794f2" },
  site:     { rotulo: "Site e admin",    cor: "#e07bc4" },
  infra:    { rotulo: "Infra",           cor: "#9aa0ac" }
};

window.PAINEL_NOVIDADES = [
  { d: "2026-10-21", a: "infra", t: "Uso de recursos da VPS no Início", x: "CPU, memória e disco da VPS separados por função, em %, agora e na média de 24 h; medido a cada 5 min", n: "—" },
  { d: "2026-10-20", a: "nay", t: "Fila da revisão da Nay", x: "toda conversa em que a Nay envia imóvel vai, de 20 em 20 min, para o agente Nay Parceria (revisão); às 22h o relatório", n: "—" },
  { d: "2026-10-17", a: "site", t: "Painel de métricas no Início", x: "pessoas × visitas, por número, por dia/semana/mês, OLX, disparos, fechamentos", n: "399" },

  { d: "2026-10-16", a: "olx", t: "Nay do WhatsApp dos clientes da OLX (8595)", x: "abre já sabendo da conversa da OLX, segue o roteiro (valor, bairros, quartos), busca e manda as opções", n: "385–389" },
  { d: "2026-10-16", a: "captacao", t: "Lead orgânico no número de captação", x: "quem escreve pela primeira vez e não é dono, corretor nem equipe vira lead da Nay do WhatsApp; tag Orgânico no CRM", n: "390" },
  { d: "2026-10-16", a: "nay", t: "Fila de perguntas no PV do Tel", x: "o que a Nay não sabe vai uma por vez (Pergunta k/N), cobrada a cada 10 min; a resposta dele vai ao cliente", n: "391" },
  { d: "2026-10-16", a: "visitas", t: "Visita de locação chama o Diego primeiro", x: "venda só corretores; com o ok de um deles, o proprietário", n: "392" },
  { d: "2026-10-16", a: "olx", t: "Nay do WhatsApp revisada", x: "nunca repete pergunta, confirma o pedido uma vez só e volta com as opções; acompanhamento 10 min depois", n: "393–395" },
  { d: "2026-10-16", a: "olx", t: "Anunciar na OLX pelo Editar imóvel", x: "popup com o anúncio montado e editável, publicado pelo nay-olx", n: "396" },
  { d: "2026-10-16", a: "crm", t: "Enviar imóvel no card do lead da Captação", x: "um a um ou por faixa, sai pelo 8595 pela Nay do WhatsApp", n: "396" },
  { d: "2026-10-16", a: "disparos", t: "Contador da Meta na linha Oficial", x: "disparos, cobrados, gasto do mês e mensagens de serviço (grátis)" },
  { d: "2026-10-16", a: "crm", t: "Aba Proprietários da Captação", x: "junta também os donos do cadastro", n: "397" },
  { d: "2026-10-16", a: "crm", t: "Parar Nay cala também a Nay do WhatsApp", x: "e o Voltar solta na próxima mensagem; o card mostra o estado dela", n: "398" },
  { d: "2026-10-16", a: "site", t: "Vários bairros e condomínios na busca", x: "home, Comprar e Alugar: cada clique marca ou desmarca" },
  { d: "2026-10-16", a: "site", t: "Comprar, Alugar, página do imóvel e Editar no acabamento do site antigo" },
  { d: "2026-10-16", a: "grupos", t: "Captação ativa: o mesmo pedido vira um card só", x: "também reescrito e colado de novo; Enviar vários imóveis no card do pedido", n: "380–382" },
  { d: "2026-10-16", a: "olx", t: "Nay da OLX leva ao WhatsApp", x: "tira a dúvida no chat e pede o WhatsApp para mandar as informações", n: "384" },
  { d: "2026-10-16", a: "crm", t: "Chat OLX igual ao da OLX", x: "busca, Vendendo/Comprando, capa do anúncio, código e condomínio no topo", n: "378, 383" },
  { d: "2026-10-16", a: "site", t: "O site antigo manda no status", x: "88 status, 22 valores e 9 condomínios como estão no antigo", n: "377" },
  { d: "2026-10-16", a: "olx", t: "58 anúncios da lista do Tel enviados à OLX", x: "53 já publicados pela conta proprietários", n: "376" },
  { d: "2026-10-16", a: "visitas", t: "Detector de visitas avisa a Rayssa", x: "pus na agenda, mudou, tirei: vão também para o WhatsApp dela" },

  { d: "2026-10-15", a: "site", t: "Lembretes da equipe no sininho do admin", x: "texto + dia; abre sozinho até clicarem em Feito", n: "375" },
  { d: "2026-10-15", a: "olx", t: "Nay da OLX no ar no chat", x: "por etapas: dúvida, convite, nome e WhatsApp; visita vira aviso no grupo" },
  { d: "2026-10-15", a: "captacao", t: "Nay proprietários da OLX", x: "o dono que anunciou na OLX, com o roteiro próprio, pelo WhatsApp da Parceria", n: "370, 374" },
  { d: "2026-10-15", a: "grupos", t: "Mensagem de negociação no privado de quem pediu", x: "e o pedido que pede financiamento não recebe imóvel que não aceita", n: "371–373" },
  { d: "2026-10-15", a: "crm", t: "CRM não desloga mais por falha de rede", x: "o caso da Rayssa no celular" },
  { d: "2026-10-15", a: "site", t: "Visão geral do projeto", x: "o mapa das duas VPS e a jornada do lead" },

  { d: "2026-10-14", a: "olx", t: "Leads da OLX e métricas dos anúncios no CRM", x: "ordenável por coluna, com o saldo do plano", n: "369" },
  { d: "2026-10-14", a: "olx", t: "Primeiros anúncios pela integração", x: "o 3134 primeiro; depois 36 da lista do Tel", n: "366, 368" },
  { d: "2026-10-14", a: "nay", t: "O que a taxa de condomínio inclui", x: "segurança, água, gás, energia: na ficha e no popup; 330 fichas", n: "367" },
  { d: "2026-10-14", a: "disparos", t: "28 modelos novos de Utilidade na Meta", x: "confirmar_disponivel, retomar_janela e sistema_aviso" },
  { d: "2026-10-14", a: "crm", t: "Entrega de cada mensagem no chat", x: "enviando e entregue, Z-API e Meta" },

  { d: "2026-10-13", a: "olx", t: "OLX no automático", x: "o anúncio sobe do cadastro (nay-olx) e o webhook dos leads", n: "362–365" },
  { d: "2026-10-13", a: "captacao", t: "A resposta do dono muda o cadastro sozinha", x: "com histórico (Mudanças recentes) e volta", n: "361" },
  { d: "2026-10-13", a: "disparos", t: "Disparo oficial retomado", x: "listas 6 e 8; a barrinha mostra quanto de cada lista já saiu", n: "358–360" },
  { d: "2026-10-13", a: "site", t: "Home nova do site", x: "busca, destaques, mapa dos imóveis, parceria 50%" },
  { d: "2026-10-13", a: "crm", t: "Aba Oficial: quem escreveu sobe", x: "o disparo e a resposta da Nay não mexem na ordem" },

  { d: "2026-10-12", a: "disparos", t: "Garantias do disparo", x: "quem falou conosco em 60 dias fica fora; corretor não é proprietário", n: "351, 352" },
  { d: "2026-10-12", a: "disparos", t: "As listas do disparo pela API oficial", x: "151 donos das listas 6 e 8; janela até 19:00 de Manaus", n: "349–355" },
  { d: "2026-10-12", a: "site", t: "Modelos WhatsApp em balões com os botões", x: "Em uso / Outros, por categoria" },
  { d: "2026-10-12", a: "infra", t: "Regra de aviso e pergunta", x: "publicar para e avisa quando o servidor tem o que não é desta pasta" },

  { d: "2026-10-11", a: "nay", t: "Reforma do imóvel", x: "por tipo, mobília em 4 níveis, condomínio com ficha completa e sugestão da IA", n: "344–348" },
  { d: "2026-10-11", a: "site", t: "Página Agentes do admin", x: "um quadrado por agente, medido pelo uso da VPS" },
  { d: "2026-10-11", a: "disparos", t: "Modelos de Utilidade para os grupos", x: "l3, l4 e l5 enviados à Meta" },

  { d: "2026-10-10", a: "captacao", t: "Lista dos contratos a vencer", x: "para o modelo oficial; mobília corrigida no cadastro", n: "341–343" },
  { d: "2026-10-10", a: "crm", t: "O cadastro pelo CRM volta a gravar", n: "340" },
  { d: "2026-10-10", a: "grupos", t: "Captação ativa: envio manual pelo botão", x: "a nota do bairro cai com a distância", n: "339" },

  { d: "2026-10-09", a: "grupos", t: "Captação ativa por grupos", x: "os pedidos dos corretores viram cards (aba Grupos › Captação ativa)", n: "336–338" },
  { d: "2026-10-09", a: "crm", t: "Mensagem marcada aparece no chat", n: "335" },
  { d: "2026-10-09", a: "nay", t: "Aviso de imóvel que saiu só com o SIM do Tel", n: "334" },
  { d: "2026-10-09", a: "visitas", t: "Visita do dia que passou fecha sozinha", n: "333" },
  { d: "2026-10-09", a: "site", t: "Cadastro rápido", x: "uma fila só de todas as fontes, a ficha chega pronta, um clique cadastra", n: "326–332" },
  { d: "2026-10-09", a: "captacao", t: "Retomada pelo oficial", x: "quem recebeu pela Z-API e nunca respondeu entra no modelo oficial, uma vez", n: "323, 324" },

  { d: "2026-10-08", a: "captacao", t: "Nay de captação em Python", x: "pelo número oficial, um disparo por minuto", n: "315–318" },
  { d: "2026-10-08", a: "captacao", t: "A resposta da captação atualiza o cadastro", x: "e a indicação com a demanda", n: "320, 321" },
  { d: "2026-10-08", a: "site", t: "Cadastro de condomínio", x: "aba em Imóveis, no site e no CRM", n: "322" },
  { d: "2026-10-08", a: "crm", t: "Chat da OLX dentro do CRM", x: "uma aba por conta; menu sem Início e o + Mais", n: "313, 314" },

  { d: "2026-10-07", a: "nay", t: "Nay nova (nay-core) para todos os corretores", x: "nenhuma conversa de corretor passa mais pela Nay velha", n: "302–307" },
  { d: "2026-10-07", a: "captacao", t: "A captação só fala com proprietário", x: "corretor e parceiro ficam de fora", n: "308" },

  { d: "2026-10-06", a: "infra", t: "Enviador manual fora do n8n", x: "Enviar imóvel, Me envia e ENVIA não obedecem mais à pausa da Nay", n: "300, 301" },
  { d: "2026-10-06", a: "site", t: "Admin › Nova Nay: Treinamento", x: "Nay antiga e Nay nova lado a lado, marcar e rodar só as com erro" },
  { d: "2026-10-06", a: "site", t: "/imoveis redesenhado e mais rápido", x: "mapa, filtros, Me envia; gzip e cache" },
  { d: "2026-10-06", a: "nay", t: "Parede de parceria na Nay nova", n: "299" },

  { d: "2026-10-05", a: "crm", t: "Histórico de atendimento e imóveis já enviados no card", x: "tags Nay/Tel/Rayssa; visitas de hoje em diante", n: "290, 292, 293" },
  { d: "2026-10-05", a: "captacao", t: "A abertura nunca sai duas vezes ao mesmo dono", n: "291" },
  { d: "2026-10-05", a: "site", t: "Proprietários no admin", x: "Todos e Contratos a vencer; Comprar/Alugar com filtros de verdade", n: "296" },

  { d: "2026-10-04", a: "crm", t: "Aviso no celular e tela em tempo real" },

  { d: "2026-10-03", a: "grupos", t: "Agenda das mensagens nos grupos", x: "listas de imóveis, cores por grupo e a métrica de 6 h; CRM › Grupos", n: "279–286" },
  { d: "2026-10-03", a: "nay", t: "Marcou a foto do post e a Nay sabe o imóvel", n: "287" },
  { d: "2026-10-03", a: "nay", t: "Mensagem à mão pausa a Nay 30 min", x: "a conversa fica na aba dela", n: "288" },
  { d: "2026-10-03", a: "site", t: "Biblioteca de fotos do cadastro", x: "subir, reordenar e excluir", n: "283" },

  { d: "2026-10-02", a: "nay", t: "Nay nova ligada pela porta", x: "o núcleo novo atende corretor de fora; a equipe fica com a velha", n: "269, 270" },
  { d: "2026-10-02", a: "site", t: "Página pública do imóvel e /imoveis para se enviar", x: "o corretor acha o imóvel e se envia pelo WhatsApp", n: "271, 275" },
  { d: "2026-10-02", a: "infra", t: "Vigia do WhatsApp", x: "aviso no grupo quando o número cai, fila guardada e reenviada", n: "272" },
  { d: "2026-10-02", a: "site", t: "Condomínio cadastrado uma vez; a situação manda no anúncio", n: "273, 274" },
  { d: "2026-10-02", a: "crm", t: "Parar Nay / Voltar no card da captação" },

  { d: "2026-10-01", a: "visitas", t: "Agendar visita à mão no card", x: "lembrete 1 h antes; aviso de robô ao Tel", n: "250, 251" },
  { d: "2026-10-01", a: "site", t: "Aba CADASTRO PENDENTE e cadastro redesenhado", n: "248, 249" },
  { d: "2026-10-01", a: "nay", t: "Todo modelo de texto no gpt-6-luna", x: "a Nay não lê mais imagem; áudio sim" },
  { d: "2026-10-01", a: "infra", t: "Grokbot: consulta e cadastro de imóveis", x: "dois webhooks, dois tokens", n: "258–264" },

  { d: "2026-09-30", a: "nay", t: "Identificação por pedido, 90x mais rápida", x: "zona, conjuntos e avenidas ligados a cada imóvel", n: "229–241" },
  { d: "2026-09-30", a: "crm", t: "Aba Imóveis do CRM é a do site", x: "follow-up agendado no card; Nay atender com instrução", n: "235" },
  { d: "2026-09-30", a: "site", t: "Treinamento por pedido no Cérebro da Nay", n: "234" },
  { d: "2026-09-30", a: "infra", t: "scripts/nay e MAPA.md", x: "pedido → função, para mudar mais rápido" },

  { d: "2026-09-29", a: "nay", t: "nay-core: o esqueleto da Nay nova", x: "tabelas core_* e o modelo de leitura do imóvel" },
  { d: "2026-09-29", a: "infra", t: "Pausa, prompt e configuração da Nay pedem senha" },

  { d: "2026-09-28", a: "crm", t: "CRM em 3 abas", x: "Oficial, Parceria e Captação, um lead por linha" },
  { d: "2026-09-28", a: "site", t: "Aba Enviar imóvel (site e CRM)", x: "os dois chamam o mesmo /api/disparo" },
  { d: "2026-09-28", a: "nay", t: "Nay de Locação religada para todos", x: "arquitetura nova: etapas, ficha #código, status" },
  { d: "2026-09-28", a: "infra", t: "Catálogo raspado 1x por dia", x: "o site antigo às 05:17, não vem mais do .com" },

  { d: "2026-09-25", a: "crm", t: "Duas abas de WhatsApp: captação e parceria" },
  { d: "2026-09-25", a: "disparos", t: "Templates da Nay para a API oficial" },
  { d: "2026-09-24", a: "nay", t: "Jev no lugar da mente", x: "a decisão passa a ser número; bateria dos casos do Tel" },
  { d: "2026-09-23", a: "nay", t: "Pediu dois imóveis, recebe os dois", x: "cada um com o seu card e as suas fotos" },
  { d: "2026-09-22", a: "nay", t: "Mente mestra e Nay secretária", x: "venda não é aluguel, casa não é apartamento" },
  { d: "2026-09-20", a: "crm", t: "CRM no ar em crm.imobeasy.online", x: "na identidade da Imob Easy" },
  { d: "2026-09-19", a: "site", t: "Cérebro da Nay", x: "trace, setores, regras e o fluxograma das 44 etapas" }
];
