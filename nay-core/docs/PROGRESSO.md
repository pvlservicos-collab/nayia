# Progresso da entrega 1 (sombra)

A próxima sessão começa aqui. Marque [x] só o que tem teste verde.

## Sessão 1 (29/09/2026): esqueleto
- [x] Estrutura de pastas, um setor por pasta, com o contrato de cada módulo em docstring
- [x] CLAUDE.md ("onde eu mudo X"), README.md, DECISOES.md, este arquivo
- [x] pyproject, Makefile, Dockerfile, docker-compose.yml (nay-core + nay-core-worker), .env.example
- [x] Migrações 001 a 005 e scripts/migrar.py (core_migracao, md5, recusa arquivo editado)
- [x] Ensaio das 5 migrações no naydb vivo, em transação desfeita: aplicam, visões montam
      em < 0,1 s, REFRESH CONCURRENTLY em < 0,2 s, core_saida recusa estado != simulado
- [x] Modelo de leitura do imóvel (005): core_imovel_busca (249 ofertáveis, 259 no mercado,
      37 locação, 219 venda) e core_imovel_dono (36 das 37 locações com dono e telefone)
- [x] tests/unit/test_esqueleto.py e scripts/limites.py
- [ ] **Aguardando o Tel**: aprovar a estrutura; decidir as pendências de DECISOES.md;
      autorizar aplicar as migrações 001 a 005 no naydb (só cria objetos core_*)

## Próximas sessões, nesta ordem (cada uma com testes verdes antes da seguinte)
- [ ] entrada: webhook < 50 ms, dedupe, rajada 20 s no worker, mídia de todas as mensagens
- [ ] identidade: chave sem @lid, irmãos, papel
- [ ] contexto: imóvel em jogo (citação > código > card > foco); casos 12556, 12123, 12186, 12592
- [ ] pré-roteador: cortesia, só código, comando, foto do X
- [ ] cérebro: catálogo, bairros, apelidos.yaml, proprietário, ficha (21 assuntos)
- [ ] estado: máquina, ORDEM_FILTROS; casos 12205, 12428/12431, 12600, "3500"
- [ ] ferramentas: buscar, card, fotos, responder_ficha, escalar
- [ ] classificador: schema, prompt.md, cliente com fallback, fixtures gravadas
- [ ] compositor: templates copiados do Tel, persona, frase de ligação <= 200 caracteres
- [ ] validador: regras.yaml (17 do painel + as da entrevista), grounding; casos 12430, 12387, 12301, 12565
- [ ] saída e trace
- [ ] replay dos 30 dias sem exceção; exportar_violacoes passando
- [ ] sombra: cópia do webhook (Z-API ou nó no n8n, com autorização), comparar.py, 3 dias de relatório
