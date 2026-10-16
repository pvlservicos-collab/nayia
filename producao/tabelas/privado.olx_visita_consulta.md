# privado.olx_visita_consulta  (tabela, ~0 linhas)
389: a pergunta da Nay a um corretor ou ao proprietário sobre uma visita, e a resposta.

## colunas
id  bigint  NOT NULL  padrão nextval('privado.olx_visita_consulta_id_seq'::regclass)
visita  bigint  NOT NULL
papel  text  NOT NULL
nome  text
telefone  text  NOT NULL
perguntado_em  timestamp with time zone  NOT NULL  padrão now()
ultima_lida  bigint  NOT NULL  padrão 0
estado  text  NOT NULL  padrão 'esperando'::text
resposta  text
respondido_em  timestamp with time zone

## índices
CREATE INDEX olx_visita_consulta_esperando ON privado.olx_visita_consulta USING btree (estado, telefone)
CREATE UNIQUE INDEX olx_visita_consulta_pkey ON privado.olx_visita_consulta USING btree (id)

## restrições
olx_visita_consulta_estado_check: CHECK ((estado = ANY (ARRAY['esperando'::text, 'sim'::text, 'nao'::text, 'sem_resposta'::text, 'cancelada'::text])))
olx_visita_consulta_papel_check: CHECK ((papel = ANY (ARRAY['corretor'::text, 'proprietario'::text])))
olx_visita_consulta_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
captacao_mensagem_do_python
