CREATE OR REPLACE FUNCTION public.nay_gravar_conhecimento(p_codigo text, p_assunto text, p_texto text, p_quem text)
 RETURNS void
 LANGUAGE sql
AS $function$
  INSERT INTO imovel_conhecimento (codigo, assunto, texto, quem_contou)
  VALUES (p_codigo, p_assunto, p_texto, p_quem)
  ON CONFLICT (codigo, assunto) DO UPDATE
     SET texto = EXCLUDED.texto,
         quem_contou = EXCLUDED.quem_contou,
         atualizado_em = now();
$function$;
