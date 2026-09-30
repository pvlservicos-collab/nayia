CREATE OR REPLACE FUNCTION public.nai_tipo_da_conversa(p_contato bigint, p_texto text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_chaves text[];
  v_falas  text[] := array[coalesce(p_texto, '')];
BEGIN
  -- as chaves do contato e dos irmaos dele (telefone e @lid), de uma vez
  SELECT coalesce(array_agg(c.chave), '{}'::text[]) INTO v_chaves
    FROM nai_contato c
   WHERE c.id = ANY (nai_contato_irmaos(p_contato)) AND c.chave IS NOT NULL;

  -- os ultimos 30 turnos dele
  v_falas := v_falas || coalesce((
    SELECT array_agg(x.texto ORDER BY x.id DESC) FROM (
      SELECT t.id, t.texto FROM nai_turno t
       WHERE t.contato_id = p_contato AND t.criado_em > now() - interval '30 days'
       ORDER BY t.id DESC LIMIT 30) x), '{}'::text[]);

  -- e as ultimas 30 mensagens. Conversa antiga nunca virou turno: era la
  -- que estava "a casa do nova cidade ainda esta disponivel?" -- o
  -- [telefone …2884], em 11/09.
  v_falas := v_falas || coalesce((
    SELECT array_agg(y.texto ORDER BY y.id DESC) FROM (
      SELECT m.id, m.texto FROM mensagens m
       WHERE nai_chave(m.telefone) = ANY (v_chaves)
         AND m.direcao = 'recebida'
         AND m.criada_em > now() - interval '60 days'
       ORDER BY m.id DESC LIMIT 30) y), '{}'::text[]);

  RETURN nai_tipo_das_falas(v_falas);
END;
$function$;
