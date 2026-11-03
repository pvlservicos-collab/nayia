CREATE OR REPLACE FUNCTION public.site_link_organico_salvar(p jsonb, p_quem text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_cod  text := lower(btrim(coalesce(p->>'codigo', '')));
  v_msg  text := btrim(coalesce(p->>'mensagem', ''));
  v_marca text := btrim(coalesce(p->>'marca', ''));
BEGIN
  IF v_cod !~ '^[a-z0-9][a-z0-9-]{1,39}$' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'O código usa só letras minúsculas, números e hífen (2 a 40).');
  END IF;
  IF btrim(coalesce(p->>'canal', '')) = '' OR btrim(coalesce(p->>'nome', '')) = '' OR v_msg = '' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Preencha o canal, o nome e a mensagem.');
  END IF;
  IF v_marca = '' THEN       -- sem marca: a primeira frase da mensagem depois do "Olá!"
    v_marca := btrim(split_part(regexp_replace(v_msg, '^\s*(ol[aá]|oi|bom dia|boa tarde|boa noite)[!,.]*\s*', '', 'i'), '.', 1));
  END IF;
  IF position(lower(v_marca) IN lower(v_msg)) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'A marca precisa estar dentro da mensagem.');
  END IF;
  IF link_organico_normal(v_marca) !~ '^vim d' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'A marca começa com "Vim do/da/de/dos..." (é assim que o lead é reconhecido).');
  END IF;
  IF EXISTS (SELECT 1 FROM privado.link_organico WHERE codigo <> v_cod AND link_organico_normal(marca) = link_organico_normal(v_marca)) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Outro link já usa essa marca: mude a frase para saber de qual veio.');
  END IF;
  INSERT INTO privado.link_organico (codigo, canal, nome, mensagem, marca, utm_source, utm_medium, utm_campaign, ativo, criado_por)
  VALUES (v_cod, btrim(p->>'canal'), btrim(p->>'nome'), v_msg, v_marca,
          coalesce(nullif(btrim(p->>'utm_source'), ''), v_cod), coalesce(nullif(btrim(p->>'utm_medium'), ''), 'organico'),
          coalesce(nullif(btrim(p->>'utm_campaign'), ''), 'organico'), coalesce((p->>'ativo')::boolean, true), p_quem)
  ON CONFLICT (codigo) DO UPDATE SET canal = EXCLUDED.canal, nome = EXCLUDED.nome, mensagem = EXCLUDED.mensagem,
    marca = EXCLUDED.marca, utm_source = EXCLUDED.utm_source, utm_medium = EXCLUDED.utm_medium,
    utm_campaign = EXCLUDED.utm_campaign, ativo = EXCLUDED.ativo, atualizado_em = now();
  RETURN jsonb_build_object('ok', true, 'codigo', v_cod);
END
$function$;
