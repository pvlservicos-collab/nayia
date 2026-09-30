-- Decide se as fotos devem ser enviadas.
--
-- O CASO QUE ISSO RESOLVE (André, 30/08): a Nay perguntou "quer que eu
-- mande as fotos?" e ele respondeu **"Por favor"**. O gatilho antigo lia
-- só palavra de foto no texto dele -- "Por favor" não tem nenhuma -- e as
-- fotos nunca saíram. Ela então prometeu quatro vezes ("as fotos serão
-- enviadas agora", "aguarda só um instante") sem nada atrás.
--
-- O consentimento nem sempre vem como pedido. Muitas vezes é resposta à
-- pergunta DELA. Então são dois caminhos:
--   1. ele pediu com todas as letras: "manda as fotos", "tem a frente?"
--   2. ela ofereceu na fala anterior E ele respondeu que sim
--
-- O SEGUNDO CASO (Gustavo, 01/09): por áudio ele disse "não, as fotos eu
-- já tenho, agora eu quero saber só o valor de entrada" -- e recebeu o
-- card e as 11 fotos outra vez. Duas causas somadas, as duas aqui:
--   * a frase DELE tem a palavra "fotos", então o caminho 1 abria;
--   * pior, o texto que chegava nesta função não era o dele: o nó
--     `Juntar mensagens` embrulha áudio num envelope que terminava em
--     "Antes de mandar imovel ou fotos, repita..." -- texto de SISTEMA com
--     a palavra "fotos" dentro. Para 100% dos áudios, qualquer que fosse o
--     conteúdo, este portão devolvia true.
-- O envelope foi separado do texto do corretor (campo `textoCru`) e a
-- negação virou parede aqui, no caminho 0.
--
-- POR QUE EM SQL E NÃO NO NÓ DE CÓDIGO: saber o que ela falou antes exige
-- ler `nay_memoria`, e nó de código do n8n não acessa banco. Além disso é
-- o padrão do projeto: a regra mora na consulta, não em instrução solta
-- que o modelo pode ponderar.
--
--   docker cp consentimento_fotos.sql nay-postgres:/tmp/cf.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/cf.sql

CREATE OR REPLACE FUNCTION nay_deve_mandar_fotos(
  p_telefone text,
  p_escreveu text
) RETURNS boolean
LANGUAGE plpgsql STABLE AS $fn$
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
$fn$;
