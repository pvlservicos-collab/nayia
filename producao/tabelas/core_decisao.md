# core_decisao  (tabela, ~0 linhas)

## colunas
turno_id  bigint  NOT NULL
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
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX core_decisao_pkey ON public.core_decisao USING btree (turno_id)

## restrições
core_decisao_origem_check: CHECK ((origem = ANY (ARRAY['jev'::text, 'reserva'::text])))
core_decisao_pkey: PRIMARY KEY (turno_id)
core_decisao_quem_responde_check: CHECK ((quem_responde = ANY (ARRAY['silencio'::text, 'secretaria'::text, 'locacao'::text, 'tel'::text, 'escalar'::text])))

## permissões
nay_core: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
