# Decisões (uma linha cada: data, decisão, motivo)

## Tomadas
- 29/09 — O modelo só classifica e liga frases; quem decide é a máquina de estados, quem sabe é o banco. Motivo: perguntas 41 e 42 (a camada que corrige depois do modelo é a que mais erra).
- 29/09 — Filtros na ordem finalidade, tipo, teto, região (quem veio do grupo: região antes do teto), e nunca lista antes dos quatro. Reverte a regra 146 ("lista com qualquer filtro"). Motivo: decisão do Tel no pedido do nay-core.
- 29/09 — Entrega 1 em sombra: `core_saida.estado` só aceita `simulado`, por CHECK no banco. Motivo: liberar envio real tem que ser decisão explícita e migração própria.
- 29/09 — O imóvel é lido de duas visões materializadas (`core_imovel_busca`, `core_imovel_dono`) com índice e REFRESH CONCURRENTLY a cada 10 min pelo worker. Motivo: pedido do Tel de "remodelar para otimizar a consulta e relacionar direito imóveis e proprietários"; montam em < 0,1 s e evitam que cada função recalcule ofertável, finalidade e dono do seu jeito.
- 29/09 — O dono vem de `imoveis.proprietario_id`, depois `imovel_privado`, depois o admin com um dono só. Motivo: medido em 30/09, onde os dois primeiros existem eles batem em 100% e nenhum id é órfão; o primeiro cobre 5.647 imóveis contra 1.172.
- 29/09 — `ofertavel` exige preço na finalidade (249 imóveis); os 10 no mercado sem preço ficam em `no_mercado` e só saem pelo código. Motivo: a especificação define ofertável com preço > 0.
- 29/09 — Função de extensão sempre qualificada com schema e dicionário. Motivo: o teste de restauração de 30/09 mostrou que objeto que depende de search_path não volta no pg_restore.
- 29/09 — As mensagens que não precisam de consulta (cortesia, só código, card colado, citação resolvida, comando) fecham no pré-roteador, sem classificador e sem busca. Motivo: pedido do Tel de "tratar de maneira melhor as mensagens que não precisam de consulta"; o velho passava todas pelo Jev e pelo agente (pergunta 6).

## Pendentes do Tel (sigo com a sugestão até ele decidir)
- Onde mora o código do nay-core: pasta `nay-core/` dentro do repositório `nayia` (sugestão, é o que está feito) ou repositório próprio no GitHub. O deploy precisa de um clone no servidor; sugiro `/opt/nayia` com sparse-checkout só de `nay-core/`.
- Papel do banco `nay_core`: sugiro criar um papel próprio com SELECT nas tabelas do velho e escrita só em `core_*` (hoje o único papel com acesso é o `nay`, superusuário). Criar papel é mudança no cluster: precisa da autorização dele.
- Mobília "só ar-condicionado" (40 imóveis): sugiro contar como **não mobiliado** na busca. Está assim em `core_imovel_busca.mobilia`.
- Telefone repetido entre donos diferentes (15 das 37 locações ofertáveis; por exemplo 2014, 5757, 5628 e 5629): sugiro que a visita a esses imóveis peça conferência antes de falar com o dono (entrega 2).
- Sombra: se a Z-API aceitar uma segunda URL de webhook, uso ela; se não, um nó no "Nay- recebe mensagem", aplicado na madrugada com o procedimento do espelho, **só com autorização**.
- Modelos `gpt-6-luna` e `gpt-6-sol`: confirmar que existem na conta da OpenAI antes da sessão do classificador; se não, `LLM_RESERVA` (gpt-5.6-sol) é o padrão.
