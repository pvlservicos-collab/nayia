# Atlas Eye Design System

Este documento define as diretrizes visuais e semânticas para o UX da plataforma Atlas Eye.

## 🎨 Paleta de Cores e Proporções

| Cor | Hex | Proporção | Função Semântica |
| :--- | :--- | :--- | :--- |
| **Background Light** | `#F6F9FF` | 25% | Fundo principal, superfícies de dashboard (com `dot-grid`). |
| **Midnight Navy** | `#0A0F21` | 25% | Texto primário, header de navegação, ícones de alto contraste. |
| **Electric Blue** | `#115AF8` | 25% | **Cores de Ação**: Botões primários, CTAs principais, links ativos. |
| **Violet** | `#4B3BFD` | 15% | **Agente (Atlas AI)**: Mensagens enviada pela IA, badges de status de IA. |
| **Ice Blue** | `#21BCED` | 9% | **Usuário**: Bolhas de mensagem do usuário. |
| **Metallic Grey** | `#97A1B3` | 1% | **Detalhes**: Degradês sutis, bordas 3D, sombras. |
| **Danger** | `#FF4C4C` | - | **Erro**: Ações destrutivas, falhas críticas, exclusão. |
| **Success** | `#00C896` | - | **Sucesso**: Confirmações, estados positivos, validação. |
| **Warning** | `#FFB100` | - | **Aviso**: Alertas, atenção necessária, estados pendentes. |

---

## 🔡 Tipografia

A tipografia do Atlas Eye combina a personalidade moderna da **Darker Grotesque** com a clareza técnica da **Neue Haas**.

- **Primária**: `Darker Grotesque` (Google Fonts)
  - *Uso*: Títulos, Números de destaque (Kpis), Headers de Pipeline.
- **Secundária**: `Neue Haas Grotesk Display Pro` (Local/Licensed)
  - *Uso*: Textos de corpo, Chat, Metadados, Labels de formulário.

### Escala Tipográfica
- **H1 (Display)**: `32px` / Bold (Darker Grotesque)
- **H2 (Section header)**: `24px` / SemiBold (Darker Grotesque)
- **H3 (Column header)**: `20px` / Medium (Darker Grotesque)
- **Body**: `16px` / Regular (Neue Haas)
- **Small (Caption)**: `14px` / Regular (Neue Haas)

---

## 📐 Layout e Espaçamento

- **Grid Base**: 4px baseline grid (incrementos de `0.25rem`).
- **Gaps**:
  - `4px` (Smallest)
  - `8px` (Small)
  - `16px` (Default/Between cards)
  - `24px` (Between columns)

---

## 🏁 Cantos (Border Radius)

Seguindo o visual "suave" do Atlas Eye:

- **24px (`rounded-3xl`)**: Containers principais (Chat wrapper, Dashboard bg).
- **16px (`rounded-2xl`)**: Cartões de Lead (Pipeline cards).
- **12px (`rounded-xl`)**: Mensagens, Inputs de busca.
- **8px (`rounded-lg`)**: Tags secundárias.
- **Full (`rounded-full`)**: Botões pills, Badges de notificação, Avatares.

---

## 🧩 Componentes Chave

### Botões
- **Primário**: Background `#115AF8`, Texto Branco, Rounding `rounded-full`.
- **Secundário**: Outline ou Background suave `#F6F9FF`, Texto `#0A0F21`.

### Chat
- **Mensagem Atlas AI**: Background `#4B3BFD` (ou tint 10%), Texto Branco/Escuro conforme contraste.
- **Mensagem Usuário**: Background `#21BCED`, Texto Branco.
- **Padrão de Fundo**: Cor `#F6F9FF` com overlay de gradiente radial de pontos (`dot-pattern`).

### Pipeline
- **Cartão de Lead**: Background Branco, top-border (3px) com cor temática da etapa, sombra suave (`shadow-sm`).

---

## 🎨 Iconografia (Phosphor Icons)

Para manter a consistência visual, utilizamos a biblioteca **Phosphor Icons**.

- **Estilo Padrão**: `Regular` (espessura equilibrada para interface limpa).
- **Estilo de Destaque**: `Bold` ou `Fill` para estados ativos, erros críticos ou botões de alta prioridade.
- **Tamanhos**:
  - `20px`: Desktop padrão (dashboard, menus).
  - `16px`: Tags, metadados, botões pequenos.
  - `24px`: Cabeçalhos de seção e ações principais.
