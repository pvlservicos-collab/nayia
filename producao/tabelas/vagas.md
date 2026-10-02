# vagas  (tabela, ~25 linhas)

## colunas
id  integer  NOT NULL  padrão nextval('vagas_id_seq'::regclass)
horario  time without time zone  NOT NULL
tipo_recorrencia  text  NOT NULL
dias_semana  integer[]
data_unica  date
codigos  text[]  NOT NULL  padrão '{}'::text[]
criado_em  timestamp with time zone  NOT NULL  padrão now()
categoria  text
negocio  text
destino  text

## índices
CREATE UNIQUE INDEX vagas_imovel_unica ON public.vagas USING btree (codigos, COALESCE(destino, ''::text), horario, tipo_recorrencia, COALESCE(dias_semana, '{}'::integer[])) WHERE ((categoria IS NULL) AND (COALESCE(array_length(codigos, 1), 0) > 0))
CREATE UNIQUE INDEX vagas_lista_unica ON public.vagas USING btree (categoria, negocio, destino, horario, tipo_recorrencia, COALESCE(dias_semana, '{}'::integer[])) WHERE (categoria IS NOT NULL)
CREATE UNIQUE INDEX vagas_pkey ON public.vagas USING btree (id)

## restrições
vagas_check: CHECK ((((tipo_recorrencia = 'diaria'::text) AND (dias_semana IS NULL) AND (data_unica IS NULL)) OR ((tipo_recorrencia = 'semanal'::text) AND (dias_semana IS NOT NULL) AND (data_unica IS NULL)) OR ((tipo_recorrencia = 'unica'::text) AND (dias_semana IS NULL) AND (data_unica IS NOT NULL))))
vagas_dias_semana_check: CHECK (((dias_semana IS NULL) OR (dias_semana <@ ARRAY[0, 1, 2, 3, 4, 5, 6])))
vagas_imovel_ou_lista: CHECK ((((categoria IS NULL) AND (negocio IS NULL)) OR ((categoria IS NOT NULL) AND (negocio IS NOT NULL) AND (destino IS NOT NULL) AND (COALESCE(array_length(codigos, 1), 0) = 0))))
vagas_pkey: PRIMARY KEY (id)
vagas_tipo_recorrencia_check: CHECK ((tipo_recorrencia = ANY (ARRAY['diaria'::text, 'semanal'::text, 'unica'::text])))

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
captacao_ficha, captacao_ficha_aviso, crm_imovel_candidatos, crm_imovel_para_cadastro, nai_bloco_oferta, nai_cadastro_absorver, nai_cadastro_importar, nai_cadastro_ler, nai_card_do_banco, nai_e_anuncio_dele, nai_e_comando_publicador, nai_ficha_completa, nai_imovel_novo_falta, nai_imovel_novo_pergunta, nai_imovel_novo_subir, nai_imovel_pontos, nai_palavra_comum, nai_pedido_de_perfil, nai_resposta_da_base, nai_sec_guardar_do_imovel, nay_comando, nay_tem_numero_de_unidade, site_imovel_publico
