# privado.cadastro_whats_entrada  (tabela, ~46 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('privado.cadastro_whats_entrada_id_seq'::regclass)
cadastro_id  bigint  NOT NULL
texto  text
midias  text[]  NOT NULL  padrão '{}'::text[]
ids  bigint[]  NOT NULL  padrão '{}'::bigint[]
status  text  NOT NULL  padrão 'Recebido'::text
criada_em  timestamp with time zone  NOT NULL  padrão now()
fonte  text  NOT NULL  padrão 'mensagens'::text   -- 479: de onde vieram os ids: mensagens (a porta da Parceria) ou captacao (captacao_mensagens, o 8595).

## índices
CREATE INDEX cadastro_whats_entrada_fila ON privado.cadastro_whats_entrada USING btree (status, criada_em) WHERE (status <> 'Feito'::text)
CREATE UNIQUE INDEX cadastro_whats_entrada_pkey ON privado.cadastro_whats_entrada USING btree (id)

## restrições
cadastro_whats_entrada_cadastro_id_fkey: FOREIGN KEY (cadastro_id) REFERENCES privado.cadastro_whats(id)
cadastro_whats_entrada_fonte_ok: CHECK ((fonte = ANY (ARRAY['mensagens'::text, 'captacao'::text])))
cadastro_whats_entrada_pkey: PRIMARY KEY (id)
cadastro_whats_entrada_status_check: CHECK ((status = ANY (ARRAY['Recebido'::text, 'Processando'::text, 'Feito'::text])))

## permissões
(só o dono)

## funções que escrevem aqui
nai_abrir_turno

## funções que citam
nai_abrir_turno
