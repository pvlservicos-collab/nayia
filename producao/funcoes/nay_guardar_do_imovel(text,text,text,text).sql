CREATE OR REPLACE FUNCTION public.nay_guardar_do_imovel(p_codigo text, p_assunto text, p_texto text, p_telefone text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_cod text := NULLIF(regexp_replace(coalesce(p_codigo,''),'[^0-9]','','g'),'');
  v_tel text := right(regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g'),8);
  v_ass text := coalesce(nay_assunto_do_imovel(p_assunto),
                         nay_assunto_do_imovel(p_texto));
  v_txt text := btrim(coalesce(p_texto,''));
BEGIN
  -- PAREDE: só o Tel grava. Corretor ensinando a Nay contaminaria o
  -- conhecimento de todo mundo naquele imóvel.
  IF v_tel <> '94717316' THEN
    RETURN 'so o Tel pode gravar informacao de imovel. NAO diga que guardou.';
  END IF;
  IF v_cod IS NULL OR v_txt = '' THEN
    RETURN 'preciso do codigo do imovel e do texto. Nao gravei nada.';
  END IF;
  IF v_ass IS NULL THEN
    RETURN 'nao reconheci o assunto. Os assuntos sao: quitacao, entrada, '
        || 'condicoes_locacao, pet, mobilia, estado, situacao.';
  END IF;
  -- Imóvel fora da carteira não recebe conhecimento novo.
  IF NOT EXISTS (SELECT 1 FROM imoveis i
                  WHERE i.codigo::text = v_cod AND coalesce(i.disponivel, true)) THEN
    RETURN 'o imovel ' || v_cod || ' nao esta disponivel. Nao gravei.';
  END IF;

  INSERT INTO imovel_conhecimento (codigo, assunto, texto, quem_contou)
  VALUES (v_cod, v_ass, v_txt, 'tel')
  ON CONFLICT (codigo, assunto) DO UPDATE
     SET texto = EXCLUDED.texto, atualizado_em = now();

  RETURN 'guardei: ' || v_ass || ' do imovel ' || v_cod
      || '. Da proxima vez que perguntarem isso desse imovel, eu respondo sozinha.';
END;
$function$;
