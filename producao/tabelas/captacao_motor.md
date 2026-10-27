# captacao_motor  (tabela, ~1783 linhas)
317: leads da captação atendidos pela Nay em Python (entraram ao receber o modelo oficial). Apagar a linha devolve o lead ao fluxo do n8n.

## colunas
lead_id  bigint  NOT NULL
motor  text  NOT NULL  padrão 'python'::text
desde  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX captacao_motor_pkey ON public.captacao_motor USING btree (lead_id)

## restrições
captacao_motor_pkey: PRIMARY KEY (lead_id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
captacao_py_reservar_disparo

## funções que citam
captacao_e_do_python, captacao_py_disparo_placar, captacao_py_fila_do_disparo, captacao_py_reservar_disparo, crm_captacao_disparo_oficial
