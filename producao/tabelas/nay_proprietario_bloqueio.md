# nay_proprietario_bloqueio  (tabela, ~0 linhas)
463: os proprietários. A Nay não atende nem manda nada que não seja visita, fechamento ou pedido da equipe.

## colunas
chave  text  NOT NULL
nome  text
fontes  text[]  NOT NULL  padrão '{}'::text[]
criado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX nay_proprietario_bloqueio_pkey ON public.nay_proprietario_bloqueio USING btree (chave)

## restrições
nay_proprietario_bloqueio_pkey: PRIMARY KEY (chave)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nay_proprietario_bloqueio_atualizar

## funções que citam
nai_e_proprietario_contato, nay_proprietario_bloqueio_atualizar
