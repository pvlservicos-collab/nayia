# privado.relatorio_etiquetas_contato  (tabela, ~399 linhas)
426: a foto de quem estava em cada etiqueta de uma linha do CRM (cópia; o CRM não muda).

## colunas
foto_id  integer  NOT NULL
etiqueta  text  NOT NULL
lead_id  text  NOT NULL
nome  text
telefone  text
ultima_atividade  timestamp with time zone
criado_no_crm  timestamp with time zone

## índices
CREATE UNIQUE INDEX relatorio_etiquetas_contato_pkey ON privado.relatorio_etiquetas_contato USING btree (foto_id, etiqueta, lead_id)

## restrições
relatorio_etiquetas_contato_foto_id_fkey: FOREIGN KEY (foto_id) REFERENCES privado.relatorio_etiquetas_foto(id)
relatorio_etiquetas_contato_pkey: PRIMARY KEY (foto_id, etiqueta, lead_id)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
site_relatorio_etiquetas
