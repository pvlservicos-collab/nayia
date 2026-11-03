# privado.me_envia  (tabela, ~152 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('privado.me_envia_id_seq'::regclass)
criado_em  timestamp with time zone  NOT NULL  padrão now()
chave  text  NOT NULL
telefone  text  NOT NULL
codigos  integer[]  NOT NULL
enviados  integer  NOT NULL  padrão 0
ip  text
resultado  text

## índices
CREATE INDEX me_envia_chave ON privado.me_envia USING btree (chave, criado_em)
CREATE INDEX me_envia_ip ON privado.me_envia USING btree (ip, criado_em)
CREATE INDEX me_envia_quando ON privado.me_envia USING btree (criado_em)
CREATE UNIQUE INDEX me_envia_pkey ON privado.me_envia USING btree (id)

## restrições
me_envia_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
site_me_envia

## funções que citam
crm_me_envia_por_telefone, site_me_envia, site_me_envia_ranking
