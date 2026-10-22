# privado.busca_contato  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('privado.busca_contato_id_seq'::regclass)
telefone8  text  NOT NULL
telefone  text  NOT NULL
busca  bigint
de  text  NOT NULL
olx_id  bigint
nome  text
em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX busca_contato_tel ON privado.busca_contato USING btree (telefone8, em)
CREATE UNIQUE INDEX busca_contato_pkey ON privado.busca_contato USING btree (id)

## restrições
busca_contato_busca_fkey: FOREIGN KEY (busca) REFERENCES privado.busca_cliente(id) ON DELETE SET NULL
busca_contato_de_check: CHECK ((de = ANY (ARRAY['anunciante_olx'::text, 'corretor_grupo'::text, 'corretor_pv'::text])))
busca_contato_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
busca_corretor_e, olx_organicos_novos
