CREATE OR REPLACE FUNCTION public.nai_re_nega_foto()
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT '(n[ãa]o (tenho|temos|tem|h[áa]|encontrei|achei|localizei|possuo|consegui|disponho)[^.?!\n]{0,60}(fotos?|imagens?|imagem)'
      || '|sem (as |nenhuma )?(fotos?|imagens?)'
      || '|(fotos?|imagens?)[^.?!\n]{0,40}(n[ãa]o (est[ãa]o|tem|h[áa]|dispon|encontr|cadastr)|indispon))';
$function$
;
