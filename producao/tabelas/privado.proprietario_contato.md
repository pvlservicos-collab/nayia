# privado.proprietario_contato  (tabela, ~0 linhas)
432: outros contatos do proprietário (o botão + do cartão Proprietário no Editar imóvel). O principal é proprietarios.telefone.

## colunas
id  bigint  NOT NULL  padrão nextval('privado.proprietario_contato_id_seq'::regclass)
proprietario_id  integer  NOT NULL
ordem  integer  NOT NULL  padrão 1
nome  text
telefone  text
quem_e  text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX proprietario_contato_dono ON privado.proprietario_contato USING btree (proprietario_id, ordem)
CREATE UNIQUE INDEX proprietario_contato_pkey ON privado.proprietario_contato USING btree (id)

## restrições
proprietario_contato_check: CHECK (((NULLIF(btrim(COALESCE(nome, ''::text)), ''::text) IS NOT NULL) OR (NULLIF(btrim(COALESCE(telefone, ''::text)), ''::text) IS NOT NULL)))
proprietario_contato_pkey: PRIMARY KEY (id)
proprietario_contato_proprietario_id_fkey: FOREIGN KEY (proprietario_id) REFERENCES proprietarios(id) ON DELETE CASCADE

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_escrita: DELETE, INSERT, SELECT, UPDATE

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
