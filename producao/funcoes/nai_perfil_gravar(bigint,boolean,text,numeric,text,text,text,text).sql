CREATE OR REPLACE FUNCTION public.nai_perfil_gravar(p_contato bigint, p_novo boolean, p_bairros text, p_teto numeric, p_quartos text, p_mobilia text, p_negocio text, p_tipo text)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE v_id bigint;
BEGIN
  SELECT id INTO v_id FROM nai_perfil_ativo(p_contato);
  IF v_id IS NOT NULL AND p_novo THEN
    UPDATE nai_perfil_cliente SET encerrado_em = now() WHERE id = v_id;
    v_id := NULL;
  END IF;
  IF v_id IS NULL THEN
    INSERT INTO nai_perfil_cliente (contato_id, negocio, tipo, teto, bairros, quartos, mobilia)
    VALUES (p_contato, p_negocio, p_tipo, p_teto, nullif(btrim(coalesce(p_bairros, '')), ''),
            nullif(btrim(coalesce(p_quartos, '')), ''), nullif(btrim(coalesce(p_mobilia, '')), ''))
    RETURNING id INTO v_id;
  ELSE
    UPDATE nai_perfil_cliente SET
      negocio = coalesce(p_negocio, negocio), tipo = coalesce(p_tipo, tipo), teto = coalesce(p_teto, teto),
      bairros = coalesce(nullif(btrim(coalesce(p_bairros, '')), ''), bairros),
      quartos = coalesce(nullif(btrim(coalesce(p_quartos, '')), ''), quartos),
      mobilia = coalesce(nullif(btrim(coalesce(p_mobilia, '')), ''), mobilia),
      atualizado_em = now()
     WHERE id = v_id;
  END IF;
  RETURN v_id;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;   -- anotação auxiliar nunca derruba a busca (ver "estado da conversa não cala")
END $function$;
