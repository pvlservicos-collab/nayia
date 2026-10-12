CREATE OR REPLACE FUNCTION public.condominio_google_marcar()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  TEXTOS text[] := ARRAY['logradouro', 'numero', 'cidade', 'estado', 'cep', 'bairro',
                         'torres', 'andares', 'aptos_por_andar', 'elevador', 'unidades',
                         'construtora', 'ano_construcao', 'observacao'];
  LISTAS text[] := ARRAY['lazer', 'seguranca', 'comodidades'];
  marca  text[] := coalesce(NEW.campos_google, '{}');
  k      text;
  novo   text;
  antigo text;
  bate   boolean;
  v_nova  text[];   -- a lista como está sendo gravada
  v_velha text[];   -- a mesma lista antes desta escrita
  v_sug   text[];   -- o que a pesquisa sugeriu, normalizado
  v_tem   text[];   -- v_nova normalizada, para cruzar com v_sug
BEGIN
  -- sem pesquisa não há o que marcar, mas o que já estava marcado
  -- continua valendo (a sugestão pode ter sido limpa depois)
  IF NEW.ia_sugestao IS NULL THEN
    RETURN NEW;
  END IF;

  FOREACH k IN ARRAY TEXTOS LOOP
    novo := to_jsonb(NEW) ->> k;
    IF TG_OP = 'UPDATE' THEN
      antigo := to_jsonb(OLD) ->> k;
      CONTINUE WHEN novo IS NOT DISTINCT FROM antigo;      -- não mudou: não reavalia
    END IF;
    bate := condominio_google_bate(k, novo, NEW.ia_sugestao);
    IF bate AND NOT (k = ANY(marca)) THEN
      marca := array_append(marca, k);
    ELSIF NOT bate AND k = ANY(marca) THEN
      marca := array_remove(marca, k);                     -- o Tel reescreveu: o selo cai
    END IF;
  END LOOP;

  -- as listas: marca se o que está guardado tem ALGUM item que veio da
  -- pesquisa (as três listas são somadas, não substituídas, então "metade
  -- minha metade do Google" é o caso normal e ainda merece o selo)
  FOREACH k IN ARRAY LISTAS LOOP
    v_nova := CASE k WHEN 'lazer' THEN NEW.lazer WHEN 'seguranca' THEN NEW.seguranca ELSE NEW.comodidades END;
    IF TG_OP = 'UPDATE' THEN
      v_velha := CASE k WHEN 'lazer' THEN OLD.lazer WHEN 'seguranca' THEN OLD.seguranca ELSE OLD.comodidades END;
      CONTINUE WHEN v_nova IS NOT DISTINCT FROM v_velha;
    END IF;
    IF coalesce(jsonb_typeof(NEW.ia_sugestao->k), '') <> 'array' THEN
      marca := array_remove(marca, k);
      CONTINUE;
    END IF;
    SELECT coalesce(array_agg(c), '{}') INTO v_sug
      FROM jsonb_array_elements_text(NEW.ia_sugestao->k) x,
           LATERAL condominio_google_chave(x) c WHERE c IS NOT NULL;
    SELECT coalesce(array_agg(c), '{}') INTO v_tem
      FROM unnest(coalesce(v_nova, '{}')) y,
           LATERAL condominio_google_chave(y) c WHERE c IS NOT NULL;
    bate := v_sug && v_tem;
    IF bate AND NOT (k = ANY(marca)) THEN
      marca := array_append(marca, k);
    ELSIF NOT bate AND k = ANY(marca) THEN
      marca := array_remove(marca, k);
    END IF;
  END LOOP;

  -- '{}' e não NULL: a coluna é NOT NULL DEFAULT '{}', igual a lazer,
  -- seguranca e comodidades. NULL aqui derrubava todo UPDATE da ficha
  -- cujos campos vigiados não mudassem (pego ao gravar a pesquisa).
  NEW.campos_google := coalesce(
    (SELECT array_agg(DISTINCT m ORDER BY m) FROM unnest(marca) m), '{}');
  RETURN NEW;
END;
$function$;
