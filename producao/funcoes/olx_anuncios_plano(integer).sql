CREATE OR REPLACE FUNCTION public.olx_anuncios_plano(p_limite integer DEFAULT NULL::integer)
 RETURNS TABLE(acao text, codigo integer, negocio text, ad_id text, motivo text, anuncio jsonb, hash text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_teto   int := greatest(0, coalesce(nullif(regexp_replace(coalesce(olx_cfg('teto'), ''), '\D', '', 'g'), '')::int, 0));
  v_rodada int := greatest(1, coalesce(p_limite, nullif(regexp_replace(coalesce(olx_cfg('por_rodada'), ''), '\D', '', 'g'), '')::int, 10));
  v_ativos int;
  v_n      int := 0;
  r        record;
  v_m      jsonb;
BEGIN
  -- 6.1 o que saiu do cadastro (vendeu, alugou, bloqueou, virou parceiro) sai da OLX
  FOR r IN SELECT a.* FROM privado.olx_anuncio a
            WHERE a.estado IN ('enviado', 'publicado')
               -- 365: a edição foi recusada mas a versão antiga continua no ar
               OR (a.estado IN ('recusado', 'erro') AND a.list_id IS NOT NULL AND a.removido_em IS NULL)
            ORDER BY a.id LOOP
    EXIT WHEN v_n >= v_rodada;
    v_m := olx_anuncio_montar(r.codigo, r.negocio);
    IF v_m->>'barrado' IS NOT NULL THEN
      acao := 'remover'; codigo := r.codigo; negocio := r.negocio; ad_id := r.ad_id; motivo := v_m->>'barrado';
      anuncio := jsonb_build_object('id', r.ad_id, 'operation', 'delete'); hash := NULL;
      v_n := v_n + 1; RETURN NEXT;
    END IF;
  END LOOP;

  -- 6.2 o que mudou no cadastro (valor, fotos, descrição) vai de novo: para a OLX, inserir de novo é editar
  FOR r IN SELECT a.* FROM privado.olx_anuncio a WHERE a.estado = 'publicado' ORDER BY a.id LOOP
    EXIT WHEN v_n >= v_rodada;
    v_m := olx_anuncio_montar(r.codigo, r.negocio);
    IF (v_m->>'ok')::boolean AND v_m->>'hash' IS DISTINCT FROM r.conteudo_hash THEN
      acao := 'atualizar'; codigo := r.codigo; negocio := r.negocio; ad_id := r.ad_id; motivo := 'o cadastro mudou';
      anuncio := v_m->'anuncio'; hash := v_m->>'hash';
      v_n := v_n + 1; RETURN NEXT;
    END IF;
  END LOOP;

  -- 6.3 os novos, do mais recente para o mais antigo, até o teto
  SELECT count(*) INTO v_ativos FROM privado.olx_anuncio a WHERE a.estado IN ('enviado', 'publicado');
  FOR r IN
    SELECT c.codigo, c.negocio, c.m
      FROM olx_anuncios_candidatos() c
      LEFT JOIN privado.olx_anuncio a ON a.codigo = c.codigo AND a.negocio = c.negocio
     WHERE (c.m->>'ok')::boolean
       AND (a.id IS NULL
            OR (a.estado = 'removido' AND NOT a.removido_por_fora)   -- o que alguém apagou na OLX não volta sozinho
            -- o que falhou tenta de novo depois de 6 h; o que a moderação recusou, só se o conteúdo mudou
            OR (a.estado = 'erro' AND coalesce(a.enviado_em, a.criado_em) < now() - interval '6 hours' AND a.tentativas < 5)
            OR (a.estado = 'recusado' AND c.m->>'hash' IS DISTINCT FROM a.conteudo_hash))
     ORDER BY c.codigo DESC, c.negocio
  LOOP
    EXIT WHEN v_n >= v_rodada OR v_ativos >= v_teto;
    acao := 'publicar'; codigo := r.codigo; negocio := r.negocio; ad_id := r.m->>'ad_id'; motivo := NULL;
    anuncio := r.m->'anuncio'; hash := r.m->>'hash';
    v_n := v_n + 1; v_ativos := v_ativos + 1; RETURN NEXT;
  END LOOP;
END
$function$;
