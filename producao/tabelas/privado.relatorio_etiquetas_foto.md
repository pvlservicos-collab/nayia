# privado.relatorio_etiquetas_foto  (tabela, ~0 linhas)

## colunas
id  integer  NOT NULL  padrão nextval('privado.relatorio_etiquetas_foto_id_seq'::regclass)
linha  text  NOT NULL
tirada_em  timestamp with time zone  NOT NULL  padrão now()
observacao  text

## índices
CREATE UNIQUE INDEX relatorio_etiquetas_foto_pkey ON privado.relatorio_etiquetas_foto USING btree (id)

## restrições
relatorio_etiquetas_foto_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
site_relatorio_etiquetas
