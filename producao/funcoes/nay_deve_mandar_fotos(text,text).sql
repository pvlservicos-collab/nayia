CREATE OR REPLACE FUNCTION public.nay_deve_mandar_fotos(p_telefone text, p_escreveu text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_txt  text := lower(btrim(coalesce(p_escreveu,'')));
  v_tel  text := regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g');
  v_ofereceu boolean;
BEGIN
  IF v_txt = '' THEN
    RETURN false;
  END IF;

  -- 0) ELE JÁ TEM. "as fotos eu ja tenho" tem a palavra "fotos" e por isso
  -- passava direto pelo caminho 1 -- foi assim que o Gustavo recebeu o card
  -- e as fotos de novo (01/09) logo depois de dizer que não precisava.
  --
  -- A negação precisa estar COLADA à palavra de foto, na mesma oração (daí
  -- o `[^.,;!?]` no vão): "já tenho o endereço, agora me manda as fotos" é
  -- pedido, não recusa, e a versão sem essa exigência bloqueava os dois.
  --
  -- E o pedido explícito vence a negação, senão isto recria o caso André em
  -- miniatura: "já recebi o card mas não recebi as fotos, manda por favor".
  IF (v_txt ~ ('(j[áa]\s+(tenho|recebi|vi|peguei)|n[ãa]o\s+precisa|voc[êe]\s+j[áa]\s+'
               || '(me\s+)?(mandou|enviou))[^.,;!?]{0,30}\m(foto|fotos|imagem|imagens|fachada|material)\M')
      OR v_txt ~ ('\m(foto|fotos|imagem|imagens|fachada|material)\M[^.,;!?]{0,30}'
                  || '(j[áa]\s+(tenho|recebi|vi|peguei)|n[ãa]o\s+precisa)'))
     -- "mandar" fica de FORA da lista de propósito: "não precisa mandar de
     -- novo" é recusa, e cairia no escape.
     AND v_txt !~ '\m(manda|mande|envia|envie|me\s+passa|por\s+favor)\M' THEN
    RETURN false;
  END IF;

  -- 1) pediu com todas as letras
  IF v_txt ~ '\m(foto|fotos|imagem|imagens|fachada|frente|video|vídeo)\M' THEN
    RETURN true;
  END IF;

  -- 2) respondeu que sim a uma oferta dela.
  -- Curto e afirmativo: "por favor", "sim", "pode", "quero", "manda".
  -- "ok" e "blz" ficam de FORA de propósito: são acusação de recebimento
  -- ("Ok", "No aguardo", "Blz" apareceram na conversa do André DEPOIS do
  -- consentimento) e fariam reenviar tudo a cada mensagem dele.
  IF v_txt !~ '\m(sim|pode|podes|quero|manda|mande|envia|envie|claro|isso|favor|positivo|bora|aceito)\M' THEN
    RETURN false;
  END IF;

  -- A oferta tem que ser recente. Olha as últimas falas DELA na conversa:
  -- se nenhuma citou foto, o "sim" era sobre outra coisa.
  SELECT EXISTS (
    SELECT 1 FROM (
      SELECT message->>'content' AS c
        FROM nay_memoria
       WHERE regexp_replace(session_id,'[^0-9]','','g') = v_tel
         AND message->>'type' = 'ai'
       ORDER BY id DESC LIMIT 3
    ) ultimas
    WHERE lower(coalesce(ultimas.c,'')) ~ '\m(foto|fotos|imagem|imagens|fachada)\M'
  ) INTO v_ofereceu;

  RETURN coalesce(v_ofereceu, false);
END;
$function$;
