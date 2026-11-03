# privado.link_organico  (tabela, ~0 linhas)
559: os links orgânicos do WhatsApp do 8595 (redes, blog, site), com a marca que identifica o lead.

## colunas
codigo  text  NOT NULL
canal  text  NOT NULL
nome  text  NOT NULL
mensagem  text  NOT NULL
marca  text  NOT NULL
utm_source  text  NOT NULL
utm_medium  text  NOT NULL
utm_campaign  text  NOT NULL  padrão 'organico'::text
ativo  boolean  NOT NULL  padrão true
criado_em  timestamp with time zone  NOT NULL  padrão now()
criado_por  text
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX link_organico_pkey ON privado.link_organico USING btree (codigo)

## restrições
link_organico_check: CHECK ((POSITION((lower(marca)) IN (lower(mensagem))) > 0))
link_organico_codigo_check: CHECK ((codigo ~ '^[a-z0-9][a-z0-9-]{1,39}$'::text))
link_organico_pkey: PRIMARY KEY (codigo)

## permissões
(só o dono)

## funções que escrevem aqui
site_link_organico_salvar

## funções que citam
link_organico_do_lead, site_link_organico_clique, site_link_organico_salvar, site_links_organicos
