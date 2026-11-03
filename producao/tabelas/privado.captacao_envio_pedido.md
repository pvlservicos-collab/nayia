# privado.captacao_envio_pedido  (tabela, ~44 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('privado.captacao_envio_pedido_id_seq'::regclass)
telefone  text  NOT NULL
codigos  integer[]  NOT NULL
pedido_por  text
estado  text  NOT NULL  padrão 'pendente'::text
enviados  integer[]  NOT NULL  padrão '{}'::integer[]
resultado  text
criado_em  timestamp with time zone  NOT NULL  padrão now()
feito_em  timestamp with time zone

## índices
CREATE INDEX captacao_envio_pedido_pendente ON privado.captacao_envio_pedido USING btree (id) WHERE (estado = 'pendente'::text)
CREATE UNIQUE INDEX captacao_envio_pedido_pkey ON privado.captacao_envio_pedido USING btree (id)

## restrições
captacao_envio_pedido_estado_check: CHECK ((estado = ANY (ARRAY['pendente'::text, 'enviando'::text, 'enviado'::text, 'falhou'::text])))
captacao_envio_pedido_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
crm_captacao_enviar_imoveis

## funções que citam
crm_captacao_enviar_imoveis, crm_captacao_envio_estado
