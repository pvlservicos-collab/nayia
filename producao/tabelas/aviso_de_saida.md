# aviso_de_saida  (tabela, ~4534 linhas)

## colunas
codigo  text  NOT NULL
motivo  text
marcado_em  timestamp with time zone  NOT NULL  padrão now()
avisado_em  timestamp with time zone
erro  text

## índices
CREATE UNIQUE INDEX aviso_de_saida_pkey ON public.aviso_de_saida USING btree (codigo)

## restrições
aviso_de_saida_pkey: PRIMARY KEY (codigo)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nay_devolver_aviso_de_saida, nay_enfileirar_aviso_de_saida, nay_reservar_aviso_de_saida

## funções que citam
nay_devolver_aviso_de_saida, nay_enfileirar_aviso_de_saida, nay_reservar_aviso_de_saida, nay_saidas_a_avisar
