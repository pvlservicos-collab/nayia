# imovel_enviado_no_dia  (tabela, ~651 linhas)

## colunas
chave  text  NOT NULL
codigo  integer  NOT NULL
dia  date  NOT NULL
primeiro_em  timestamp with time zone  NOT NULL  padrão now()
origem  text  NOT NULL
turno_id  bigint

## índices
CREATE UNIQUE INDEX imovel_enviado_no_dia_pkey ON public.imovel_enviado_no_dia USING btree (chave, codigo, dia)

## restrições
imovel_enviado_no_dia_pkey: PRIMARY KEY (chave, codigo, dia)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT

## funções que escrevem aqui
nai_confirmar_envio, nai_disparo_liberar, nay_liberar_imovel_do_dia, nay_reservar_imovel_do_dia

## funções que citam
crm_imoveis_enviados, crm_parceria_followup_nay, nai_confirmar_envio, nai_disparo_liberar, nai_etapa_calcular, nai_followup_rodar, nai_saida_validar, nay_imovel_ja_foi_24h, nay_liberar_imovel_do_dia, nay_reservar_imovel_do_dia
