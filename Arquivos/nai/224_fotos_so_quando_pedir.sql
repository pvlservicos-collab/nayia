-- 224 (30/09/2026): FOTO SÓ QUANDO ELE PEDE, E IDENTIFICAÇÃO FORTE DE CASA/APTO.
-- Pedro: "a nay tá confundindo muito entre casa e apartamento e entre locação e
-- venda, preciso que isso seja uma identificação forte, e ela só manda a foto
-- depois de obrigatoriamente saber isso para ela não mandar várias fotos de
-- imóveis errados para o corretor, e as fotos não quero mais que envie por padrão
-- junto com os cards, quero que ela seja enviada quando tiver uma menção a fotos,
-- ou o corretor pedir em um imóvel claro 'envia', 'me manda', e é claro quando o
-- corretor pedir fotos diretamente; até lá ela não manda fotos, faz uma boa
-- identificação e aí vai mandando os cards com todas as informações".
--
-- Medido antes (29-30/09): 77 turnos com foto em 10 dias, só 11 com pedido de foto.
-- Casos: numa conversa de VENDA, "Tens jardim das cerejeiras?" levou 24 fotos de
-- um de LOCAÇÃO (o texto foi barrado, as fotos saíram sozinhas); "descartou o Life
-- por ser só 1 vaga" levou 13 fotos do Life; o Marcio pediu apartamento no Smart
-- Tower Itapuranga e recebeu "Casa nesse perfil eu não tenho" + 94 fotos de uma
-- casa de R$ 4 mi, e os apartamentos certos foram barrados como "tipo errado".
-- O tipo vinha de um "casa" de até 60 dias atrás, e "não é a casa não, é o Smart
-- Tower" era lido como pedido de casa.
--
--   nai_menciona_foto         falou em foto, imagem, vídeo, "ver a fachada"; não
--                             conta: "já tenho as fotos", foto de RG/CNH, ele
--                             mandando foto, descrição de imagem que o sistema fez.
--   nai_pede_envio_do_imovel  "me manda/envia/passa/encaminha" + imóvel claro
--                             (código, card colado, "esse imóvel", nome do
--                             condomínio); "manda as de locação", "me passa a
--                             lista", "me manda a documentação" não contam.
--   nai_deve_mandar_fotos     uma das duas acima, ou "sim" à pergunta dela sobre
--                             as fotos. Fora isso: só o card (com tudo).
--   portão (conferência 15)   foto só do imóvel que bate com locação/venda e
--                             casa/apto da conversa, a não ser o que ele citou.
--   sem promessa              sem foto, a frase "segue as fotos" sai do texto.
--   código solto, dois        o caminho do número solto ("5724") e a fila dos
--   imóveis                   outros imóveis seguem a mesma regra.
--   sobras                    "Aqui as fotos" sem foto vira "Quer fazer uma
--                             visita?"; "📌 Status" sem o card não sai; se a
--                             conferência barrou tudo, o Tel é avisado.
--   tipo da conversa          3 dias (a janela do negócio, 190), sem as mensagens
--                             de 60 dias; negação ("não é casa"), "cheguei em
--                             casa", "Amazonas Flat" e descrição de foto não contam.
--   textos                    o prompt do corretor e as instruções das
--                             ferramentas deixam de dizer que a foto sai sozinha.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION pg_temp.trocar(p_fn regprocedure, p_de text, p_para text, p_vezes int DEFAULT 1)
 RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  d text := pg_get_functiondef(p_fn);
  n int := (length(d) - length(replace(d, p_de, ''))) / length(p_de);
BEGIN
  IF n <> p_vezes THEN
    RAISE EXCEPTION 'trocar em %: esperava % vez(es), achei % -- %', p_fn, p_vezes, n, left(p_de, 60);
  END IF;
  EXECUTE replace(d, p_de, p_para);
END $$;

-- 1 -------------------------------------------------- ELE FALOU EM FOTO
CREATE OR REPLACE FUNCTION public.nai_menciona_foto(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- 224: "menção a fotos" (Pedro, 30/09). Medido em 15 dias de conversa: o que
  -- NÃO é pedido são as descrições de imagem que o sistema escreve ("a imagem
  -- mostra..."), "já achei as fotos", "mandei para o cliente as fotos", "foto do
  -- RG", "tenho fotos", "não vou autorizar foto" e "fachada moderna" (perfil).
  SELECT (x ~ '\m(fotos?|imagens?|videos?|fotografias?)\M'
          OR x ~ '\m(ver|veja|vendo|mostra\w*|foto|fotos|imagem|video|tem|manda\w*|envia\w*|passa\w*)\s+(a |da |de )?fachada\M')
     AND x !~ '^\s*(o|a|os|as|este|esse|esta|essa)\s+(arquivo|imagem|documento|print|foto|video|audio|pdf)s?\s+(mostra|apresenta|e|eh|contem|traz|exibe|parece|tem|possui)\M'
     AND x !~ '(ja (recebi|vi|tenho|peguei|achei)|nao precis|dispensa|voce ja (me )?(mandou|enviou))[^.,;!?]{0,30}\m(fotos?|imagens?|videos?|fachada)\M'
     AND x !~ '\m(fotos?|imagens?|videos?|fachada)\M[^.,;!?]{0,30}(ja (recebi|vi|tenho|peguei|achei)|nao precis)'
     AND x !~ '\m(fotos?|imagens?|prints?)\s+(do|da|de|dos|das)\s+(rg|cnh|cpf|documentos?|comprovantes?|contracheques?|holerites?|identidade|cliente|pix|recibos?|contratos?|boletos?|carteira|certid\w*|creci)\M'
     AND x !~ '\m(segue|seguem|mandei|enviei|passei|encaminhei|vou (te |lhe )?(mandar|enviar|passar)|to mandando|estou mandando|te mando|te envio)\M[^.,;?!]{0,25}\m(fotos?|imagens?|videos?)\M'
     AND x !~ '\m(tenho|possuo|tirar|tirei|tirando|bater|bati|autorizar|autorizo)\s+(mais |umas |as |os |algumas |a |uma )?(fotos?|imagens?|videos?)\M'
     AND x !~ '\m(essas|estas|nessas|nestas)\s+(aqui\s+)?(sao\s+)?(as\s+)?(fotos|imagens)\M'
  FROM (SELECT lower(unaccent(regexp_replace(coalesce(p_texto, ''), '(https?://|www\.)\S+', ' ', 'gi'))) AS x) t;
$function$;

-- 2 ------------------------------------- "ME MANDA / ME ENVIA" UM IMÓVEL CLARO
CREATE OR REPLACE FUNCTION public.nai_pede_envio_do_imovel(p_texto text, p_telefone text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE x text := lower(unaccent(coalesce(p_texto, '')));
BEGIN
  -- 224: "o corretor pedir em um imóvel claro: envia, me manda" (Pedro, 30/09).
  -- O verbo é o PEDIDO (imperativo, ou "pode me mandar"): "vou encaminhar" é ele
  -- mandando ao cliente, não pedido.
  IF x !~ ('\m(manda|mande|envia|envie|encaminha|encaminhe|passa|passe|compartilha)\M'
           || '|\m(pode|poderia|podes|consegue|conseguiria|tem como|da pra|da para)\s+(me\s+)?(mandar|enviar|encaminhar|passar)\M') THEN
    RETURN false;
  END IF;
  -- O que ele pede mandar não é o imóvel: a lista, as de locação, o endereço...
  IF x ~ ('\m(manda|mande|envia|envie|encaminha|encaminhe|passa|passe|mandar|enviar|encaminhar|passar)\s+(me\s+)?(ai\s+|aqui\s+|por aqui\s+|pra mim\s+)?'
          || '(a |o |as |os |umas? |uns |mais |outras? |outros? )?(sua |tua |seus |suas |teus |tuas )?'
          || '(opc\w*|lista\w*|outr\w*|mais\M|localiza\w*|endereco|pin\M|link|horario|document\w*|checklist|contrato|ficha|valor\w*|preco\w*|numero'
          || '|contato|telefone|audio|disponib\w*|de loca\w*|de venda|algo|alguma?s?\M|tudo|relacao|tabela|planilha|proposta|dados|nome|essas? informac\w*|estas? informac\w*)') THEN
    RETURN false;
  END IF;
  -- ...e o imóvel é claro: código, card colado, "esse imóvel", nome do condomínio.
  RETURN coalesce(array_length(nay_codigos_citados(coalesce(p_texto, '')), 1), 0) > 0
      OR position('📍' IN coalesce(p_texto, '')) > 0
      OR x ~ '\mcodigo\M'
      OR x ~ '\m(esse|essa|este|esta|desse|dessa|deste|desta|aquele|aquela|daquele|daquela|o|a)\s+(teu |seu |mesmo |mesma )?(imovel|apartamento|apto|ap|casa|unidade|anuncio|card|material)\M'
      OR coalesce(array_length(nai_imovel_pelo_condominio(p_texto, coalesce(p_telefone, '')), 1), 0) > 0;
END;
$function$;

-- 3 ------------------------------------------------------ O PORTÃO DAS FOTOS
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

-- 4 ------------------------------------------ CASA OU APARTAMENTO, DE VERDADE
CREATE OR REPLACE FUNCTION public.nai_tipo_pedido(p_texto text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE COST 800
AS $function$
  -- AS RESIDENCIAIS bastam a palavra. AS COMERCIAIS exigem a marca
  -- ("sala comercial") ou o verbo do pedido ("alugar uma sala") -- medido:
  -- sem isso, 123 de 127 leituras eram falsas (120d). E "ponto de
  -- referencia/onibus/taxi" nunca e imovel (120e).
  -- 224: a palavra so conta quando e o pedido. Fora: a negacao ("nao e a casa
  -- nao, e o Smart Tower" era lido como casa -- Marcio, 30/09), a casa de quem
  -- escreve ("cheguei em casa", "saindo de casa"), nome de condominio
  -- ("Amazonas Flat" tem 22 apartamentos), link, e a descricao de foto que o
  -- sistema escreve ("a imagem mostra ... muitas casas").
  SELECT CASE
    WHEN s0 ~ '^\s*(o|a|os|as|este|esse|esta|essa)\s+(arquivo|imagem|documento|print|foto|video|audio|pdf)s?\s+(mostra|apresenta|e|eh|contem|traz|exibe|parece|tem|possui)\M'
                                                            THEN NULL
    WHEN s ~ '\m(casa|casas|sobrado)\M'                     THEN 'Casa%'
    WHEN s ~ '\m(apartamento|apartamentos|apto|aptos|ap)\M' THEN 'Apartamento%'
    WHEN s ~ '\m(cobertura|coberturas)\M'                   THEN 'Cobertura%'
    WHEN s ~ '\m(flat|flats)\M'                             THEN 'Flat%'
    WHEN s ~ '\m(salas?|conjuntos?)\s+(comercial|comerciais)\M'
      OR   s ~ (v || 'salas?\M')                            THEN 'Sala%'
    WHEN s ~ '\m(lojas?|pontos?)\s+(comercial|comerciais)\M'
      OR   (s ~ (v || '(lojas?|pontos?)\M')
            AND NOT s ~ '\mpontos?\s+de\s+(referencia|onibus|taxi|encontro)\M')
                                                            THEN 'Loja%'
    WHEN s ~ '\m(galpao|galpoes)\M'
      OR   s ~ (v || 'depositos?\M')                        THEN 'Galp%'
    WHEN s ~ '\m(terreno|terrenos|lote|lotes)\M'            THEN 'Lote%'
    WHEN s ~ '\m(chacara|chacaras|sitio)\M'                 THEN 'Ch%'
    WHEN s ~ (v || 'predios?\M')                            THEN 'Pr%dio%'
  END
  FROM (SELECT s0,
               regexp_replace(regexp_replace(regexp_replace(regexp_replace(s0,
                 '(https?://|www\.)\S+', ' ', 'g'),
                 '\mnao\s+(e|eh|era|seria|quero|queria|precisa ser|pode ser|serve|busco|procuro|preciso de)\s+(uma?\s+|a\s+|o\s+|de\s+)?(casas?|sobrados?|apartamentos?|aptos?|ap|flats?|coberturas?)\M', ' ', 'g'),
                 '\m(cheguei|chegar|chego|chegando|chegou|sai|sair|saindo|saio|saiu|voltei|voltar|voltando|volto|indo|vou|to|estou|esta|estava|estarei|fico|fiquei|ficar|ficando|trabalho|trabalhando|trabalhar|la)\s+(de|em|na|pra|para)\s+(a\s+)?casa\M', ' ', 'g'),
                 '\m(amazonas?\s+flat|flat\s+edificio|condominio\s+flat|casa\s+center)\M', ' ', 'g') AS s,
               '\m(alug\w*|loc\w*|procur\w*|quer\w*|busc\w*|precis\w*|tem|teria|tenho cliente p\w*|interesse em)\s+(\w+\s+){0,2}' AS v
          FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS s0) a) x;
$function$;

CREATE OR REPLACE FUNCTION public.nai_tipo_da_conversa(p_contato bigint, p_texto text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- 224: O TIPO E O DO PEDIDO DE AGORA. A fala dele e os turnos dos ultimos 3
  -- dias (a mesma janela do negocio, 190), dele e dos irmaos, depois do
  -- "zerar". Antes eram 30 dias de turnos e 60 de mensagens: um "casa" antigo
  -- do Marcio fez a Nay responder "Casa nesse perfil eu nao tenho" a quem pedia
  -- apartamento no Smart Tower Itapuranga, e barrar os apartamentos certos.
  -- Sem tipo nos 3 dias, a busca pergunta "casa ou apartamento?" (152).
  SELECT nai_tipo_das_falas(array[coalesce(p_texto, '')] || coalesce((
    SELECT array_agg(x.texto ORDER BY x.id DESC) FROM (
      SELECT t.id, t.texto FROM nai_turno t
       WHERE t.contato_id = ANY (nai_contato_irmaos(p_contato))
         AND t.criado_em > greatest(now() - interval '3 days',
                                    coalesce((SELECT k.zerado_em FROM nai_contato k WHERE k.id = p_contato), '-infinity'))
       ORDER BY t.id DESC LIMIT 40) x), '{}'::text[]));
$function$;

-- 5 ------------------------------------------------------- AS SOBRAS DA CAIXA
CREATE OR REPLACE FUNCTION public.nai_saida_sem_sobras(p_turno bigint)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_foto boolean; v_card boolean; v_resp boolean;
  n int := 0; m int;
BEGIN
  -- 224: a conferencia (116, 190) barra o card ou a foto que nao batem com o
  -- pedido, mas a frase que ia junto saia sozinha: em 30/09 o Marcio recebeu
  -- "📌 Status: Disponivel" e "Aqui as fotos, quer fazer uma visita?" sem card
  -- e sem foto nenhuma atras.
  SELECT EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = p_turno AND estado = 'pendente' AND tipo = 'imagem'),
         EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = p_turno AND estado = 'pendente' AND tipo = 'texto'
                  AND texto ~* 'C[óo]digo:\s*\d{3,5}'),
         EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = p_turno AND estado = 'pendente' AND tipo = 'texto'
                  AND motivo = 'resposta')
    INTO v_foto, v_card, v_resp;

  IF NOT v_card THEN
    UPDATE nai_saida SET estado = 'bloqueado', bloqueio = 'sobra: o card do status foi barrado'
     WHERE turno_id = p_turno AND estado = 'pendente' AND motivo = 'status';
    GET DIAGNOSTICS m = ROW_COUNT; n := n + m;
  END IF;

  IF NOT v_foto THEN
    IF v_card OR v_resp THEN
      UPDATE nai_saida SET texto = 'Quer fazer uma visita? Só me informar um horário'
       WHERE turno_id = p_turno AND estado = 'pendente' AND motivo = 'depois_das_fotos'
         AND texto LIKE 'Aqui as fotos,%';
    ELSE
      UPDATE nai_saida SET estado = 'bloqueado', bloqueio = 'sobra: as fotos e o card foram barrados'
       WHERE turno_id = p_turno AND estado = 'pendente' AND motivo = 'depois_das_fotos';
    END IF;
    GET DIAGNOSTICS m = ROW_COUNT; n := n + m;
  END IF;

  -- Barrou tudo o que era imovel e nao sobrou nada para ele: o Tel fica sabendo.
  IF n > 0
     AND NOT EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = p_turno AND estado = 'pendente'
                        AND papel_destino <> 'tel')
     AND NOT EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = p_turno AND motivo = 'saida_sem_imovel') THEN
    PERFORM nai_avisar_tel(p_turno, NULL,
      'Tel, a conferência barrou os imóveis desta resposta (não batiam com o que o corretor pediu), '
      || 'então não mandei nada. Dá uma olhada nesse chat.', 'saida_sem_imovel');
  END IF;

  IF n > 0 THEN
    PERFORM nai_anotar(p_turno, 23, 'sobras_da_caixa', 'mudou', n || ' linha(s) sem o card ou a foto atrás');
  END IF;
  RETURN n;
END;
$function$;

SELECT pg_temp.trocar('nai_enfileirar_resposta(bigint,text,jsonb,text,jsonb)',
$a$  PERFORM nai_conferir_texto_da_saida(p_turno);
$a$,
$b$  PERFORM nai_conferir_texto_da_saida(p_turno);
  -- 224: o status e o "Aqui as fotos" nao saem sem o card e a foto atras
  PERFORM nai_saida_sem_sobras(p_turno);
$b$);

-- 224: o anuncio de foto ("segue as fotos") sem foto nenhuma atras do card nao sai
SELECT pg_temp.trocar('nai_enfileirar_resposta(bigint,text,jsonb,text,jsonb)',
$a$    ELSIF v_resto <> '' THEN$a$,
$b$    ELSIF v_resto <> '' AND NOT (v_fotos = 0 AND nai_so_anuncia_fotos(v_resto)) THEN$b$);

-- 6 ------------------------------------------------- A CONFERÊNCIA DAS FOTOS
SELECT pg_temp.trocar('nai_conferir_resposta(bigint,text,jsonb,text,jsonb)',
$a$    -- AS FOTOS VAO SEMPRE (Tel, 16/09): falou de imovel, recebe informacao e
    -- foto na mesma resposta. Antes era preciso pedir "foto" com todas as
    -- letras, e quem escrevia "me encaminha o 5717" recebia so o card.$a$,
$b$    -- 224: FOTO SO QUANDO ELE PEDE (Pedro, 30/09): falou em foto, ou pediu um
    -- imovel claro com "me manda/envia/encaminha". Sem pedido vai o card, que
    -- tem todas as informacoes. (De 16/09 a 30/09 a foto ia sempre.)$b$);

SELECT pg_temp.trocar('nai_conferir_resposta(bigint,text,jsonb,text,jsonb)',
$a$  IF v_gate AND coalesce(array_length(v_cods, 1), 0) = 0 THEN
    v_gate := false;
  END IF;

  -- IMOVEL INDISPONIVEL NAO LEVA FOTO (138)$a$,
$b$  IF v_gate AND coalesce(array_length(v_cods, 1), 0) = 0 THEN
    v_gate := false;
  END IF;

  -- 224: FOTO SO DO IMOVEL CERTO. Pedido de foto na mao, sai foto so do imovel
  -- que bate com o negocio (locacao/venda) e o tipo (casa/apartamento) da
  -- conversa -- a nao ser o que ele mesmo citou (codigo digitado em 3 dias,
  -- nome do condominio agora). Em 29/09, numa conversa de venda, sairam 24
  -- fotos de um de locacao.
  IF v_gate THEN
    DECLARE
      v_neg224 text := nai_negocio_da_conversa(t.contato_id, coalesce(p_escreveu, ''));
      v_tp224  text := nai_tipo_da_conversa(t.contato_id, coalesce(p_escreveu, ''));
      v_citou  int[] := nai_codigos_que_ele_digitou(t.contato_id)
                        || coalesce(nai_imovel_pelo_condominio(coalesce(p_escreveu, ''), coalesce(k.telefone, '')), '{}'::int[]);
      v_fora   int[];
    BEGIN
      SELECT coalesce(array_agg(c), '{}') INTO v_fora FROM unnest(v_cods) c
       WHERE NOT (c = ANY (v_citou))
         AND (NOT nai_finalidade_serve(c, v_neg224)
              OR (v_tp224 IS NOT NULL
                  AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = c
                                 AND i.tipo IS NOT NULL AND i.tipo NOT ILIKE v_tp224)));
      IF coalesce(array_length(v_fora, 1), 0) > 0 THEN
        v_cods := ARRAY(SELECT c FROM unnest(v_cods) c WHERE NOT (c = ANY (v_fora)));
        PERFORM nai_anotar(p_turno, 15, 'foto_fora_do_pedido', 'mudou',
          'sem foto de ' || array_to_string(v_fora, ', ') || ' (conversa: '
          || coalesce(v_neg224, '?') || ', ' || coalesce(nai_rotulo_do_tipo(v_tp224), '?') || ')');
        IF coalesce(array_length(v_cods, 1), 0) = 0 THEN
          v_gate := false;
        END IF;
      END IF;
    END;
  END IF;

  -- IMOVEL INDISPONIVEL NAO LEVA FOTO (138)$b$);

SELECT pg_temp.trocar('nai_conferir_resposta(bigint,text,jsonb,text,jsonb)',
$a$  -- 16 ------------------------------- NEGOU FOTO QUE EXISTE / PROMETEU A QUE NÃO
$a$,
$b$  -- 224: SEM FOTO, SEM PROMESSA DE FOTO. A frase do modelo que anuncia foto
  -- ("segue as fotos", "já te mando as fotos") sai quando nenhuma foto vai.
  -- Se a frase era tudo o que ela ia dizer ("Claro! Segue as fotos."), fica: e
  -- dali que sai o "de qual imovel voce quer as fotos?" quando ele pediu foto.
  IF NOT v_gate AND v_texto ~* nai_re_promete_foto() THEN
    v_novo := nai_tirar_frase(v_texto, nai_re_promete_foto());
    IF length(regexp_replace(v_novo, '\W', '', 'g')) >= 12 THEN
      v_texto := v_novo;
      v_guarda := coalesce(v_guarda || '+', '') || 'promessa_de_foto';
      PERFORM nai_anotar(p_turno, 16, 'promessa_sem_foto', 'mudou', 'nenhuma foto vai: a frase das fotos saiu');
    END IF;
  END IF;

  -- 16 ------------------------------- NEGOU FOTO QUE EXISTE / PROMETEU A QUE NÃO
$b$);

SELECT pg_temp.trocar('nai_conferir_resposta(bigint,text,jsonb,text,jsonb)',
$a$                          ELSE 'ele não pediu foto' END);$a$,
$b$                          ELSE 'sem foto: ele não pediu, ou o imóvel não bate com o pedido' END);$b$);

-- 7 ------------------------------------- O CÓDIGO SOLTO E A FILA DE DOIS IMÓVEIS
SELECT pg_temp.trocar('nai_enfileirar_card(bigint,integer)',
$a$  IF NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = p_codigo AND coalesce(e_parceiro, false)) THEN$a$,
$b$  -- 224: o codigo solto ("5724") leva o card; a foto so se ele pediu
  IF NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = p_codigo AND coalesce(e_parceiro, false))
     AND coalesce(nai_deve_mandar_fotos(t.contato_id,
                    (SELECT k.telefone FROM nai_contato k WHERE k.id = t.contato_id), t.texto), false) THEN$b$);

SELECT pg_temp.trocar('nai_fila_dos_outros_imoveis(bigint,text)',
$a$    FOR f IN SELECT * FROM nai_imagens_do_envio(c) LOOP$a$,
$b$    -- 224: a foto do segundo imovel so vai se ele pediu foto
    FOR f IN SELECT * FROM nai_imagens_do_envio(c)
              WHERE (SELECT coalesce(nai_deve_mandar_fotos(t.contato_id, k.telefone, v_txt), false)) LOOP$b$);

-- 8 --------------------------------------- AS INSTRUÇÕES QUE PROMETIAM FOTO
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$      ('e um imovel so nesse perfil: mande o card EXATAMENTE como veio. O sistema manda as '
       || 'fotos e a sugestao de visita logo depois.')::text;$a$,
$b$      ('e um imovel so nesse perfil: mande o card EXATAMENTE como veio. O sistema manda a '
       || 'sugestao de visita logo depois; foto so sai se ele pedir.')::text;$b$);

SELECT pg_temp.trocar('nai_status_do_imovel(integer)',
$a$'As fotos e a pergunta saem sozinhas atrás. Não escale.'$a$,
$b$'A pergunta sai sozinha atrás; foto só sai se ele pedir. Não escale.'$b$);

SELECT pg_temp.trocar('nay_disponibilidade_no_condominio(text,text)',
$a$'manda as fotos e a sugestao de visita logo depois. NAO escale.'$a$,
$b$'manda a sugestao de visita logo depois; foto so sai se ele pedir. NAO escale.'$b$);

-- 9 ----------------------------------------------- O PROMPT DO CORRETOR
DO $$
DECLARE v_texto text; v_novo text; v_versao int;
  r text[];
  trocas text[][] := ARRAY[
    ARRAY['manda as fotos atrás do card, a pergunta atrás da lista',
          'manda as fotos quando ele pede, a pergunta atrás da lista'],
    ARRAY['Disponível vem com o status e o card (as fotos saem atrás);',
          'Disponível vem com o status e o card;'],
    ARRAY['- Chame imovel_por_codigo e mande o card inteiro, como veio. As fotos e a pergunta saem atrás, sozinhas.',
          '- Chame imovel_por_codigo e mande o card inteiro, como veio: ele leva todas as informações do imóvel.'
          || E'\n' || '- As fotos saem sozinhas atrás do card quando ele pede: falou em foto, vídeo ou fachada, ou pediu o imóvel com "me manda", "me envia", "me passa". Sem esse pedido vai só o card, e você não fala de foto.'],
    ARRAY['- O card veio com qtd_fotos = 0: "Já te mando as fotos!"',
          '- Ele pediu as fotos e o card veio com qtd_fotos = 0: "Já te mando as fotos!"'],
    ARRAY['Ela pergunta locação ou venda quando não está claro, e lista assim que houver um filtro.',
          'Ela pergunta locação ou venda e casa ou apartamento quando não está claro, e lista assim que houver um filtro.']];
BEGIN
  SELECT texto, versao INTO v_texto, v_versao FROM nai_prompt WHERE papel = 'corretor' FOR UPDATE;
  v_novo := v_texto;
  FOR i IN 1 .. array_length(trocas, 1) LOOP
    IF position(trocas[i][1] IN v_novo) = 0 THEN
      RAISE EXCEPTION 'prompt do corretor: não achei "%"', left(trocas[i][1], 70);
    END IF;
    v_novo := replace(v_novo, trocas[i][1], trocas[i][2]);
  END LOOP;
  PERFORM nai_salvar_prompt('corretor', v_novo, v_versao,
    'Claude 30/09 (224): foto só quando ele pede; identificação casa/apto');
  RAISE NOTICE 'prompt do corretor: versão % -> %', v_versao, v_versao + 1;
END $$;

-- 10 ---------------------------------------------------------- A BATERIA
SELECT pg_temp.trocar('nai_rodar_casos()',
$a$      WHEN 'lugar'      THEN coalesce(nai_bairros_do_lugar(c.frase)::text, '-')  -- 206$a$,
$b$      WHEN 'lugar'      THEN coalesce(nai_bairros_do_lugar(c.frase)::text, '-')  -- 206
      WHEN 'foto'       THEN coalesce(nai_deve_mandar_fotos(NULL, '', c.frase), false)::text  -- 224$b$);

INSERT INTO nai_caso (quem, frase, pergunta, esperado, regra) VALUES
  ('Pedro 30/09', 'Oi, Nai, não é a casa não, é o Smart Tower Itapuranga.', 'tipo', '-', 'negação não é pedido de casa'),
  ('Pedro 30/09', 'não é apartamento, é casa', 'tipo', 'Casa%', 'negação de um tipo, pedido do outro'),
  ('Pedro 30/09', 'nao consegui nem olhar nao cheguei em casa ainda', 'tipo', '-', 'a casa de quem escreve não é pedido'),
  ('Pedro 30/09', 'pode ser 13 pois 13:30 estarei saindo de casa', 'tipo', '-', 'a casa de quem escreve não é pedido'),
  ('Pedro 30/09', 'bom dia o amazonas flat esta disponivel', 'tipo', '-', 'Amazonas Flat é nome de condomínio (de apartamentos)'),
  ('Pedro 30/09', 'nay vc tem flat mobiliado?', 'tipo', 'Flat%', 'flat pedido continua flat'),
  ('Pedro 30/09', 'A imagem mostra uma vista aérea de Manaus, com muitas casas próximas', 'tipo', '-', 'descrição de foto não é pedido'),
  ('Pedro 30/09', 'Preciso de casa para locação perto da zona leste', 'tipo', 'Casa%', 'pedido de casa continua casa'),
  ('Pedro 30/09', 'me manda as fotos do 5724', 'foto', 'true', 'pediu foto: vai foto'),
  ('Pedro 30/09', 'Fotos?', 'foto', 'true', 'menção a foto: vai foto'),
  ('Pedro 30/09', 'tem foto da fachada dessa casa?', 'foto', 'true', 'fachada é foto'),
  ('Pedro 30/09', 'me manda o card do 5733', 'foto', 'true', 'me manda + imóvel claro: vai foto'),
  ('Pedro 30/09', 'nay me envia esse teu imovel atende um cliente aqui', 'foto', 'true', 'me envia + esse imóvel: vai foto'),
  ('Pedro 30/09', '5724', 'foto', 'false', 'código solto: só o card'),
  ('Pedro 30/09', 'o 5724 ainda está disponível?', 'foto', 'false', 'pergunta de situação: só o card'),
  ('Pedro 30/09', 'manda as de locação', 'foto', 'false', 'pediu lista, não imóvel'),
  ('Pedro 30/09', 'me manda a documentação necessária para fazer analise do cliente', 'foto', 'false', 'documentação não é imóvel'),
  ('Pedro 30/09', 'preciso de uma casa duplex, fachada moderna e com piscina', 'foto', 'false', 'fachada moderna é perfil'),
  ('Pedro 30/09', 'mandei para o cliente as fotos', 'foto', 'false', 'ele mandando foto não é pedido'),
  ('Pedro 30/09', 'já achei aqui as fotos, aguardando cliente responder', 'foto', 'false', 'já tem as fotos'),
  ('Pedro 30/09', 'segue foto do RG do cliente', 'foto', 'false', 'foto de documento não é do imóvel'),
  ('Pedro 30/09', 'A imagem mostra uma cozinha com armários planejados', 'foto', 'false', 'descrição de foto não é pedido');
COMMIT;
