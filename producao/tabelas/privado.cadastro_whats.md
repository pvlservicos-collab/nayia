# privado.cadastro_whats  (tabela, ~0 linhas)
428: o imóvel que o Tel encaminhou no grupo CADASTRO DE IMÓVEL IMOBEASY, do texto até o cadastro concluído. ficha = o que já se sabe (chaves da API do site); faltam = as perguntas, na ordem; pergunta = a que está no ar no privado.

## colunas
id  bigint  NOT NULL  padrão nextval('privado.cadastro_whats_id_seq'::regclass)
grupo_id  text  NOT NULL
mensagens  text[]  NOT NULL  padrão '{}'::text[]
texto  text
fotos  jsonb  NOT NULL  padrão '[]'::jsonb
contato_tel  text
contato_nome  text
papel  text
codigo  integer
condominio_id  integer
condominio_novo  jsonb   -- o condomínio que ainda não existe: {nome, ...o que ele respondeu}; vira condominios + condominio_ficha quando as perguntas dele acabam
ficha  jsonb  NOT NULL  padrão '{}'::jsonb
faltam  text[]  NOT NULL  padrão '{}'::text[]
pergunta  text
perguntas_feitas  integer  NOT NULL  padrão 0
pergunta_em  timestamp with time zone
cobrada_em  timestamp with time zone
estado  text  NOT NULL  padrão 'juntando'::text
erro  text
criado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()
concluido_em  timestamp with time zone

## índices
CREATE INDEX cadastro_whats_aberto ON privado.cadastro_whats USING btree (estado, atualizado_em) WHERE (estado <> ALL (ARRAY['concluido'::text, 'cancelado'::text]))
CREATE UNIQUE INDEX cadastro_whats_pkey ON privado.cadastro_whats USING btree (id)

## restrições
cadastro_whats_estado_check: CHECK ((estado = ANY (ARRAY['juntando'::text, 'sem_contato'::text, 'na_fila'::text, 'perguntando'::text, 'concluido'::text, 'sem_resposta'::text, 'cancelado'::text, 'erro'::text])))
cadastro_whats_papel_check: CHECK ((papel = ANY (ARRAY['corretor'::text, 'proprietario'::text])))
cadastro_whats_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
nai_abrir_turno

## funções que citam
cadastro_whats_da_parceria, nai_abrir_turno
