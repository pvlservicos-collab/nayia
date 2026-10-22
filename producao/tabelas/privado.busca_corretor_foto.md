# privado.busca_corretor_foto  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('privado.busca_corretor_foto_id_seq'::regclass)
telefone8  text  NOT NULL
url  text  NOT NULL
message_id  text
usada_em  timestamp with time zone
em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX busca_corretor_foto_tel ON privado.busca_corretor_foto USING btree (telefone8, id)
CREATE UNIQUE INDEX busca_corretor_foto_message_id_key ON privado.busca_corretor_foto USING btree (message_id)
CREATE UNIQUE INDEX busca_corretor_foto_pkey ON privado.busca_corretor_foto USING btree (id)

## restrições
busca_corretor_foto_message_id_key: UNIQUE (message_id)
busca_corretor_foto_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
busca_corretor_foto_guardar

## funções que citam
busca_corretor_foto_guardar
