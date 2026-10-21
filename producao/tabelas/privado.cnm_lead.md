# privado.cnm_lead  (tabela, ~0 linhas)
458: os leads que o Chaves na Mão manda por POST (nay-site-api /api/chavesnamao/leads).

## colunas
lead_id  text  NOT NULL
recebido_em  timestamp with time zone  NOT NULL  padrão now()
vezes  integer  NOT NULL  padrão 1
ultimo_em  timestamp with time zone  NOT NULL  padrão now()
autenticado  boolean  NOT NULL
nome  text
telefone  text
email  text
mensagem  text
tipo  text
codigo  integer
anuncio_id  text
anuncio_url  text
anuncio_titulo  text
negocio  text
valor  numeric
criado_no_portal  timestamp with time zone
payload  jsonb  NOT NULL

## índices
CREATE INDEX cnm_lead_recebido ON privado.cnm_lead USING btree (recebido_em DESC)
CREATE INDEX cnm_lead_telefone ON privado.cnm_lead USING btree (telefone)
CREATE UNIQUE INDEX cnm_lead_pkey ON privado.cnm_lead USING btree (lead_id)

## restrições
cnm_lead_pkey: PRIMARY KEY (lead_id)

## permissões
(só o dono)

## funções que escrevem aqui
cnm_lead_receber

## funções que citam
cnm_lead_receber
