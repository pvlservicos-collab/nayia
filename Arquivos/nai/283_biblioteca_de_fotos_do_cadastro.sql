-- 283 (03/10/2026): A BIBLIOTECA DE FOTOS DO CADASTRO.
--
-- Pedro, 03/10: "cria no cadastro de imóveis uma biblioteca de subir imagens manualmente, abre um popup e eu
-- posso subir do meu computador direto em um imóvel que já existe no menu editar, ou lá em criar imóvel tenha
-- esse campo que monta a galeria, e eu posso mudar a ordem das fotos" / "excluir fotos também".
--
-- O ARQUIVO mora na pasta que o site já serve (fotos-captacao/manual/<código>/), gravado pela API do site; aqui
-- fica a linha em imovel_fotos e a ORDEM (a primeira é a capa: site, Nay, card e colagem leem por `ordem`).
-- A role do site tem só INSERT e DELETE em imovel_fotos (colunas contadas), nada de UPDATE: reordenar passa por
-- estas funções, e só por elas.
--
-- A MARCA "EDITADO À MÃO" (imovel_fotos_manual). A conferência diária das fotos (nay-publicador/varrer_fotos.py)
-- APAGA E REGRAVA as fotos de todo imóvel publicado no site antigo cujo anúncio difere do banco: sem a marca, a
-- ordem que o Pedro escolheu, a foto que ele apagou e a que ele subiu voltariam ao que o site antigo tem no dia
-- seguinte. Com a marca, a varredura (as duas partes) e `nai_gravar_fotos_do_site` deixam o imóvel em paz.
-- Tabela à parte, e não coluna em `imoveis`: ALTER em `imoveis` trava a Nay (ver ensaio-sem-ddl-no-banco-vivo).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS public.imovel_fotos_manual (
  codigo      integer PRIMARY KEY,
  editado_em  timestamptz NOT NULL DEFAULT now(),
  acoes       integer NOT NULL DEFAULT 0
);
COMMENT ON TABLE public.imovel_fotos_manual IS
  'Imóvel cujas fotos foram mexidas à mão na biblioteca do cadastro (283, 03/10/2026). A varredura de fotos do site antigo não mexe nele.';
GRANT SELECT ON public.imovel_fotos_manual TO nay_leitura;

CREATE OR REPLACE FUNCTION public.site_fotos_marcar_manual(p_codigo integer)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  INSERT INTO imovel_fotos_manual (codigo, editado_em, acoes) VALUES (p_codigo, now(), 1)
  ON CONFLICT (codigo) DO UPDATE SET editado_em = now(), acoes = imovel_fotos_manual.acoes + 1;
$function$;

-- a ordem 1..n e a capa na primeira, depois de qualquer mudança
CREATE OR REPLACE FUNCTION public.site_fotos_renumerar(p_codigo integer)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  UPDATE imovel_fotos f SET ordem = x.n, e_capa = (x.n = 1)
    FROM (SELECT id, row_number() OVER (ORDER BY ordem NULLS LAST, id) AS n FROM imovel_fotos WHERE codigo = p_codigo) x
   WHERE f.id = x.id AND (f.ordem IS DISTINCT FROM x.n OR f.e_capa IS DISTINCT FROM (x.n = 1));
$function$;

CREATE OR REPLACE FUNCTION public.site_fotos_lista(p_codigo integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
    'codigo', p_codigo,
    'existe', EXISTS (SELECT 1 FROM imoveis WHERE codigo = p_codigo),
    'manual', EXISTS (SELECT 1 FROM imovel_fotos_manual WHERE codigo = p_codigo),
    'fotos', coalesce((SELECT jsonb_agg(jsonb_build_object('id', f.id, 'url', f.url, 'ordem', f.ordem,
                                                           'capa', coalesce(f.e_capa, false),
                                                           'do_site_antigo', f.url ~ '^https://imobeasy\.com/')
                                        ORDER BY f.ordem NULLS LAST, f.id)
                         FROM imovel_fotos f WHERE f.codigo = p_codigo AND coalesce(f.url, '') <> ''), '[]'::jsonb));
$function$;

CREATE OR REPLACE FUNCTION public.site_foto_adicionar(p_codigo integer, p_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_id integer; v_ordem integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = p_codigo) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'imóvel não encontrado');
  END IF;
  -- só o arquivo que a própria API gravou na pasta deste imóvel
  IF coalesce(p_url, '') !~ ('^https://imobeasy\.online/fotos-captacao/manual/' || p_codigo || '/[A-Za-z0-9_-]+\.(jpg|png|webp)$') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'endereço de foto inválido');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('imovel_fotos'), p_codigo);
  IF EXISTS (SELECT 1 FROM imovel_fotos WHERE codigo = p_codigo AND url = p_url) THEN
    RETURN jsonb_build_object('ok', true, 'ja', true);
  END IF;
  SELECT coalesce(max(ordem), 0) + 1 INTO v_ordem FROM imovel_fotos WHERE codigo = p_codigo;
  INSERT INTO imovel_fotos (codigo, ordem, url, e_capa) VALUES (p_codigo, v_ordem, p_url, false) RETURNING id INTO v_id;
  PERFORM site_fotos_renumerar(p_codigo);
  PERFORM site_fotos_marcar_manual(p_codigo);
  RETURN jsonb_build_object('ok', true, 'id', v_id, 'ordem', (SELECT ordem FROM imovel_fotos WHERE id = v_id));
END;
$function$;

CREATE OR REPLACE FUNCTION public.site_fotos_ordenar(p_codigo integer, p_ids integer[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_todas integer[];
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('imovel_fotos'), p_codigo);
  SELECT array_agg(id ORDER BY id) INTO v_todas FROM imovel_fotos WHERE codigo = p_codigo AND coalesce(url, '') <> '';
  -- a ordem nova tem de trazer TODAS as fotos do imóvel, cada uma uma vez: a tela pode estar velha
  IF v_todas IS NULL OR p_ids IS NULL OR cardinality(p_ids) <> cardinality(v_todas)
     OR (SELECT array_agg(x ORDER BY x) FROM unnest(p_ids) x) IS DISTINCT FROM v_todas THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'as fotos mudaram enquanto a tela estava aberta: recarregue');
  END IF;
  UPDATE imovel_fotos f SET ordem = x.n, e_capa = (x.n = 1)
    FROM unnest(p_ids) WITH ORDINALITY x(id, n)
   WHERE f.id = x.id AND f.codigo = p_codigo;
  PERFORM site_fotos_marcar_manual(p_codigo);
  RETURN jsonb_build_object('ok', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.site_foto_apagar(p_codigo integer, p_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_url text;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('imovel_fotos'), p_codigo);
  DELETE FROM imovel_fotos WHERE id = p_id AND codigo = p_codigo RETURNING url INTO v_url;
  IF v_url IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'foto não encontrada (já foi excluída?)');
  END IF;
  PERFORM site_fotos_renumerar(p_codigo);
  PERFORM site_fotos_marcar_manual(p_codigo);
  RETURN jsonb_build_object('ok', true, 'url', v_url,
                            'restam', (SELECT count(*) FROM imovel_fotos WHERE codigo = p_codigo));
END;
$function$;

-- a varredura do site antigo não repõe foto em imóvel mexido à mão (quem apagou tudo quis assim)
CREATE OR REPLACE FUNCTION public.nai_gravar_fotos_do_site(p_lote jsonb)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  e jsonb; v_cod int; v_urls text[]; n int := 0; i int;
BEGIN
  FOR e IN SELECT * FROM jsonb_array_elements(coalesce(p_lote, '[]'::jsonb)) LOOP
    v_cod := NULLIF(regexp_replace(coalesce(e->>'codigo', ''), '\D', '', 'g'), '')::int;
    -- mantem a ordem do site (a capa primeiro), sem repetir URL
    SELECT array_agg(u ORDER BY ord) INTO v_urls FROM (
      SELECT u, min(ord) AS ord FROM jsonb_array_elements_text(coalesce(e->'urls', '[]'::jsonb)) WITH ORDINALITY x(u, ord)
       WHERE u ~ '^https://imobeasy\.com/system/pictures/' GROUP BY u) y;
    IF v_cod IS NULL OR v_urls IS NULL OR NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = v_cod) THEN CONTINUE; END IF;
    IF EXISTS (SELECT 1 FROM imovel_fotos WHERE codigo = v_cod) THEN CONTINUE; END IF;
    IF EXISTS (SELECT 1 FROM imovel_fotos_manual WHERE codigo = v_cod) THEN CONTINUE; END IF;   -- 283
    FOR i IN 1..array_length(v_urls, 1) LOOP
      INSERT INTO imovel_fotos (codigo, ordem, url, e_capa) VALUES (v_cod, i, v_urls[i], i = 1);
      n := n + 1;
    END LOOP;
  END LOOP;
  RETURN n;
END;
$function$;

REVOKE ALL ON FUNCTION public.site_fotos_marcar_manual(integer), public.site_fotos_renumerar(integer),
  public.site_fotos_lista(integer), public.site_foto_adicionar(integer, text),
  public.site_fotos_ordenar(integer, integer[]), public.site_foto_apagar(integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_fotos_lista(integer), public.site_foto_adicionar(integer, text),
  public.site_fotos_ordenar(integer, integer[]), public.site_foto_apagar(integer, integer) TO nay_site_escrita;

COMMIT;
