# privado.link_organico_clique  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('privado.link_organico_clique_id_seq'::regclass)
codigo  text  NOT NULL
em  timestamp with time zone  NOT NULL  padrão now()
utm  jsonb  NOT NULL  padrão '{}'::jsonb
referer  text
ip_hash  text

## índices
CREATE INDEX link_organico_clique_codigo ON privado.link_organico_clique USING btree (codigo, em DESC)
CREATE UNIQUE INDEX link_organico_clique_pkey ON privado.link_organico_clique USING btree (id)

## restrições
link_organico_clique_codigo_fkey: FOREIGN KEY (codigo) REFERENCES privado.link_organico(codigo) ON UPDATE CASCADE
link_organico_clique_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
site_link_organico_clique

## funções que citam
site_link_organico_clique, site_links_organicos
