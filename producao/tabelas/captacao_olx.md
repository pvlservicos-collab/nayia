# captacao_olx  (tabela, ~0 linhas)
370: o lead da captação que é dono de anúncio da OLX (a "Nay proprietários da OLX"): o anúncio que já temos e as respostas do roteiro do Pedro. Ter linha aqui troca o prompt e as ferramentas do lead no nay-captacao.

## colunas
lead_id  bigint  NOT NULL
codigo  integer
anuncio  jsonb  NOT NULL  padrão '{}'::jsonb   -- o que já sabemos do imóvel (do cadastro importado da OLX): tipo, negócio, valor, condomínio, taxa, IPTU, andar, sol, áreas, endereço, título e descrição
respostas  jsonb  NOT NULL  padrão '{}'::jsonb   -- {campo: o que o dono disse}, campo = condominio_nome, elevador, taxa_condominio, iptu, lances_escada, bloco, andar, torre, metragem_terreno, numero_casa, endereco, sol, honorarios, condominio_incluso, outros, outros_detalhe, indicacao
aberto_em  timestamp with time zone
abertura_tentada_em  timestamp with time zone
criado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX captacao_olx_pkey ON public.captacao_olx USING btree (lead_id)

## restrições
captacao_olx_pkey: PRIMARY KEY (lead_id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
captacao_olx_guardar, captacao_olx_novo

## funções que citam
captacao_olx_da_parceria, captacao_olx_encerrar, captacao_olx_guardar, captacao_olx_novo, captacao_olx_perfil, captacao_olx_proxima
