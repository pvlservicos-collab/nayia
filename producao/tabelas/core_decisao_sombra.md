# core_decisao_sombra  (tabela, ~107 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('core_decisao_sombra_id_seq'::regclass)
turno_id  bigint  NOT NULL
modo  text  NOT NULL
quem_responde  text  NOT NULL
intencao  text
confianca_intencao  real
pediu_imovel  boolean  NOT NULL
codigo_quer  integer
codigo_rejeita  integer
pergunta_de_confirmacao  text
origem  text  NOT NULL
versao_perguntas  text  NOT NULL
ms  integer
custo  numeric
decisao  jsonb  NOT NULL
estado  jsonb  NOT NULL
respostas  jsonb
erro  text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX core_decisao_sombra_turno ON public.core_decisao_sombra USING btree (turno_id, criado_em)
CREATE UNIQUE INDEX core_decisao_sombra_ao_vivo ON public.core_decisao_sombra USING btree (turno_id) WHERE (modo = 'ao_vivo'::text)
CREATE UNIQUE INDEX core_decisao_sombra_pkey ON public.core_decisao_sombra USING btree (id)

## restrições
core_decisao_sombra_modo_check: CHECK ((modo = ANY (ARRAY['ao_vivo'::text, 'replay'::text])))
core_decisao_sombra_origem_check: CHECK ((origem = ANY (ARRAY['jev'::text, 'reserva'::text])))
core_decisao_sombra_pkey: PRIMARY KEY (id)
core_decisao_sombra_quem_responde_check: CHECK ((quem_responde = ANY (ARRAY['silencio'::text, 'secretaria'::text, 'locacao'::text, 'tel'::text, 'escalar'::text])))

## permissões
nay_core: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
