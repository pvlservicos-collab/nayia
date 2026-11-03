-- 577 (Pedro, 03/11/2026: "separa para mandar só o card"): a newsletter de imóveis do blog (406) manda só o CARD do imóvel
-- novo, sem as fotos. Ela continua usando nai_disparo_enfileirar (o mesmo envio do painel); logo depois, as fotos que esse
-- envio pôs na caixa da Nay (o turno criado nesta mesma transação: criado_em = now()) ficam 'bloqueado', com o motivo.
-- Base: producao/funcoes/blog_newsletter_disparar().sql (o que roda hoje), só com o bloco das fotos a mais.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.blog_newsletter_disparar()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE c record; v_cods integer[]; v_res text; v_n integer := 0; v_hora int := extract(hour FROM now() AT TIME ZONE 'America/Manaus');
BEGIN
  IF v_hora < 8 OR v_hora >= 20 THEN RETURN 0; END IF;
  FOR c IN SELECT * FROM blog_newsletter_corretor WHERE ativo ORDER BY id LOOP
    CONTINUE WHEN (SELECT count(*) FROM blog_newsletter_envio e WHERE e.corretor_id = c.id AND e.enviado_em > now() - interval '24 hours') >= 10;
    SELECT array_agg(i.codigo ORDER BY i.criado_em) INTO v_cods
      FROM (SELECT i.codigo, i.criado_em
              FROM imoveis i JOIN core_imovel_busca b ON b.codigo = i.codigo
             WHERE i.criado_em > greatest(c.criado_em, now() - interval '7 days')
               AND b.ofertavel AND NOT coalesce(b.e_parceiro, false) AND coalesce(b.qtd_fotos, 0) > 0
               AND NOT EXISTS (SELECT 1 FROM blog_newsletter_envio e WHERE e.corretor_id = c.id AND e.codigo = i.codigo)
             ORDER BY i.criado_em LIMIT 3) i;
    CONTINUE WHEN v_cods IS NULL;
    BEGIN
      v_res := nai_disparo_enfileirar(c.telefone, v_cods, 'newsletter do blog');
      -- 577: só o card -- as fotos deste envio não saem
      UPDATE nai_saida s SET estado = 'bloqueado', bloqueio = 'newsletter do blog: só o card (577)'
        FROM nai_turno t
       WHERE t.id = s.turno_id AND t.papel = 'tel' AND t.criado_em = now()
         AND t.texto LIKE 'disparo pelo painel (newsletter do blog): %'
         AND s.estado = 'pendente' AND s.tipo = 'imagem';
    EXCEPTION WHEN OTHERS THEN
      v_res := 'erro: ' || SQLERRM;
    END;
    INSERT INTO blog_newsletter_envio (corretor_id, codigo, resultado)
    SELECT c.id, x, left(v_res, 300) FROM unnest(v_cods) x ON CONFLICT DO NOTHING;
    UPDATE blog_newsletter_corretor SET ultimo_envio_em = now() WHERE id = c.id;
    v_n := v_n + cardinality(v_cods);
  END LOOP;
  RETURN v_n;
END
$function$;

COMMIT;
