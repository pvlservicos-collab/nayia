# captacoes  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('captacoes_id_seq'::regclass)
link_olx  text  NOT NULL
olx_id  text
dados_olx  jsonb
campos  jsonb  NOT NULL  padrão '{}'::jsonb
status  text  NOT NULL  padrão 'rascunho'::text
codigo_no_site  text
erro  text
quem  text
criado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX captacoes_status_idx ON public.captacoes USING btree (status, atualizado_em DESC)
CREATE UNIQUE INDEX captacao_um_por_anuncio ON public.captacoes USING btree (nay_chave_do_link(link_olx))
CREATE UNIQUE INDEX captacoes_pkey ON public.captacoes USING btree (id)

## restrições
captacao_codigo_e_numero: CHECK (((codigo_no_site IS NULL) OR (codigo_no_site ~ '^[0-9]+$'::text)))
captacao_erro_tem_motivo: CHECK (((status <> 'erro'::text) OR (erro IS NOT NULL)))
captacao_link_nao_vazio: CHECK ((btrim(link_olx) <> ''::text))
captacao_link_tem_chave: CHECK ((nay_chave_do_link(link_olx) IS NOT NULL))
captacao_publicado_tem_codigo: CHECK (((status <> 'publicado'::text) OR (codigo_no_site IS NOT NULL)))
captacao_status_ok: CHECK ((status = ANY (ARRAY['rascunho'::text, 'pronto'::text, 'publicado'::text, 'erro'::text])))
captacoes_pkey: PRIMARY KEY (id)

## gatilhos
CREATE TRIGGER captacoes_atualizado_em BEFORE UPDATE ON public.captacoes FOR EACH ROW EXECUTE FUNCTION nay_captacao_marca_atualizacao()

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
nay_captacao_do_link
