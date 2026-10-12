# corretores  (tabela, ~1564 linhas)

## colunas
telefone  text  NOT NULL
nome  text
creci  text
ativo  boolean  padrão true
no_shows  integer  padrão 0
ultima_interacao  timestamp with time zone
origem  text
aprovado  boolean  NOT NULL  padrão false
criado_em  timestamp with time zone  NOT NULL  padrão now()
nome_origem  text
nome_visto_em  timestamp with time zone
pode_falar  boolean  NOT NULL  padrão false
fonte  text
grupos  text[]
no_grupo_em  timestamp with time zone

## índices
CREATE INDEX corretores_chave_idx ON public.corretores USING btree (nai_chave(telefone))
CREATE UNIQUE INDEX corretores_pkey ON public.corretores USING btree (telefone)
CREATE UNIQUE INDEX corretores_telefone_uk ON public.corretores USING btree (telefone)

## restrições
corretores_pkey: PRIMARY KEY (telefone)
corretores_telefone_uk: UNIQUE (telefone)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_leitura, só nestas colunas: SELECT(telefone, nome, ativo, no_shows, ultima_interacao, aprovado, criado_em)

## funções que escrevem aqui
nai_decidir_corretor, nai_guardar_dados_visita, nai_resultado_visita, nai_sincronizar_grupos, nay_sincronizar_nome

## funções que citam
captacao_fora_da_campanha, crm_anuncio_decidir, crm_grupo_pessoas, crm_grupos_conhecidos, crm_nay_voltar, crm_olx_conta_preparar, crm_parceria_marcas, crm_visitas, nai_abrir_turno, nai_dados_corretor, nai_decidir_corretor, nai_deve_atender, nai_e_proprietario_contato, nai_enfileirar_cortesia, nai_guardar_dados_visita, nai_liberar_saida, nai_perguntar_se_e_corretor, nai_pode_falar, nai_resultado_visita, nai_sincronizar_grupos, nai_tel_com_a_conversa, nay_comando, nay_entregas_devidas, nay_escalar, nay_nome_de_pessoa, nay_pendencias_esquecidas, nay_responder_conversando, nay_sincronizar_nome, site_me_envia_ranking, site_publicos_disparo
