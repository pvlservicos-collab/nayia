# nai_core_turno  (tabela, ~107 linhas)
Turnos de corretor que a porta (nai_abrir_turno) entregou ao núcleo novo (269). O nay-core lê daqui.

## colunas
turno_id  bigint  NOT NULL
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX nai_core_turno_pkey ON public.nai_core_turno USING btree (turno_id)

## restrições
nai_core_turno_pkey: PRIMARY KEY (turno_id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT

## funções que escrevem aqui
nai_abrir_turno

## funções que citam
nai_abrir_turno
