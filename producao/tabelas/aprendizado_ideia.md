# aprendizado_ideia  (tabela, ~127 linhas)
514: as ideias refinadas dos vídeos: sugestão, como é hoje, onde ajuda, prazo; nota do Pedro (barrinha) e nota_claude.

## colunas
id  bigint  NOT NULL  padrão nextval('aprendizado_ideia_id_seq'::regclass)
numero  integer  NOT NULL
youtube_id  text
titulo  text  NOT NULL
area  text
prazo  text  NOT NULL
nota  integer  NOT NULL
nota_claude  integer  NOT NULL
nota_revisada  boolean  NOT NULL  padrão false
nota_por  text
sugestao  text
como_hoje  text
onde_ajuda  text
porque_prazo  text
do_video  text
criada_em  timestamp with time zone  NOT NULL  padrão now()
mudada_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX aprendizado_ideia_numero_key ON public.aprendizado_ideia USING btree (numero)
CREATE UNIQUE INDEX aprendizado_ideia_pkey ON public.aprendizado_ideia USING btree (id)

## restrições
aprendizado_ideia_nota_check: CHECK (((nota >= 0) AND (nota <= 100)))
aprendizado_ideia_nota_claude_check: CHECK (((nota_claude >= 0) AND (nota_claude <= 100)))
aprendizado_ideia_numero_key: UNIQUE (numero)
aprendizado_ideia_pkey: PRIMARY KEY (id)
aprendizado_ideia_prazo_check: CHECK ((prazo = ANY (ARRAY['curto'::text, 'medio'::text, 'longo'::text])))
aprendizado_ideia_youtube_id_fkey: FOREIGN KEY (youtube_id) REFERENCES aprendizado_video(youtube_id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
aprendizado_gravar, site_aprendizado_ideia_nota

## funções que citam
aprendizado_gravar, site_aprendizado_ideia_nota, site_aprendizado_ideias
