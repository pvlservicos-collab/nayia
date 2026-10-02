# nai_turno_decisao  (tabela, ~972 linhas)

## colunas
turno_id  bigint  NOT NULL
intencao  text  NOT NULL
decidido_por  text  NOT NULL
confianca  real
codigos_pedidos  integer[]  NOT NULL  padrão '{}'::integer[]
codigos_rejeitados  integer[]  NOT NULL  padrão '{}'::integer[]
ferramentas  text[]  NOT NULL  padrão '{}'::text[]
enviados  jsonb  NOT NULL  padrão '[]'::jsonb
bloqueados  jsonb  NOT NULL  padrão '[]'::jsonb
jev_bruto  jsonb
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX nai_turno_decisao_intencao ON public.nai_turno_decisao USING btree (intencao, criado_em DESC)
CREATE UNIQUE INDEX nai_turno_decisao_pkey ON public.nai_turno_decisao USING btree (turno_id)

## restrições
nai_turno_decisao_intencao_check: CHECK ((intencao = ANY (ARRAY['pedir_imovel'::text, 'rejeitar_imovel'::text, 'pergunta_sobre_imovel'::text, 'visita'::text, 'resultado_visita'::text, 'cortesia'::text, 'oferta_de_imovel'::text, 'assunto_geral'::text, 'indefinida'::text])))
nai_turno_decisao_pkey: PRIMARY KEY (turno_id)
nai_turno_decisao_turno_id_fkey: FOREIGN KEY (turno_id) REFERENCES nai_turno(id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
nai_decidir_v2, nai_ferramentas_v2, nai_registrar_saida_v2

## funções que citam
nai_bloco_colher, nai_decidir_v2, nai_ferramentas_v2, nai_pode_enviar_codigo_v2, nai_registrar_saida_v2
