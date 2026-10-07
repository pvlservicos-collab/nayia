# core_instrucao_feita  (tabela, ~0 linhas)
Instruções do CRM (nai_instrucao) que o nay-core já executou: cada uma sai uma vez só (026).

## colunas
instrucao_id  bigint  NOT NULL
turno_id  bigint
feito  jsonb
feito_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX core_instrucao_feita_pkey ON public.core_instrucao_feita USING btree (instrucao_id)

## restrições
core_instrucao_feita_pkey: PRIMARY KEY (instrucao_id)
core_instrucao_feita_turno_id_fkey: FOREIGN KEY (turno_id) REFERENCES core_turno(id)

## permissões
nay_core: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
nai_instrucao_texto
