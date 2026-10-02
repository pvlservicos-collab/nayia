# nai_acesso_imovel  (tabela, ~4 linhas)

## colunas
codigo  integer  NOT NULL
acesso  text  NOT NULL
detalhe  text
fonte  text  NOT NULL
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX nai_acesso_imovel_pkey ON public.nai_acesso_imovel USING btree (codigo)

## restrições
nai_acesso_imovel_acesso_check: CHECK ((acesso = ANY (ARRAY['chave_conosco'::text, 'buscar_chave'::text, 'fechadura'::text, 'proprietario_acompanha'::text])))
nai_acesso_imovel_codigo_fkey: FOREIGN KEY (codigo) REFERENCES imoveis(codigo)
nai_acesso_imovel_pkey: PRIMARY KEY (codigo)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nai_comando_tel, nai_resposta_proprietario

## funções que citam
nai_comando_tel, nai_prosseguir_acesso, nai_resposta_proprietario
