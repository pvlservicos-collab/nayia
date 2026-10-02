# captacao_fotos  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('captacao_fotos_id_seq'::regclass)
captacao_id  bigint  NOT NULL
ordem  integer  NOT NULL
url_olx  text  NOT NULL
baixada_em  timestamp with time zone
caminho  text
bytes  integer
e_capa  boolean  NOT NULL  padrão false
erro  text

## índices
CREATE UNIQUE INDEX captacao_foto_ordem_unica ON public.captacao_fotos USING btree (captacao_id, ordem)
CREATE UNIQUE INDEX captacao_fotos_pkey ON public.captacao_fotos USING btree (id)
CREATE UNIQUE INDEX captacao_foto_uma_capa ON public.captacao_fotos USING btree (captacao_id) WHERE e_capa
CREATE UNIQUE INDEX captacao_foto_url_unica ON public.captacao_fotos USING btree (captacao_id, url_olx)

## restrições
captacao_fotos_captacao_id_fkey: FOREIGN KEY (captacao_id) REFERENCES captacoes(id) ON DELETE CASCADE
captacao_fotos_pkey: PRIMARY KEY (id)
foto_baixada_tem_caminho: CHECK (((baixada_em IS NULL) OR (caminho IS NOT NULL)))
foto_bytes_positivo: CHECK (((bytes IS NULL) OR (bytes > 0)))
foto_ordem_positiva: CHECK ((ordem >= 1))
foto_ou_baixou_ou_falhou: CHECK (((baixada_em IS NULL) OR (erro IS NULL)))

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
