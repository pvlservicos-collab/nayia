# privado.imovel_ficha  (tabela, ~715 linhas)
Dado interno do imóvel que o site antigo tinha: locatário atual e observações. Fora do public de propósito (157).

## colunas
codigo  integer  NOT NULL
locatario_nome  text
locatario_contato  text
observacao_aluguel  text
observacoes  text
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX imovel_ficha_pkey ON privado.imovel_ficha USING btree (codigo)

## restrições
imovel_ficha_pkey: PRIMARY KEY (codigo)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_site_escrita: INSERT, SELECT, UPDATE

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
