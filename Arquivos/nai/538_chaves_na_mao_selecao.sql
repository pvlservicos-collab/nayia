-- 538 (Pedro, 30/10/2026): o Chaves na Mão lê uma URL que aponta para o XML dos imóveis que ele escolheu. A escolha da
-- página "Envio Chaves na Mão" passa a ficar guardada no servidor (uma linha só) e o XML da URL
-- (/api/chavesnamao/envio.xml) sai dela. Quem publica é o botão "Publicar na URL" da página.
--
--   privado.cnm_envio_selecao   a escolha publicada: os códigos no ar, os que vão em destaque, quando e quem
--   cnm_envio_selecao()         lê (a URL e a página)
--   cnm_envio_publicar(...)     grava (a página); só aceita códigos que existem, sem repetir, destaque dentro do no ar
BEGIN;

CREATE TABLE IF NOT EXISTS privado.cnm_envio_selecao (
  id            integer PRIMARY KEY CHECK (id = 1),
  ids           integer[] NOT NULL DEFAULT '{}',
  destaques     integer[] NOT NULL DEFAULT '{}',
  atualizado_em timestamptz NOT NULL DEFAULT now(),
  atualizado_por text
);
COMMENT ON TABLE privado.cnm_envio_selecao IS '538: a escolha de imóveis publicada na URL do Chaves na Mão (uma linha); escrita só por cnm_envio_publicar';
INSERT INTO privado.cnm_envio_selecao (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.cnm_envio_selecao()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT jsonb_build_object('ids', to_jsonb(s.ids), 'destaques', to_jsonb(s.destaques),
                            'atualizado_em', s.atualizado_em, 'atualizado_por', s.atualizado_por)
    FROM cnm_envio_selecao s WHERE s.id = 1;
$function$;

CREATE OR REPLACE FUNCTION public.cnm_envio_publicar(p_ids integer[], p_destaques integer[], p_quem text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE v_ids integer[]; v_dest integer[];
BEGIN
  SELECT coalesce(array_agg(c ORDER BY n), '{}') INTO v_ids
    FROM (SELECT c, min(n) AS n FROM unnest(coalesce(p_ids, '{}')) WITH ORDINALITY u(c, n)
           WHERE EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = u.c) GROUP BY c) x;
  SELECT coalesce(array_agg(c ORDER BY n), '{}') INTO v_dest
    FROM (SELECT c, min(n) AS n FROM unnest(coalesce(p_destaques, '{}')) WITH ORDINALITY u(c, n) WHERE c = ANY (v_ids) GROUP BY c) x;
  UPDATE cnm_envio_selecao SET ids = v_ids, destaques = v_dest, atualizado_em = now(), atualizado_por = left(p_quem, 120) WHERE id = 1;
  RETURN cnm_envio_selecao();
END
$function$;

REVOKE ALL ON FUNCTION public.cnm_envio_selecao(), public.cnm_envio_publicar(integer[], integer[], text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cnm_envio_selecao() TO nay_site_leitura, nay_site_escrita;
GRANT EXECUTE ON FUNCTION public.cnm_envio_publicar(integer[], integer[], text) TO nay_site_escrita;

COMMIT;
