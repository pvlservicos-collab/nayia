# corretor_alto_padrao  (tabela, ~0 linhas)

## colunas
telefone  text  NOT NULL
nome  text
pediu_em  timestamp with time zone  NOT NULL  padrão now()
pediu_texto  text
perguntado_em  timestamp with time zone
anuncia_instagram  boolean
instagram  text
anuncia_portais  boolean
portais  text
respondido_em  timestamp with time zone
aprovado  boolean
avaliado_em  timestamp with time zone
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX corretor_alto_padrao_a_avaliar ON public.corretor_alto_padrao USING btree (respondido_em DESC) WHERE ((respondido_em IS NOT NULL) AND (avaliado_em IS NULL))
CREATE UNIQUE INDEX corretor_alto_padrao_pkey ON public.corretor_alto_padrao USING btree (telefone)

## restrições
corretor_alto_padrao_pkey: PRIMARY KEY (telefone)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
