# 🧪 Testing Guide — Atlas Eye CRM

**Status:** Aplicação rodando em http://localhost:3001
**Última atualização:** 2026-02-18 11:30 UTC

---

## 🌐 Acessar a Aplicação

### URLs Principais

```
Home:     http://localhost:3001
Pipeline: http://localhost:3001/pipeline
Chat:     http://localhost:3001/chat
```

**Copie e cole no navegador:**
```
http://localhost:3001/pipeline
```

---

## 📋 Teste 1: Verificar Home Page

### Passos
1. Abra http://localhost:3001
2. Verifique o título "Atlas Eye CRM"
3. Verifique os botões "📊 Pipeline" e "💬 Chats"
4. Clique em um botão para ir para a página

### Esperado
- ✅ Página carrega sem erros
- ✅ Título visível
- ✅ Botões são clicáveis
- ✅ Navegação funciona

### Debugging
- Abra DevTools: F12
- Veja a aba "Console"
- Procure por erros em vermelho
- Se houver: leia a mensagem de erro

---

## 🎯 Teste 2: Pipeline Board

### Passos
1. Abra http://localhost:3001/pipeline
2. Aguarde carregamento (1-2 segundos)
3. Verifique o layout

### Esperado
- ✅ Cabeçalho com dropdown de pipeline
- ✅ Botão "+ Novo Lead" amarelo
- ✅ Colunas de estágios (se houver dados)
- ✅ Cards de leads com informações

### Visual Check
```
┌─────────────────────────────────────┐
│ [Pipeline ▼] [+ Novo Lead]         │  ← Header
├─────────────────────────────────────┤
│ Novo(5) │ Qualif│ Proposta│ Fechado│  ← Stages
│         │       │         │        │
│ [Card]  │ [Card]│ [Card]  │ Empty  │  ← Lead Cards
│ [Card]  │       │         │        │
└─────────────────────────────────────┘
```

### Se Não Ver Nada
1. Verifique Console (F12) para erros
2. Verifique se há dados no Supabase
3. Verifique .env.local tem credenciais
4. Veja Supabase Dashboard → dados reais

### Cores Esperadas
- Amarelo: #f9f506 (botão, destaque)
- Branco: #ffffff (background)
- Cinza: #e5e7eb (borders)

---

## 💬 Teste 3: Chat Interface

### Passos
1. Abra http://localhost:3001/chat
2. Aguarde carregamento
3. Verifique o layout

### Esperado
```
┌──────────────────┬─────────────────────┐
│  Chats           │  Chat Window        │
│                  │                     │
│ 👤 Lead 1   10m  │ Header              │
│ 👤 Lead 2    2h  │ Timeline            │
│ 👤 Lead 3    1d  │ (messages)          │
│                  │                     │
│                  │ Composer            │
└──────────────────┴─────────────────────┘
```

### Componentes
- **Esquerda:** Lista de leads (1/3 width)
- **Direita:** Chat window (2/3 width)

### Verificar
- ✅ Lead list mostrando
- ✅ Avatar amarelo com iniciais
- ✅ Timestamps relativos
- ✅ Chat window à direita
- ✅ Type selector buttons (💬 📝 📞 📧)

### Se Não Funcionar
1. Verifique console para erros
2. Verifique se há leads no Supabase
3. Clique em um lead para selecionar
4. Verifique se timeline carrega

---

## 🔍 Teste 4: Real-time (Avançado)

### Setup
1. Abra http://localhost:3001/chat em **2 abas do navegador**
2. DevTools em ambas as abas (F12)
3. Vá para Network → WS (WebSocket)

### Teste
1. Na aba 1: Digite mensagem no composer
2. Clique "Enviar" (botão ➤)
3. Observe a aba 2

### Esperado
- ✅ Mensagem aparece na aba 2 em < 1 segundo
- ✅ Sem reload de página
- ✅ WebSocket ativo (status 101 Switching Protocols)
- ✅ Console sem erros

### Se Não Funcionar
1. Verifique WebSocket conectado: DevTools → Network → WS
2. Procure por erros: Console → vermelho
3. Verifique Realtime ativo no Supabase:
   - Database → Replication → Tables
   - Verifique "lead_activities" tem realtime ON

---

## 📊 Teste 5: Dados Supabase

### Verificar Conexão
1. Abra Supabase Dashboard
2. Vá para seu projeto: https://app.supabase.com
3. Verifique tabelas:
   - pipelines (deve ter ≥1 pipeline)
   - leads (deve ter ≥1 lead)
   - lead_activities (pode estar vazio)

### No Navegador
1. Abra http://localhost:3001/pipeline
2. Abra Console (F12 → Console)
3. Procure por logs como:
   ```
   "Leads loaded: 5"
   "Pipeline fetched: Sales Pipeline"
   ```

### Se Vazio
1. Verifique se há dados no Supabase
2. Execute queries test:
   ```sql
   SELECT COUNT(*) FROM pipelines;
   SELECT COUNT(*) FROM leads;
   ```
3. Se 0, adicione dados de teste

---

## 🐛 Teste 6: Debugging

### Console Log
```javascript
// No console do navegador (F12), teste:

// Verificar ambiente
console.log(process.env.NEXT_PUBLIC_SUPABASE_URL)
// Deve mostrar: https://hklfcfadultzuhwgkqmz.supabase.co

// Verificar client
import { supabase } from '@/lib/supabase'
supabase.auth.getSession().then(r => console.log(r))
```

### Network Tab
1. F12 → Network
2. Recarregue a página
3. Procure por requisições:
   - `/api/rest/v1/*` (Supabase API calls)
   - `ws://` ou `wss://` (WebSocket)

### Performance
1. F12 → Performance
2. Clique "Record"
3. Interaja com a página
4. Clique "Stop"
5. Analise os tempos

---

## ✅ Checklist Rápido

### Visuais
- [ ] Home page carrega
- [ ] Pipeline page carrega
- [ ] Chat page carrega
- [ ] Cores corretas (amarelo #f9f506)
- [ ] Fontes legíveis
- [ ] Botões clicáveis

### Funcionalidade
- [ ] Pode navegar entre páginas
- [ ] Dados carregam do Supabase
- [ ] Sem erros no console
- [ ] Real-time funciona (se testar)

### Performance
- [ ] Página carrega em < 2s
- [ ] Sem lag na interação
- [ ] WebSocket conectado
- [ ] Nenhum erro de rede

---

## 🔧 Troubleshooting Rápido

| Problema | Solução |
|----------|---------|
| Página em branco | F12 console → procurar erro |
| Sem dados visíveis | Verificar se há dados no Supabase |
| Erro 404 | Verificar URL está correta |
| Erro de auth | Verificar .env.local tem credenciais |
| Port 3001 em uso | `npm run dev -- -p 3002` |
| WebSocket não conecta | Verificar Realtime ativo no Supabase |

---

## 📱 Teste 7: Responsiveness

### Teste em Diferentes Tamanhos
1. F12 → Ctrl+Shift+M (Responsive Mode)
2. Selecione diferentes devices:
   - iPhone 12 (390x844)
   - iPad (768x1024)
   - Desktop (1920x1080)

### Esperado
- ✅ Layout se adapta
- ✅ Sem overflow horizontal
- ✅ Texto legível
- ✅ Botões clicáveis

---

## 🎯 Teste 8: Interatividade

### Pipeline Page
1. [ ] Clique no dropdown de pipeline
2. [ ] Selecione outro pipeline
3. [ ] Estágios mudam
4. [ ] Leads reorganizam

### Chat Page
1. [ ] Clique em um lead na lista
2. [ ] Chat window atualiza
3. [ ] Digite mensagem
4. [ ] Envie (Enter ou botão)
5. [ ] Mensagem aparece na timeline

---

## 📝 Teste 9: Forms e Input

### Composer
1. Clique no input "Escrever mensagem..."
2. Digite texto
3. Verifique:
   - [ ] Texto aparece enquanto digita
   - [ ] Cursor visível
   - [ ] Placeholder desaparece
   - [ ] Botão enviar se habilita

### Type Selector
1. Clique em "💬 WhatsApp"
2. Clique em "📝 Nota"
3. Clique em "📞 Ligação"
4. Verifique: estilo muda (amarelo quando selecionado)

---

## 🧹 Limpeza Pós-Testes

Se quiser resetar:
```bash
# Parar servidor
Ctrl+C

# Limpar cache
rm -rf .next

# Reiniciar
npm run dev
```

---

## 📊 Relatório de Teste

### Template
Salve em `TEST_REPORT.md`:

```markdown
# Test Report - [Data]

## Visual Tests
- [ ] Home loads
- [ ] Pipeline loads
- [ ] Chat loads
- [ ] Colors correct

## Functional Tests
- [ ] Navigation works
- [ ] Data loads
- [ ] No console errors
- [ ] Realtime works

## Performance
- [ ] < 2s load time
- [ ] No lag
- [ ] WebSocket active
- [ ] No network errors

## Notes
- [Qualquer observação adicional]

## Status: PASS / FAIL
```

---

## 🚀 Próximos Testes

### User Testing
- [ ] Fazer testes com usuários reais
- [ ] Coletar feedback
- [ ] Priorizar melhorias

### Load Testing
- [ ] Testar com muitos leads
- [ ] Testar com muitos usuários
- [ ] Medir performance

### Security Testing
- [ ] Testar RLS policies
- [ ] Testar auth workflows
- [ ] Testar data isolation

---

## 📞 Se Tiver Problemas

1. **Verifique erros:**
   ```
   DevTools (F12) → Console
   ```

2. **Veja logs do servidor:**
   ```
   Terminal onde npm run dev está rodando
   ```

3. **Verifique Supabase:**
   ```
   https://app.supabase.com → Seu projeto → Logs
   ```

4. **Leia documentação:**
   - QUICKSTART.md
   - SETUP.md
   - STATUS.md

---

**Happy Testing! 🎉**

Tempo estimado: 15-20 minutos
Próximo: Report issues ou passe para produção!
