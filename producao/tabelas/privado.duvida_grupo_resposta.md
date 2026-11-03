# privado.duvida_grupo_resposta  (tabela, ~0 linhas)
575: as respostas da Nay das Dúvidas no grupo "Dúvidas Imobeasy" (Parceria): cada linha junta as mensagens de uma pessoa

## colunas
id  bigint  NOT NULL  padrão nextval('privado.duvida_grupo_resposta_id_seq'::regclass)
grupo_id  text  NOT NULL
remetente  text
remetente_nome  text
mensagens  text[]  NOT NULL
pergunta  text
resposta  text
codigos  integer[]
message_id  text
erro  text
ms  integer
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX duvida_grupo_resposta_criado ON privado.duvida_grupo_resposta USING btree (grupo_id, criado_em DESC)
CREATE INDEX duvida_grupo_resposta_mensagens ON privado.duvida_grupo_resposta USING gin (mensagens)
CREATE UNIQUE INDEX duvida_grupo_resposta_pkey ON privado.duvida_grupo_resposta USING btree (id)

## restrições
duvida_grupo_resposta_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
