# privado.olx_bot_imovel  (tabela, ~0 linhas)
260: o que o grokbot mandou cadastrar, esperando um humano aprovar na aba Imóveis da OLX Bot

## colunas
id  bigint  NOT NULL  padrão nextval('privado.olx_bot_imovel_id_seq'::regclass)
estado  text  NOT NULL  padrão 'pendente'::text
link  text  NOT NULL
link_normal  text  NOT NULL
portal  text
id_anuncio  text
corretor_nome  text  NOT NULL
corretor_telefone  text  NOT NULL
proprietario_nome  text
proprietario_telefone  text
autorizacao_como  text  NOT NULL
dados  jsonb  NOT NULL
fotos  text[]  NOT NULL  padrão '{}'::text[]
candidatos  jsonb
envios  integer  NOT NULL  padrão 1
recebido_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()
codigo  integer
decidido_por  text
decidido_em  timestamp with time zone
motivo  text

## índices
CREATE INDEX olx_bot_imovel_estado ON privado.olx_bot_imovel USING btree (estado, recebido_em DESC)
CREATE UNIQUE INDEX olx_bot_imovel_link_normal_key ON privado.olx_bot_imovel USING btree (link_normal)
CREATE UNIQUE INDEX olx_bot_imovel_pkey ON privado.olx_bot_imovel USING btree (id)

## restrições
olx_bot_imovel_estado_check: CHECK ((estado = ANY (ARRAY['pendente'::text, 'aprovado'::text, 'descartado'::text])))
olx_bot_imovel_link_normal_key: UNIQUE (link_normal)
olx_bot_imovel_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_site_escrita: SELECT, UPDATE

## funções que escrevem aqui
crm_olx_bot_receber

## funções que citam
crm_olx_bot_receber
