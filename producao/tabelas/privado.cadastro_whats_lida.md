# privado.cadastro_whats_lida  (tabela, ~0 linhas)

## colunas
message_id  text  NOT NULL
cadastro_id  bigint
lida_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX cadastro_whats_lida_pkey ON privado.cadastro_whats_lida USING btree (message_id)

## restrições
cadastro_whats_lida_pkey: PRIMARY KEY (message_id)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
