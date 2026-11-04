# privado.campanha_evento  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('privado.campanha_evento_id_seq'::regclass)
contato  bigint  NOT NULL
tipo  text  NOT NULL
texto  text
message_id  text
saida_id  bigint
dados  jsonb
em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX campanha_evento_contato ON privado.campanha_evento USING btree (contato, id)
CREATE UNIQUE INDEX campanha_evento_pkey ON privado.campanha_evento USING btree (id)

## restrições
campanha_evento_contato_fkey: FOREIGN KEY (contato) REFERENCES privado.campanha_contato(id)
campanha_evento_pkey: PRIMARY KEY (id)
campanha_evento_tipo_check: CHECK ((tipo = ANY (ARRAY['liberada'::text, 'cancelada'::text, 'adiada'::text, 'enviada'::text, 'recebida'::text, 'classificada'::text, 'nota'::text, 'aviso'::text, 'erro'::text])))

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
