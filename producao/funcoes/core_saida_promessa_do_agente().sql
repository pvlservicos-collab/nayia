CREATE OR REPLACE FUNCTION public.core_saida_promessa_do_agente()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  s   text;
  v_c integer;
BEGIN
  IF NEW.motivo IS DISTINCT FROM 'correcao_do_agente' OR NEW.papel_destino <> 'turno' OR NEW.tipo <> 'texto' THEN
    RETURN NEW;
  END IF;
  s := lower(unaccent(coalesce(NEW.texto, '')));
  -- "vou levar a sua proposta ao proprietário", "vou confirmar com o dono", "vou perguntar ao proprietário"
  -- (o "R$ 2.000" tem ponto: a frase só termina em ! ? ou quebra de linha)
  IF s !~ '\m(vou|vamos|irei)\M[^!?\n]{0,60}\m(levar|passar|confirmar|consultar|perguntar|verificar|checar|falar|ver)\M[^!?\n]{0,80}\m(proprietari[oa]s?|don[oa]s?)\M' THEN
    RETURN NEW;
  END IF;
  v_c := coalesce(NEW.codigo, (regexp_match(s, '(?:codigo|cod\.?|#)\s*(\d{3,5})'))[1]::int);
  IF EXISTS (SELECT 1 FROM core_pendencia p WHERE p.chave = NEW.chave_destino AND p.criado_em > now() - interval '2 hours'
                AND coalesce(p.codigo, 0) = coalesce(v_c, 0)) THEN
    RETURN NEW;                                   -- o agente (ou a Nay) já abriu a dúvida
  END IF;
  INSERT INTO core_pendencia (turno_id, chave, codigo, pergunta, faltou)
  VALUES (NEW.turno_id, NEW.chave_destino, v_c,
          'O agente prometeu ao corretor levar ao proprietário: "' || left(btrim(NEW.texto), 600) || '"',
          ARRAY['promessa do agente (547)']);
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'core_saida_promessa_do_agente: %', SQLERRM;   -- a mensagem do agente sai de qualquer jeito
  RETURN NEW;
END
$function$;
