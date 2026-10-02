# nai_retomada  (tabela, ~0 linhas)
Fila de uma vez so: as conversas sem resposta que a NAI vai retomar no sabado 19/09 08:45. Descartavel depois.

## colunas
chave  text  NOT NULL
telefone  text  NOT NULL
nome  text
texto  text
recebida_em  timestamp with time zone
responder  boolean  NOT NULL  padrão true
motivo  text
estado  text  NOT NULL  padrão 'pendente'::text
pulo  text
rodado_em  timestamp with time zone

## índices
CREATE UNIQUE INDEX nai_retomada_pkey ON public.nai_retomada USING btree (chave)

## restrições
nai_retomada_estado_check: CHECK ((estado = ANY (ARRAY['pendente'::text, 'enviado'::text, 'pulado'::text, 'erro'::text])))
nai_retomada_pkey: PRIMARY KEY (chave)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
