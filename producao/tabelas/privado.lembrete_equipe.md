# privado.lembrete_equipe  (tabela, ~0 linhas)
375: lembrete da equipe no sininho do admin do site (texto + dia, até clicar em Feito).

## colunas
id  bigint  NOT NULL  padrão nextval('privado.lembrete_equipe_id_seq'::regclass)
texto  text  NOT NULL
dia  date  NOT NULL
criado_em  timestamp with time zone  NOT NULL  padrão now()
feito_em  timestamp with time zone
apagado_em  timestamp with time zone

## índices
CREATE INDEX lembrete_equipe_aberto ON privado.lembrete_equipe USING btree (dia) WHERE ((feito_em IS NULL) AND (apagado_em IS NULL))
CREATE UNIQUE INDEX lembrete_equipe_pkey ON privado.lembrete_equipe USING btree (id)

## restrições
lembrete_equipe_pkey: PRIMARY KEY (id)
lembrete_equipe_texto_check: CHECK (((length(btrim(texto)) >= 1) AND (length(btrim(texto)) <= 1000)))

## permissões
(só o dono)

## funções que escrevem aqui
site_lembrete_apagar, site_lembrete_criar, site_lembrete_feito

## funções que citam
site_lembrete_apagar, site_lembrete_criar, site_lembrete_feito, site_lembretes
