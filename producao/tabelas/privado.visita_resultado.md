# privado.visita_resultado  (tabela, ~56 linhas)

## colunas
origem  text  NOT NULL
visita_id  bigint  NOT NULL
resultado  text  NOT NULL
marcado_por  text
marcado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX visita_resultado_pkey ON privado.visita_resultado USING btree (origem, visita_id)

## restrições
visita_resultado_origem_check: CHECK ((origem = ANY (ARRAY['parceria'::text, 'olx'::text])))
visita_resultado_pkey: PRIMARY KEY (origem, visita_id)
visita_resultado_resultado_check: CHECK ((resultado = ANY (ARRAY['desistiu'::text, 'realizada'::text, 'fechou'::text])))

## permissões
(só o dono)

## funções que escrevem aqui
site_painel_visita_marcar

## funções que citam
site_painel_metricas, site_painel_visita_marcar, site_painel_visitas
