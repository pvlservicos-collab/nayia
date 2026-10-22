# pergunta_fila  (tabela, ~196 linhas)
391: a fila de perguntas que a Nay não sabe, feitas ao Tel no PV uma por vez (Pergunta k/N). linha: parceria | captacao

## colunas
id  bigint  NOT NULL  padrão nextval('pergunta_fila_id_seq'::regclass)
criada_em  timestamp with time zone  NOT NULL  padrão now()
ordem  bigint  NOT NULL  padrão 0
linha  text  NOT NULL
chave  text  NOT NULL
cliente  text
codigo  integer
imovel  text
pergunta  text  NOT NULL
origem  text  NOT NULL
origem_id  bigint
estado  text  NOT NULL  padrão 'fila'::text
perguntada_em  timestamp with time zone
cobrada_em  timestamp with time zone
cobrancas  integer  NOT NULL  padrão 0
saida_id  bigint
resposta  text
respondida_em  timestamp with time zone
entregue_em  timestamp with time zone
entrega_erro  text
detalhe  text

## índices
CREATE INDEX pergunta_fila_aberta ON public.pergunta_fila USING btree (ordem, id) WHERE (estado = ANY (ARRAY['fila'::text, 'perguntada'::text]))
CREATE UNIQUE INDEX pergunta_fila_da_origem ON public.pergunta_fila USING btree (origem, origem_id) WHERE (origem_id IS NOT NULL)
CREATE UNIQUE INDEX pergunta_fila_pkey ON public.pergunta_fila USING btree (id)
CREATE UNIQUE INDEX pergunta_fila_uma_perguntada ON public.pergunta_fila USING btree ((true)) WHERE (estado = 'perguntada'::text)

## restrições
pergunta_fila_estado_check: CHECK ((estado = ANY (ARRAY['fila'::text, 'perguntada'::text, 'respondida'::text, 'descartada'::text, 'agente'::text])))
pergunta_fila_linha_check: CHECK ((linha = ANY (ARRAY['parceria'::text, 'captacao'::text])))
pergunta_fila_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
pergunta_fila_agente_devolver, pergunta_fila_agente_responder, pergunta_fila_entrar, pergunta_fila_perguntar_proxima, pergunta_fila_responder, pergunta_fila_tick

## funções que citam
pergunta_fila_agente_devolver, pergunta_fila_agente_responder, pergunta_fila_entrar, pergunta_fila_ligada, pergunta_fila_perguntar_proxima, pergunta_fila_posicao, pergunta_fila_responder, pergunta_fila_resposta_valida, pergunta_fila_texto, pergunta_fila_tick, site_painel_metricas
