# nai_perfil_cliente  (tabela, ~29 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_perfil_cliente_id_seq'::regclass)
contato_id  bigint  NOT NULL
criado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()
encerrado_em  timestamp with time zone
negocio  text
tipo  text
teto  numeric
bairros  text
quartos  text
mobilia  text
exige  jsonb  NOT NULL  padrão '{}'::jsonb
pendente  text
pendente_em  timestamp with time zone

## índices
CREATE INDEX nai_perfil_cliente_ativo ON public.nai_perfil_cliente USING btree (contato_id, atualizado_em DESC) WHERE (encerrado_em IS NULL)
CREATE UNIQUE INDEX nai_perfil_cliente_pkey ON public.nai_perfil_cliente USING btree (id)

## restrições
nai_perfil_cliente_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nai_enfileirar_resposta_ferramentas, nai_perfil_gravar, nai_perfil_resposta

## funções que citam
nai_buscar_por_perfil, nai_enfileirar_resposta_ferramentas, nai_perfil_ativo, nai_perfil_gravar, nai_perfil_resposta, nai_uma_pergunta_da_sequencia
