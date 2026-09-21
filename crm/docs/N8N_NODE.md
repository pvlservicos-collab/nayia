# ⚙️ Integração n8n: n8n-nodes-atlaseye

**Data:** 2026-03-12 | **Versão do Pacote:** 1.2.8

Este documento fornece um guia para usar o **Community Node oficial do Atlas Eye CRM** no [n8n](https://n8n.io/).

O Node interage diretamente com as rotas REST (`/api/*`) do CRM e suporta autenticação via Bearer Token (gerado no painel da Organização).

---

## 🚀 Instalação

Dentro da sua instância n8n, vá em **Configurações > Community Nodes** e instale:

`n8n-nodes-atlaseye`

*(A versão mais recente resolve o suporte a campos dinâmicos, pipelines, custom fields e suporte para tags)*.

---

## 🔐 Autenticação (Credentials)

Crie uma nova credencial no n8n do tipo **Atlas Eye API**.
- **Base URL:** A URL de produção da sua API (ex: `https://seu-dominio.com/api`)
- **API Token:** Seu token JWT Bearer, começando com `atl_` (gerado na tela de Settings do Atlas Eye).

> O n8n usará este token em todas as requisições. O backend lerá o cabeçalho, realizará hash (SHA-256) e validará se a OrganizationID corresponde, retornando unicamente dados do seu Tenant.

---

## 🧩 Recursos e Operações Disponíveis

O nó é dividido pelos principais recursos ("Resources") do CRM:

### 1. Lead
Operações core em contatos/oportunidades no CRM.

* **Check Exists:** Retorna verdadeiro/falso se um lead com aquele telefone ou ID já existe no Kanban. Muito útil para dividir fluxos no bot (IF Node).
* **Create/Upsert:** Cria um lead. Se o Lead já existir (via telefone idêntico), ele é anexado. Pode receber campos base como `title`, `phone`, `email` e a origem da conversa `source`. Se especificado, uma mensagem inicial de Histórico é escrita.
* **Get:** Buscar os detalhes e timeline de um lead específico.
* **Update:** Onde você move fisicamente o lead em colunas. Selecione o Pipeline e o novo Estágio (`stage_id`) onde o lead deve estar.
* **Add Message:** Anexa uma mensagem direta extraída do WhatsApp na aba "Atividades" da UI. Aceita `whatsapp` (mensagens de texto do bot ou cliente) ou `note` (eventos ocultos ao Lead, lidos pela IA/staff).

### 2. Custom Fields (Anexo a Lead)
Os Custom Fields dinâmicos gerados pelos usuários na interface estão disponíveis como dropdowns.
- Ao usar opções do Lead -> **Custom Fields**, o seu n8n buscará via API a listagem total de atributos personalizados disponíveis para sua organização (ex: "CPF do Cliente", "Nível de Risco") em tempo-real.

### 3. Pipeline / Stages
O n8n pode reagir a qualitativos. Se houver uma lógica pesada de "Lost Deals" ou envio de pesquisa NPS, o Workflow pode mover leads de Estágio massivamente em laço (Looping). O input de ID de estágios no nó fornece as opções via API Load Methods.

### 4. Notifications
Ferramenta para envio prático de alertas push na UI para a tela `(authenticated)/notifications` se o lead ficou muito tempo na tela de "Aguardando", por exemplo.

---

## 💡 Modelos de Automação Frequentes

### Padrão 1: Recepção de Leads (Chatbot -> CRM)
1. **Webhook Inbound** (n8n capta WhatsApp API Oficial ou Z-API/Evolution)
2. **Atlas Eye (Lead): Check Exists**
   - *If `false`:* Node Atlas Eye -> **Create** (Preenche pipeline de Entrada).
   - *If `true`:* Node Atlas Eye -> **Add Message** (Descreve o que o usuário quer no histórico sem duplicar o cartão Kanban).

### Padrão 2: Automação Pós-Atendimento
1. **Trigger de Tempo** ou Recebimento de Tag de "Fechamento" do Gateway de Pagamento
2. **Atlas Eye (Lead) -> Update** -> Move lead forçadamente de "Em negociação" para "Ganho".
3. **Atlas Eye (Notification)** -> Emite notificação de sucesso aos vendedores na plataforma.

---

> **Depuração:** Em caso de erro "Unauthorized", verifique em `Settings > Integrations > API Tokens` no CRM se o Token `atl_...` não foi revogado.
