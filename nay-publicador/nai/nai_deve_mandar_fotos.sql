CREATE OR REPLACE FUNCTION public.nai_deve_mandar_fotos(p_contato bigint, p_telefone text, p_escreveu text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE v_txt text := lower(unaccent(btrim(coalesce(p_escreveu, ''))));
BEGIN
  -- ELE DISSE QUE JA TEM. A negacao precisa estar COLADA a palavra de foto, na
  -- mesma oracao: "ja tenho o endereco, agora me manda as fotos" e pedido, nao
  -- recusa. E o pedido explicito vence a negacao -- foi o caso do Andre, em
  -- 01/09: "ja recebi o card mas nao recebi as fotos, manda por favor".
  IF (v_txt ~ ('(ja\s+(tenho|recebi|vi|peguei)|nao\s+precisa|voce\s+ja\s+'
               || '(me\s+)?(mandou|enviou))[^.,;!?]{0,30}\m(foto|fotos|imagem|imagens|fachada|material)\M')
      OR v_txt ~ ('\m(foto|fotos|imagem|imagens|fachada|material)\M[^.,;!?]{0,30}'
                  || '(ja\s+(tenho|recebi|vi|peguei)|nao\s+precisa)'))
     AND v_txt !~ '\m(manda|mande|envia|envie|me\s+passa|por\s+favor)\M' THEN
    RETURN false;
  END IF;

  -- Fora isso: SEMPRE (Tel, 16/09). Quem chega perto de um imovel recebe as
  -- informacoes e as fotos na mesma resposta.
  RETURN true;
END;
$function$
;
