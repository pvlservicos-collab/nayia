# nai_regra_sugerida  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_regra_sugerida_id_seq'::regclass)
rodada  integer  NOT NULL  padrão 1
criada_em  timestamp with time zone  NOT NULL  padrão now()
janela_de  date
janela_ate  date
categoria  text  NOT NULL
importancia  text  NOT NULL  padrão 'media'::text
titulo  text  NOT NULL
regra  text  NOT NULL
o_que_faz  text
porque  text  NOT NULL
tipo  text  NOT NULL  padrão 'fluxo'::text
estado  text  NOT NULL  padrão 'sugerida'::text
decidido_em  timestamp with time zone
decidido_por  text
nota_do_tel  text

## índices
CREATE INDEX nai_regra_sugerida_por_estado ON public.nai_regra_sugerida USING btree (estado, importancia, rodada)
CREATE UNIQUE INDEX nai_regra_sugerida_pkey ON public.nai_regra_sugerida USING btree (id)

## restrições
nai_regra_sugerida_estado_check: CHECK ((estado = ANY (ARRAY['sugerida'::text, 'aceita'::text, 'recusada'::text])))
nai_regra_sugerida_importancia_check: CHECK ((importancia = ANY (ARRAY['alta'::text, 'media'::text, 'baixa'::text])))
nai_regra_sugerida_pkey: PRIMARY KEY (id)
nai_regra_sugerida_tipo_check: CHECK ((tipo = ANY (ARRAY['parede'::text, 'fluxo'::text, 'ajuste'::text, 'defeito'::text])))

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_conteudo: SELECT
nay_site_conteudo, só nestas colunas: UPDATE(estado, decidido_em, decidido_por, nota_do_tel)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
