# privado.duvida  (tabela, ~47 linhas)
512: a dúvida de um lead/corretor ligada a quem perguntamos (dono ou corretor) e ao andamento; nay-olx olx/duvidas.py, de cron

## colunas
id  bigint  NOT NULL  padrão nextval('privado.duvida_id_seq'::regclass)
origem  text  NOT NULL
origem_id  bigint  NOT NULL
juntas  bigint[]  NOT NULL  padrão '{}'::bigint[]
linha  text  NOT NULL
cliente_tel  text  NOT NULL
cliente_nome  text
cliente_papel  text  NOT NULL
lead_id  bigint
codigo  integer
pergunta  text  NOT NULL
perguntada_em  timestamp with time zone  NOT NULL
dono_tel  text
dono_nome  text
dono_papel  text
dono_motivo  text
dono_linha  text
dono_perguntado_em  timestamp with time zone
dono_cobrado_em  timestamp with time zone
cobrancas  integer  NOT NULL  padrão 0
estado  text  NOT NULL  padrão 'aberta'::text
situacao  text
resumo  text
resposta  text
respondida_em  timestamp with time zone
cliente_avisado_em  timestamp with time zone
checada_em  timestamp with time zone
checagens  integer  NOT NULL  padrão 0
historico  jsonb  NOT NULL  padrão '[]'::jsonb
criada_em  timestamp with time zone  NOT NULL  padrão now()
atualizada_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX duvida_aberta ON privado.duvida USING btree (perguntada_em) WHERE (estado = ANY (ARRAY['aberta'::text, 'esperando_dono'::text]))
CREATE INDEX duvida_cliente ON privado.duvida USING btree ("right"(regexp_replace(cliente_tel, '\D'::text, ''::text, 'g'::text), 8))
CREATE INDEX duvida_juntas ON privado.duvida USING gin (juntas)
CREATE UNIQUE INDEX duvida_origem_origem_id_key ON privado.duvida USING btree (origem, origem_id)
CREATE UNIQUE INDEX duvida_pkey ON privado.duvida USING btree (id)

## restrições
duvida_cliente_papel_check: CHECK ((cliente_papel = ANY (ARRAY['lead'::text, 'corretor'::text])))
duvida_dono_linha_check: CHECK ((dono_linha = ANY (ARRAY['captacao'::text, 'parceria'::text])))
duvida_dono_papel_check: CHECK ((dono_papel = ANY (ARRAY['proprietario'::text, 'corretor'::text])))
duvida_estado_check: CHECK ((estado = ANY (ARRAY['aberta'::text, 'esperando_dono'::text, 'respondida'::text, 'com_o_tel'::text, 'encerrada'::text])))
duvida_linha_check: CHECK ((linha = ANY (ARRAY['captacao'::text, 'parceria'::text])))
duvida_origem_check: CHECK ((origem = ANY (ARRAY['pergunta_fila'::text, 'core_pendencia'::text])))
duvida_origem_origem_id_key: UNIQUE (origem, origem_id)
duvida_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
crm_contatos_relacionados
