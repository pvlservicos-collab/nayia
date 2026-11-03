# privado.link_organico_lead  (tabela, ~0 linhas)

## colunas
telefone8  text  NOT NULL
codigo  text  NOT NULL
telefone  text  NOT NULL
primeira_em  timestamp with time zone  NOT NULL
mensagem  text

## índices
CREATE INDEX link_organico_lead_em ON privado.link_organico_lead USING btree (codigo, primeira_em DESC)
CREATE UNIQUE INDEX link_organico_lead_pkey ON privado.link_organico_lead USING btree (telefone8, codigo)

## restrições
link_organico_lead_codigo_fkey: FOREIGN KEY (codigo) REFERENCES privado.link_organico(codigo) ON UPDATE CASCADE
link_organico_lead_pkey: PRIMARY KEY (telefone8, codigo)

## permissões
(só o dono)

## funções que escrevem aqui
link_organico_do_lead

## funções que citam
link_organico_do_lead, site_links_organicos
