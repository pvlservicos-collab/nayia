-- 476: a NAY DOS CORRETORES da busca (Pedro, 22/10/2026: "quando o corretor mandar no PV tenhamos uma Nay que entenda que
-- o cara enviou um imóvel que bate com uma das buscas ativas logo ele é corretor, e cadastre esse imóvel no nosso site,
-- pergunte as informações que faltar do que ele enviou e completando tudo oferte ao cliente o imóvel dele, tanto de quem
-- vem da OLX quanto dos grupos").
--   privado.busca_corretor       a conversa com cada corretor no número de captação: o que ele ofereceu (imovel), para qual
--                                busca, o código do pré-cadastro, a última mensagem lida e o estado
--   privado.busca_corretor_foto  as fotos que ele mandou (a API /api/fotos-captacao/whatsapp guarda em
--                                fotos-captacao/whatsapp-busca/<telefone>/ quando o número é de um corretor da busca)
--   busca_corretor_e(telefone)   o número é de corretor da busca (chamado por uma busca, membro dos grupos, ou cadastrado)
--                                e não é cliente da aba Leads nem dono da campanha

BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.busca_corretor (
  telefone8     text PRIMARY KEY,
  telefone      text NOT NULL,
  nome          text,
  ultima_lida   bigint NOT NULL DEFAULT 0,
  busca         bigint REFERENCES privado.busca_cliente(id) ON DELETE SET NULL,
  codigo        integer,
  imovel        jsonb NOT NULL DEFAULT '{}'::jsonb,
  estado        text NOT NULL DEFAULT 'conversando'
                CHECK (estado IN ('conversando', 'cadastrando', 'ofertado', 'sem_match', 'humano')),
  humano_em     timestamptz,
  criado_em     timestamptz NOT NULL DEFAULT now(),
  atualizado_em timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE privado.busca_corretor IS '476: a conversa da Nay dos corretores (nay-olx olx/buscas.py) com cada corretor que oferece imóvel para uma busca.';

CREATE TABLE IF NOT EXISTS privado.busca_corretor_foto (
  id         bigserial PRIMARY KEY,
  telefone8  text NOT NULL,
  url        text NOT NULL,
  message_id text UNIQUE,
  usada_em   timestamptz,
  em         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS busca_corretor_foto_tel ON privado.busca_corretor_foto (telefone8, id);

CREATE OR REPLACE FUNCTION public.busca_corretor_e(p_telefone text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH t AS (SELECT right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 8) AS t8)
  SELECT length(t.t8) = 8
     AND (EXISTS (SELECT 1 FROM privado.busca_contato c WHERE c.telefone8 = t.t8)
          OR EXISTS (SELECT 1 FROM privado.busca_grupo_membro g WHERE g.telefone8 = t.t8)
          OR EXISTS (SELECT 1 FROM privado.busca_corretor b WHERE b.telefone8 = t.t8))
     AND NOT EXISTS (SELECT 1 FROM privado.olx_lead_whatsapp o WHERE right(o.telefone, 8) = t.t8)
     AND NOT EXISTS (SELECT 1 FROM captacao_leads l WHERE right(regexp_replace(coalesce(l.telefone, ''), '\D', '', 'g'), 8) = t.t8)
    FROM t;
$function$;

COMMIT;
