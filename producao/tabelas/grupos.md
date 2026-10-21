# grupos  (tabela, ~20 linhas)

## colunas
id_grupo  text  NOT NULL
nome  text
ativo  boolean  NOT NULL  padrão true
todas_fotos  boolean  NOT NULL  padrão false
limite_dia  integer  NOT NULL  padrão 5
aceita_venda  boolean  NOT NULL  padrão true
aceita_locacao  boolean  NOT NULL  padrão true
aluguel_minimo  numeric
venda_minima  numeric
so_condominio  boolean  NOT NULL  padrão false
so_comercial  boolean  NOT NULL  padrão false
apelido  text

## índices
CREATE UNIQUE INDEX grupos_apelido_unico ON public.grupos USING btree (apelido) WHERE ((apelido IS NOT NULL) AND (apelido <> 'lotado'::text))
CREATE UNIQUE INDEX grupos_pkey ON public.grupos USING btree (id_grupo)

## restrições
grupos_pkey: PRIMARY KEY (id_grupo)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
captacao_fora_da_campanha, captacao_py_fila_do_disparo, cnm_imovel_montar, crm_grupos_conhecidos, crm_mensagem_citada, nai_card_do_banco, nai_card_do_imovel, nai_comando_tel, nai_enviar_imoveis_para, nai_imagens_do_envio, nai_perguntar_se_e_corretor, nai_quem_atende, nai_resposta_da_base, nai_sincronizar_grupos, nay_imovel_do_disparo, nay_qual_imovel, olx_anuncio_montar, olx_cliente_buscar, olx_pode_receber_parceiro, site_captacao_grupos, site_captacao_grupos_enviar, site_captacao_grupos_enviar_varios, site_captacao_grupos_perguntar, site_grade_agenda, site_grade_metricas, site_grade_opcoes, site_grade_salvar, site_painel_metricas, site_publicos_disparo
