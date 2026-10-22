# privado.busca_cliente_passo  (tabela, ~54 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('privado.busca_cliente_passo_id_seq'::regclass)
busca  bigint  NOT NULL
em  timestamp with time zone  NOT NULL  padrão now()
lugar  text  NOT NULL
texto  text  NOT NULL
dados  jsonb

## índices
CREATE INDEX busca_cliente_passo_busca ON privado.busca_cliente_passo USING btree (busca, id)
CREATE UNIQUE INDEX busca_cliente_passo_pkey ON privado.busca_cliente_passo USING btree (id)

## restrições
busca_cliente_passo_busca_fkey: FOREIGN KEY (busca) REFERENCES privado.busca_cliente(id) ON DELETE CASCADE
busca_cliente_passo_lugar_check: CHECK ((lugar = ANY (ARRAY['perfil'::text, 'base'::text, 'cliente'::text, 'grupos'::text, 'olx'::text, 'corretor'::text, 'oferta'::text, 'equipe'::text])))
busca_cliente_passo_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
crm_busca_cliente_acao, crm_busca_cliente_manual

## funções que citam
crm_busca_cliente_acao, crm_busca_cliente_lista, crm_busca_cliente_manual
