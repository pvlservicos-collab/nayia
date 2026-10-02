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

  -- 267: O GATILHO DUPLO (Pedro, 02/10: "se ela já mandou o card e o cara disse
  -- para ela mandar, é porque ele quer as fotos"). O card acabou de sair e a
  -- resposta é um "manda aí": o que falta mandar são as fotos. Só vale com imóvel
  -- na frente dele (2 h), em fala curta, e nunca num pedido de busca ("me manda
  -- uma casa no Flores" é pedido de imóvel, não de foto).
  IF p_contato IS NOT NULL AND length(v_txt) <= 40
     AND v_txt ~ '\m(manda|mande|mandar|envia|envie|enviar|encaminha|encaminhe|encaminhar)\M'
     AND v_txt !~ '\m(nao|depois|amanha|mais tarde|outr[oa]s?|opc(ao|oes)|mais)\M'
     -- pedido novo dentro da fala ("me manda uma casa no Flores até 500 mil") não é
     -- "manda aí": tem tipo, número ou é pedido de perfil
     AND v_txt !~ '[0-9]' AND nai_tipo_pedido(p_escreveu) IS NULL
     AND NOT coalesce((nai_pedido_de_perfil(p_escreveu) ->> 'e_pedido')::boolean, false)
     AND coalesce(array_length(nai_imoveis_na_frente(p_contato), 1), 0) >= 1 THEN
    RETURN true;
  END IF;

  -- "sim" à pergunta dela sobre as fotos -- e, desde a 267, a ESCOLHA quando ela
  -- perguntou de qual ("as duas", "os dois", "todas", ou o nome do condomínio)
  IF p_contato IS NOT NULL
     AND (nai_e_sim_curto(p_escreveu)
          OR (length(v_txt) <= 60
              AND (v_txt ~ '\m(as duas|os dois|ambas|ambos|todas|todos|as 2|os 2)\M'
                   OR coalesce(array_length(nai_imovel_pelo_condominio(p_escreveu, coalesce(p_telefone, '')), 1), 0) >= 1))) THEN
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
