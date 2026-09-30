-- 003: o estado da conversa (setor estado). Uma linha por pessoa.
-- É a máquina de estados que o sistema velho não tinha (pergunta 13): os
-- filtros que o corretor já respondeu ficam AQUI, e ninguém descobre "o que
-- ela já perguntou" por regex sobre o que ela mesma enviou (pergunta 12).
CREATE TABLE IF NOT EXISTS core_conversa (
  chave              text PRIMARY KEY,
  estado             text NOT NULL DEFAULT 'NOVO' CHECK (estado IN (
                       'NOVO', 'IDENTIFICANDO',
                       'FILTRO_FINALIDADE', 'FILTRO_TIPO', 'FILTRO_TETO', 'FILTRO_REGIAO',
                       'BUSCA', 'APRESENTADO', 'VISITA_PEDIDA',
                       'ESCALADO', 'HUMANO', 'SILENCIO')),
  estado_desde       timestamptz NOT NULL DEFAULT now(),
  -- os quatro filtros, na ordem de ORDEM_FILTROS. NULL = ainda não sabe.
  -- 'tanto_faz' é valor válido e conta como preenchido.
  filtro_finalidade  text CHECK (filtro_finalidade IN ('locacao', 'venda', 'ambos', 'tanto_faz')),
  filtro_tipo        text,
  filtro_teto        numeric,
  filtro_teto_tanto_faz boolean NOT NULL DEFAULT false,
  filtro_regiao      text[],
  filtro_regiao_tanto_faz boolean NOT NULL DEFAULT false,
  -- complementos: nunca perguntados, só guardados quando ele diz
  filtro_quartos     int,
  filtro_mobilia     text CHECK (filtro_mobilia IN ('mobiliado', 'semi', 'nao', 'tanto_faz')),
  veio_do_grupo      boolean NOT NULL DEFAULT false,
  -- o imóvel em jogo e de onde ele veio (citação, código, card, busca...)
  foco_codigo        int,
  foco_origem        text,
  foco_desde         timestamptz,
  mostrados          int[] NOT NULL DEFAULT '{}',
  rejeitados         int[] NOT NULL DEFAULT '{}',
  visita_sugerida_em timestamptz,
  visita_pedida      jsonb,
  escalado_motivo    text,
  escalado_ate       timestamptz,
  humano_ate         timestamptz,
  -- trava otimista: duas rajadas da mesma pessoa não sobrescrevem uma à outra
  versao             int NOT NULL DEFAULT 0,
  atualizado_em      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS core_conversa_estado ON core_conversa (estado);
