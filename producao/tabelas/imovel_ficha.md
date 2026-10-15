# imovel_ficha  (tabela, ~341 linhas)
191: a ficha completa do anúncio (imobeasy.com/anuncios/<codigo>), lida por ficha_do_anuncio.py a cada 3 h. É a base que a Nay consulta para responder sobre o imóvel.

## colunas
codigo  integer  NOT NULL
encontrado  boolean  NOT NULL  padrão true
campos  jsonb  NOT NULL  padrão '{}'::jsonb
caracteristicas_imovel  text[]  NOT NULL  padrão '{}'::text[]
caracteristicas_condominio  text[]  NOT NULL  padrão '{}'::text[]
descricao  text
observacoes  text
card  text
valor_venda  numeric
valor_aluguel  numeric
lido_em  timestamp with time zone
tentado_em  timestamp with time zone  NOT NULL  padrão now()
erro  text

## índices
CREATE UNIQUE INDEX imovel_ficha_pkey ON public.imovel_ficha USING btree (codigo)

## restrições
imovel_ficha_pkey: PRIMARY KEY (codigo)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_leitura, só nestas colunas: SELECT(codigo, caracteristicas_condominio)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
nai_bloco_oferta, nai_card_do_imovel, nai_ficha_caracteristicas, nai_ficha_completa, nai_ficha_texto_livre, nai_ficha_valor, nai_imovel_tem_elevador, nai_mobilia_da_lista, site_imovel_publico
