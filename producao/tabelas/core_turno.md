# core_turno  (tabela, ~818 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('core_turno_id_seq'::regclass)
chave  text  NOT NULL
papel  text
texto  text  NOT NULL
estado_antes  text
estado_depois  text
intencao  text
caminho  text
usou_modelo  boolean  NOT NULL  padrão false
versao_regras  text
versao_prompt  text
exec_id  text
ms_total  integer
erro  text
criado_em  timestamp with time zone  NOT NULL  padrão now()
fechado_em  timestamp with time zone

## índices
CREATE INDEX core_turno_chave ON public.core_turno USING btree (chave, criado_em)
CREATE UNIQUE INDEX core_turno_exec_id ON public.core_turno USING btree (exec_id) WHERE (exec_id IS NOT NULL)
CREATE UNIQUE INDEX core_turno_pkey ON public.core_turno USING btree (id)

## restrições
core_turno_caminho_check: CHECK ((caminho = ANY (ARRAY['pre_roteador'::text, 'classificador'::text, 'fallback'::text, 'fora_do_escopo'::text])))
core_turno_pkey: PRIMARY KEY (id)

## permissões
nay_core: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
