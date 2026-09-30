CREATE OR REPLACE FUNCTION public.nai_deve_mandar_fotos(p_contato bigint, p_telefone text, p_escreveu text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE v_txt text := lower(unaccent(btrim(coalesce(p_escreveu, ''))));
BEGIN
  -- 224: FOTO SÓ QUANDO ELE PEDE (Pedro, 30/09). De 16/09 a 30/09 a foto ia
  -- SEMPRE atrás do card, e saía foto de imóvel que ele não pediu -- inclusive
  -- de locação numa conversa de venda. Agora sem pedido vai só o card, que já
  -- tem todas as informações. Pedido é: falar em foto (nai_menciona_foto), pedir
  -- um imóvel claro com "me manda/envia/passa" (nai_pede_envio_do_imovel), ou
  -- dizer "sim" à pergunta dela sobre as fotos.
  IF v_txt = '' THEN
    RETURN false;
  END IF;

  IF (v_txt ~ ('(ja\s+(tenho|recebi|vi|peguei)|nao\s+precisa|voce\s+ja\s+'
               || '(me\s+)?(mandou|enviou))[^.,;!?]{0,30}\m(foto|fotos|imagem|imagens|fachada|material)\M')
      OR v_txt ~ ('\m(foto|fotos|imagem|imagens|fachada|material)\M[^.,;!?]{0,30}'
                  || '(ja\s+(tenho|recebi|vi|peguei)|nao\s+precisa)'))
     AND v_txt !~ '\m(manda|mande|envia|envie|me\s+passa|por\s+favor)\M' THEN
    RETURN false;
  END IF;

  -- a oferta ou o anúncio DELE não é pedido de foto nossa
  IF nai_fala_e_dele(p_escreveu) THEN
    RETURN false;
  END IF;

  IF nai_menciona_foto(p_escreveu) OR nai_pede_envio_do_imovel(p_escreveu, p_telefone) THEN
    RETURN true;
  END IF;

  IF p_contato IS NOT NULL AND nai_e_sim_curto(p_escreveu) THEN
    RETURN coalesce((SELECT lower(unaccent(coalesce(s.texto, ''))) ~ '\m(fotos?|imagens?|videos?)\M[^?]*\?'
                       FROM nai_saida s
                      WHERE s.contato_id = ANY (nai_contato_irmaos(p_contato))
                        AND s.tipo = 'texto' AND s.estado = 'enviado'
                        AND s.criado_em > now() - interval '2 hours'
                      ORDER BY s.id DESC LIMIT 1), false);
  END IF;

  RETURN false;
END;
$function$;
