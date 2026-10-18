# privado.grupo_pedido  (tabela, ~1843 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('privado.grupo_pedido_id_seq'::regclass)
fonte  text  NOT NULL
ref  text  NOT NULL
parte  integer  NOT NULL
grupo_id  text
grupo_nome  text
remetente  text
remetente_nome  text
enviada_em  timestamp with time zone  NOT NULL
texto  text  NOT NULL
ficha  jsonb  NOT NULL
duvidosos  text[]  NOT NULL  padrão '{}'::text[]
local  jsonb
estado  text  NOT NULL  padrão 'novo'::text
melhor_codigo  integer
nota  numeric(5,1)
faixa  text
sem_match_motivo  text
funil  jsonb
extraido_em  timestamp with time zone  NOT NULL  padrão now()
pontuado_em  timestamp with time zone

## índices
CREATE INDEX grupo_pedido_quando ON privado.grupo_pedido USING btree (enviada_em DESC)
CREATE UNIQUE INDEX grupo_pedido_fonte_ref_parte_key ON privado.grupo_pedido USING btree (fonte, ref, parte)
CREATE UNIQUE INDEX grupo_pedido_pkey ON privado.grupo_pedido USING btree (id)

## restrições
grupo_pedido_estado_check: CHECK ((estado = ANY (ARRAY['novo'::text, 'rejeitado'::text, 'aprovado'::text, 'enviado'::text])))
grupo_pedido_faixa_check: CHECK ((faixa = ANY (ARRAY['verde'::text, 'amarelo'::text, 'registro'::text, 'sem_match'::text])))
grupo_pedido_fonte_check: CHECK ((fonte = ANY (ARRAY['grupo'::text, 'teste'::text])))
grupo_pedido_fonte_ref_parte_key: UNIQUE (fonte, ref, parte)
grupo_pedido_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
site_captacao_grupos_enviar, site_captacao_grupos_enviar_varios, site_captacao_grupos_estado

## funções que citam
site_captacao_grupos, site_captacao_grupos_citacao, site_captacao_grupos_demanda, site_captacao_grupos_enviar, site_captacao_grupos_enviar_varios, site_captacao_grupos_estado, site_captacao_grupos_julgar, site_captacao_grupos_mensagem, site_captacao_grupos_teste_lido, site_painel_metricas
