# anuncio_abordagem_texto  (tabela, ~0 linhas)
309: a mensagem que o bot da OLX manda ao anunciante e a frase do cliente por tipo de imóvel

## colunas
chave  text  NOT NULL
texto  text  NOT NULL
nota  text
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX anuncio_abordagem_texto_pkey ON public.anuncio_abordagem_texto USING btree (chave)

## restrições
anuncio_abordagem_texto_pkey: PRIMARY KEY (chave)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
crm_anuncio_mensagem
