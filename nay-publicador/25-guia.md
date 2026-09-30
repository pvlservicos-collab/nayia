# 25 — Varredura do catálogo: passo a passo completo

*Escrito em 21/08/2026. Todos os dados aqui foram verificados no site e no banco, não supostos.*

---

## Por que isso é o item número 1

A base da Nay está **congelada em 10/08/2026**. Todos os 1.172 imóveis têm `sincronizado_em` daquele dia, entre 20:17 e 20:33. Nunca mais rodou.

Enquanto isso não for resolvido, ela oferece imóvel vendido com valor antigo e desconhece tudo cadastrado depois. Tirar a trava antes disso é entregar catálogo velho para 1.050 corretores.

## Fatos confirmados sobre o site público

| Item | Valor |
|---|---|
| Listagem de venda | `?ad_type=Venda&page=N` — **67 páginas** |
| Listagem de aluguel | `?ad_type=Aluguel&page=N` — **8 páginas** |
| Por página | 12 anúncios |
| Total publicado | **~900** |
| Total no banco | **1.172** |
| **Diferença** | **~270 disponíveis sem anúncio** |
| Página do imóvel | `imobeasy.com/anuncios/<codigo>` |
| Link na listagem | `imobeasy.com/imoveis/<codigo>` |

**Sem login.** O site público não exige autenticação.

### O que a listagem entrega, por imóvel

Código (no link) · **`Imóvel Parceiro`** (texto e ícone `partner-sm-*.svg`) · condomínio · endereço · bairro · complemento · área · quartos · suítes · banheiros · garagem · valor de venda · valor de aluguel · marcadores como "Decorado".

Quando o imóvel tem venda **e** aluguel, os dois valores aparecem mesmo no filtro de venda.

### O que a página do anúncio entrega a mais

Sol · andar · taxa de condomínio · IPTU · aceita permuta · aceita financiamento · mobília · características do imóvel e do condomínio · descrição · observações · **todas as fotos em alta resolução**.

### O que o site NÃO entrega

- Contato do proprietário — só o admin tem
- `captado_por` nominal — só a marca genérica de parceiro
- Campos internos: `bloqueado`, `travado`, `motivo_bloqueio`
- **Imóveis disponíveis sem anúncio publicado** — os ~270 não aparecem

## Ferramenta

**Claude Code dentro do VS Code.** A saída é um script Python que roda no servidor por cron. É código versionado, testável contra 3 páginas antes de rodar contra 75, e cada mudança vira commit.

O script **não roda na sua máquina** — ele é escrito lá e executado no servidor, onde o banco está.

---

# PARTE 1 — Preparar o ambiente (uma vez só)

**1.1** Instale o VS Code: https://code.visualstudio.com/

**1.2** No VS Code, tecle `Cmd+Shift+X`, procure **Claude Code** (publisher Anthropic) e instale.

**1.3** Abra o painel do Claude e faça login. Se reclamar de "CLI not found", instale o Node.js 18+ em https://nodejs.org e rode:
```
npm install -g @anthropic-ai/claude-code
```

**1.4** No terminal do Mac:
```
mkdir -p ~/projetos/nay-catalogo && cd ~/projetos/nay-catalogo && git init
```

**1.5** No VS Code: **File → Open Folder** → selecione `~/projetos/nay-catalogo`.

---

# PARTE 2 — O arquivo de contexto

Crie na raiz um arquivo `CLAUDE.md` com este conteúdo. É lido em toda conversa e evita reexplicar tudo.

````markdown
# Varredura do catálogo Imob Easy

## Objetivo
Ler o site público da Imob Easy e atualizar a tabela `imoveis` do banco `naydb`,
sem apagar nada. Modo COMPLEMENTAR, nunca substitutivo.

## Fonte
- Venda: https://imobeasy.com/anuncios?ad_type=Venda&page=N  (67 páginas)
- Aluguel: https://imobeasy.com/anuncios?ad_type=Aluguel&page=N (8 páginas)
- Anúncio: https://imobeasy.com/anuncios/<codigo>
- Sem login. 12 anúncios por página.

## Como identificar cada coisa
- Código: no link `/imoveis/<codigo>` de cada card
- Parceiro: o card contém o texto `Imóvel Parceiro` ou o ícone `partner-sm-`
- Valores: linhas `Venda: R$ ...` e `Aluguel: R$ ...`, podem aparecer as duas

## Banco
PostgreSQL 16 em container Docker `nay-postgres`, usuário `nay`, banco `naydb`.
Acesso no servidor: `docker exec nay-postgres psql -U nay -d naydb -c "QUERY"`

Colunas relevantes de `imoveis`: codigo, tipo, status, condominio_nome, bairro,
logradouro, complemento, area_util, area_total, quartos, suites, banheiros,
vagas, vagas_cobertas, sol, andar, valor_venda, valor_aluguel, taxa_condominio,
iptu, mobilia, descricao, caracteristicas, origem, publicado_no_site, disponivel,
bloqueado, motivo_bloqueio, sincronizado_em, criado_em, e_parceiro, travado,
travado_motivo, travado_em, extras, captado_por, captado_em

Fotos ficam em `imovel_fotos`: codigo, ordem, url, e_capa, e_fachada.

## Regras que não podem ser violadas
1. **Nunca apagar linha de `imoveis`.** Só atualizar ou marcar.
2. O que existe no banco e não aparece no site vira `publicado_no_site = false`.
   NÃO vira indisponível — pode estar disponível no admin sem anúncio.
3. Sempre gravar `sincronizado_em = now()` no que foi tocado.
4. Rodar em modo simulação por padrão. Só escrever no banco com flag explícita.
5. Pausa de 1 a 2 segundos entre requisições. Não martelar o site.
6. Nenhuma credencial em código. Tudo por variável de ambiente.

## Como trabalhar comigo
- Teste contra 3 páginas antes de propor rodar contra 75
- Não afirme que funciona sem ter rodado
- Uma etapa por vez, com commit ao fim de cada uma
````

---

# PARTE 3 — Os prompts, um de cada vez

Cole cada um no Claude Code. **Só passe ao seguinte depois de testar o anterior.**

## Prompt 1 — Ler uma página

```
Leia o CLAUDE.md.

Escreva um script Python que baixe UMA página da listagem de venda e extraia,
para cada um dos 12 anúncios: codigo, se e_parceiro, condominio, endereco,
bairro, complemento, area, quartos, suites, banheiros, vagas, valor_venda,
valor_aluguel.

Rode contra a página 2 e me mostre o resultado em tabela.
Não toque em banco nenhum ainda.
```

## Prompt 2 — Conferir contra o que eu sei

```
Rode agora contra a página 1 de aluguel e me mostre o resultado.

Eu conferi manualmente: nessa página, 8 dos 12 são Imóvel Parceiro, e o
imóvel 5611 é Condomínio Acquarelle, 88 m2, 3 quartos, aluguel 4.600.

Compare com o que seu script extraiu e me diga onde diverge.
```

## Prompt 3 — Varrer tudo, sem gravar

```
Agora varra as 67 páginas de venda e as 8 de aluguel, com pausa de 1 a 2
segundos entre requisições. Guarde tudo num arquivo catalogo.json.

Me mostre no fim: quantos anúncios ao todo, quantos de parceiro, quantos
códigos repetidos entre venda e aluguel, e quantas páginas falharam.

Não escreva no banco.
```

## Prompt 4 — Comparar com o banco

```
Escreva um script que compare catalogo.json com a tabela `imoveis` e produza
um relatório, SEM escrever nada:

- quantos códigos do site existem no banco
- quantos códigos do site NÃO existem no banco (imóveis novos desde 10/08)
- quantos códigos do banco não aparecem no site (os ~270 sem anúncio)
- quantos têm valor diferente entre site e banco, listando os 20 maiores desvios
- quantos têm e_parceiro diferente entre site e banco

Como o banco está no servidor e não na minha máquina, o script deve aceitar
uma exportação da tabela em CSV como entrada. Me diga o comando exato para
eu gerar esse CSV no servidor.
```

## Prompt 5 — Gerar o SQL de atualização

```
Gere o SQL que aplica as atualizações, seguindo as regras do CLAUDE.md:

- UPDATE nos que existem nos dois lados, com sincronizado_em = now()
- INSERT nos que estão no site e não no banco
- UPDATE publicado_no_site = false nos que estão no banco e não no site
- NENHUM DELETE

Salve em atualiza.sql. Me mostre as 30 primeiras linhas e o total de comandos.
```

## Prompt 6 — Empacotar para o servidor

```
Prepare tudo para rodar direto no servidor:
- um script único que faz varredura, comparação e atualização
- flag --simular (padrão) e --aplicar
- log do que mudou, com data
- README com o comando exato para rodar e para agendar no cron semanal

Me diga como copiar isso para o servidor.
```

---

# PARTE 4 — Executar no servidor

**4.1** Abra o terminal: https://hpanel.hostinger.com/ → VPS → **srv1894338** → botão **Terminal**

**4.2** **Faça backup antes de qualquer escrita:**
```
docker exec nay-postgres pg_dump -U nay -d naydb -t imoveis > /root/imoveis_antes.sql && wc -l /root/imoveis_antes.sql
```

**4.3** Rode em **modo simulação** primeiro. O script deve dizer quantas linhas seriam alteradas, sem alterar nenhuma.

**4.4** Confira o relatório. Se o número de alterações for absurdo — tipo 1.000 de 1.172 —, **pare**. Alguma coisa está errada na extração.

**4.5** Só então rode com `--aplicar`.

**4.6** Confirme:
```
docker exec nay-postgres psql -U nay -d naydb -c "SELECT count(*) total, count(*) FILTER (WHERE sincronizado_em > now() - interval '1 hour') atualizados, count(*) FILTER (WHERE NOT publicado_no_site) sem_anuncio FROM imoveis;"
```

**4.7** Teste na Nay pelo WhatsApp: `me manda o 2539` e um imóvel que você saiba que mudou depois de 10/08.

---

# PARTE 5 — Depois que rodar

**5.1 Agendar.** Cron semanal no servidor. Enquanto for manual, vira tarefa esquecida.

**5.2 A lista dos ~270.** Depois da varredura, o comando abaixo entrega o que você pediu — disponíveis no admin sem anúncio no site:
```
docker exec nay-postgres psql -U nay -d naydb -c "SELECT codigo, condominio_nome, bairro, valor_venda, valor_aluguel FROM imoveis WHERE disponivel AND NOT publicado_no_site ORDER BY codigo;"
```

**5.3 A decisão do parceiro.** Com a base atualizada, aí sim faz sentido decidir se bloqueia os de parceria — com número certo, não com dado de 11 dias atrás.

---

# PARTE 6 — Riscos

**A extração pode errar em silêncio.** Se o site mudar de layout, o script traz dado errado sem avisar. Por isso o Prompt 2 existe: conferir contra caso que você conhece. E por isso o passo 4.4: número absurdo é sinal de erro, não de sucesso.

**O site pode barrar por volume.** 75 requisições seguidas. A pausa de 1 a 2 segundos existe para isso. Se der bloqueio, aumentar a pausa.

**Os ~270 sem anúncio continuam sem solução.** O site público não os mostra. Para eles, só o admin ou a API de setembro.

**Backup é obrigatório.** O passo 4.2 não é opcional. É a única forma de voltar se a varredura gravar errado.