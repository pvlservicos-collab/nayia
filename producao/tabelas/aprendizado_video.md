# aprendizado_video  (tabela, ~0 linhas)
514: os vídeos estudados na rotina de aprendizado (admin › Aprendizado › Ideias refinadas).

## colunas
youtube_id  text  NOT NULL
titulo  text  NOT NULL
quem  text
link  text
data  date  NOT NULL  padrão CURRENT_DATE
duracao  text
defende  text
nao_serve  text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX aprendizado_video_pkey ON public.aprendizado_video USING btree (youtube_id)

## restrições
aprendizado_video_pkey: PRIMARY KEY (youtube_id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
aprendizado_gravar

## funções que citam
aprendizado_gravar, site_aprendizado_ideias
