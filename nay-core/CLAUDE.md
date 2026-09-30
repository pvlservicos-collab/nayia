# nay-core: onde eu mudo X

Núcleo novo da Nay. Roda em **sombra**: recebe cópia do que chega, decide a
resposta, grava em `core_saida` (estado sempre `simulado`) e **não envia nada**.
O sistema velho (n8n + funções `nai_*`) continua atendendo e **não é tocado**.
Antes de mexer, leia `docs/PROGRESSO.md` (onde paramos) e `docs/DECISOES.md`.

## Os princípios (não negociáveis)
1. O modelo **não decide caminho e não afirma fato**: só classifica num JSON
   fechado e escreve `{frase_de_ligacao}` em volta de texto pronto.
2. Imóvel só entra na resposta se saiu de ferramenta **deste turno**. O
   validador veta e devolve ao modelo **uma vez**; nunca substitui texto, nunca
   acrescenta card ou foto sozinho.
3. Estado é **dado gravado** em `core_conversa`, nunca regex sobre o que ela enviou.
4. Frase é `.md`, regra é linha de YAML, ordem de filtro é lista.
5. **Git é a produção.** Migração é arquivo numerado + `core_migracao`.
6. Toda regra tem teste; `make test` sem rede e em menos de 60 s.
7. Arquivo até 300 linhas, função até 60 (`make lint` confere).

## Para mudar...
| o quê | edite | teste |
|---|---|---|
| uma frase que ela diz | `nay/compositor/templates/<estado>_<acao>.md` | caso em `tests/casos/` que contém a frase |
| o jeito de falar (persona) | `nay/compositor/persona.md` | `tests/unit/compositor` |
| uma regra de validação | uma linha em `nay/validador/regras.yaml` (id, onde, tipo, acao_ao_vetar, teste) | o caso nomeado no campo `teste` |
| a ordem dos filtros | `ORDEM_FILTROS` em `nay/estado/maquina.py` | `tests/unit/estado` |
| uma transição da conversa | `nay/estado/maquina.py` (função pura) | caso de conversa em `tests/casos/` |
| um apelido (PN = Ponta Negra) | `nay/cerebro/apelidos.yaml` | `tests/unit/cerebro` |
| o que conta como ofertável, tipo, mobília, zona | a view `core_imovel_busca` numa **migração nova** | `tests/unit/cerebro` |
| o dono do imóvel | a view `core_imovel_dono` numa **migração nova** | `tests/unit/cerebro` |
| o que o classificador extrai | `nay/classificador/schema.py` + `prompt.md` + regravar fixtures | `tests/unit/classificador` |
| o modelo | `.env`: `LLM_CLASSIFICADOR`, `LLM_COMPOSITOR`, `LLM_RESERVA` | `make replay` antes e depois |
| uma tabela `core_*` | `migrations/NNN_nome.sql` novo (**nunca** editar um aplicado) | `make migrar-ensaio` |

## Onde cada coisa acontece (um setor por pasta)
`entrada` (webhook 200 em < 50 ms, dedupe, rajada de 20 s no worker, mídia de
TODAS as mensagens) → `identidade` (chave sem `@lid`, irmãos, papel) →
`contexto` (imóvel em jogo: citação > código literal > card colado > foco;
nunca por nome de bairro) → `roteador/pre.py` (**o que não precisa de
consulta sai aqui**: cortesia, só código, comando, foto do imóvel já
resolvido) → `classificador` → `estado` → `ferramentas` (devolvem os códigos
que autorizam) → `compositor` → `validador` → `saida` → `trace`.
O orquestrador é `nay/turno.py`; o worker é `nay/worker.py`.

## Banco
Mesmo `naydb`. **Lê** as tabelas do velho (imoveis, imovel_fotos, imovel_ficha,
corretores, identidade_lid, proprietarios, bairro_zona, bairro_vizinho,
condominios, mv_vocabulario_nomes, nai_turno, nai_saida, mensagens, envios).
**Escreve só em `core_*`.** O imóvel é lido de duas visões materializadas
(migração 005), atualizadas pelo worker a cada 10 min:
- `core_imovel_busca`: tipo, finalidade, zona, mobília, fotos, `ofertavel` e
  `no_mercado` calculados uma vez, com índice. Toda busca lê daqui.
- `core_imovel_dono`: o dono por `imoveis.proprietario_id` (depois
  `imovel_privado`, depois o admin com um dono só), com `mesmo_telefone_em`.
Função de extensão sempre qualificada (`public.unaccent('public.unaccent'::regdictionary, x)`):
o `pg_restore` roda com search_path vazio.

## Comandos
`make test` · `make lint` · `make migrar-ensaio` · `make migrar` ·
`make deploy` · `make rollback` · `make replay` · `make comparar` · `make violacoes`.
Deploy só pelo `make deploy` (git pull → testes → migração → container →
healthcheck). O que não está no git não está em produção.

## Não faça
- Não escreva em tabela que não comece com `core_`.
- Não afrouxe o `CHECK (estado = 'simulado')` de `core_saida` sem uma decisão
  do Tel registrada em `docs/DECISOES.md` e uma migração própria.
- Não copie o prompt v16 inteiro: só a seção "COMO VOCÊ FALA" vira persona.
- Não chute regra de negócio: registre "pendente do Tel" em DECISOES.md,
  siga com a sugestão e avise.
