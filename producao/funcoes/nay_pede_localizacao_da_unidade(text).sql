CREATE OR REPLACE FUNCTION public.nay_pede_localizacao_da_unidade(p_texto text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  t     text := lower(unaccent(coalesce(p_texto,'')));
  nivel text := coalesce((SELECT valor FROM config WHERE chave = 'unidade_nivel'),
                         'apartamento');
  -- "apartamento" e o substantivo mais comum da conversa inteira: aparece
  -- em busca ("tem apartamento no Tarumã"), em visita ("confirma a visita
  -- no apartamento"), em conversa ("tá lá no apt ainda?"). A janela entre
  -- a pergunta e o substantivo TEM que ser curta -- com 25 caracteres a
  -- regra pegava "me informe se esse Apartamento ta quitado", que e
  -- pergunta de pagamento. So cabe artigo e verbo de ligacao.
  -- Ate duas palavrinhas, nao uma: "Qual E O apartamento?" atravessava a
  -- janela de uma so. Achado no red team de 01/09.
  colagem constant text := '\s*(e|eh|é|o|a|os|as|do|da|de|no|na|seu|sua|esse|essa|este|esta|qual)?'
                        || '\s*(o|a|os|as|do|da|de|esse|essa|este|esta)?\s*';
  unidade  constant text := '(apartamento|apartamentos|apto|aptos|apt|ap|ape|apes|'
                            || 'cobertura|kitnet|kit|unidade|unidades|complemento|porta|'
                            -- 94 imóveis são "Lote em Condomínio": ali o número
                            -- do lote é o identificador, igual ao do apartamento.
                            || 'lote|lotes|quadra|sala)';
  -- CASA entra so na pergunta pelo NUMERO. "qual casa" e busca -- das 45
  -- mensagens reais que citam casa, quase todas sao "procuro casa na
  -- cidade nova", "casa do nova cidade disponivel?". Bloquear "qual casa"
  -- calaria a Nay na conversa mais comum que ela tem.
  numerada constant text := '(apartamento|apartamentos|apto|aptos|apt|ap|ape|apes|'
                            || 'cobertura|unidade|unidades|complemento|porta|casa|casas|'
                            || 'sobrado|lote|lotes|quadra|sala|conjunto)';
  loc      constant text := '(apartamento|apto|apt|unidade|bloco|torre|andar|complemento)';
BEGIN
  IF t = '' THEN RETURN false; END IF;

  -- NAO EXISTE FILTRO NEGATIVO AQUI, e a ausencia e deliberada.
  --
  -- Havia um: se a mensagem citasse foto, video, material ou ficha, a
  -- funcao devolvia false ANTES de olhar qualquer regra positiva. O red
  -- team de 01/09 furou em um minuto:
  --     BLOQUEIA  "qual o apartamento"
  --     PASSA     "qual o apartamento e me manda as fotos"
  -- E pedir foto e o gesto mais comum da conversa -- 57 mensagens --
  -- porque o proprio gatilho de fotos EXIGE que o corretor peca. Pior: o
  -- no `Gravar na fila` chama esta mesma funcao, entao a segunda camada
  -- (o aviso no turno do agente) caia junto.
  --
  -- MEDIDO antes de remover: as 15 mensagens legitimas que o filtro
  -- existia para proteger continuam passando sem ele -- quem separa e a
  -- janela curta `colagem` com a lista estreita `unidade`, como o proprio
  -- comentario ja dizia. Nas 2.960 reais: 6 bloqueadas com ele, 6 sem.
  --
  -- A LICAO, que ja estava escrita neste arquivo e eu apliquei pela
  -- metade de manha: filtro negativo em regra de seguranca e senha que
  -- qualquer um adivinha. Nao basta encurtar a lista -- ela nao pode
  -- existir.

  -- PERGUNTA direta pelo identificador da unidade. Janela curta.
  IF t ~ ('\mqual' || colagem || unidade || '\M')
     OR t ~ ('\m(numero|nro|n[°º]|n\.)' || colagem || '(do|da)?\s*' || numerada || '\M')
     -- "qual o numero da casa", "qual o numero" -- decisao do Tel em
     -- 01/09: o numero da casa e o identificador dela, igual ao numero do
     -- apartamento.
     OR t ~ ('\mqual' || colagem || '(o\s+)?numero' || colagem || '(do|da)?\s*' || numerada || '\M')
     OR t ~ ('\m' || unidade || '\s*(e|eh|é)?\s*(qual|numero|nro)\M')
     OR t ~ '\mendereco\s*(completo|exato|certo|detalhado|certinho)\M'
     OR t ~ '\m(completo|exato)\s*(o\s*)?endereco\M'
     OR t ~ ('\m(me\s+)?(passa|passe|manda|mande|informa|informe|envia|envie|diz|fala)\s*'
          || '(me\s+)?(o|a)?\s*(numero|complemento|localizador|endereco completo)\M')
     OR t ~ ('\m(me\s+)?(passa|passe|manda|mande)\s*(me\s+)?qual' || colagem || unidade || '\M')
     OR t ~ '\monde\s*(fica|e|é)?\s*(exatamente|certinho)\M'
     -- "qual o numero?" sozinho. Num contexto de imovel nao ha outro
     -- numero que ele possa querer -- valor ele pede por "valor" ou
     -- "quanto".
     OR t ~ ('\mqual' || colagem || '(numero|nro|n[°º])\M')
  THEN
    RETURN true;
  END IF;

  -- DOIS localizadores numa pergunta: "torre e apto", "bloco e
  -- apartamento", "qual andar, bloco e apartamento". O conjunto e a porta,
  -- mesmo que cada parte sozinha fosse aceitavel.
  -- Dois localizadores juntos NAO precisam de "qual": "Torre e apto?" e
  -- mensagem real deste banco e passava, porque o bloco exigia o
  -- interrogativo. A pergunta esta na propria justaposicao.
  IF (
       -- SÓ conjunção, nunca possessivo. "torre E apto" pergunta duas
       -- coisas e a segunda é o número; "torre DO apto" pergunta uma só, a
       -- torre, que o Tel liberou. Com "do" na lista, "E qual o andar do
       -- apto? Nascente ou poente?" -- mensagem real, pergunta de
       -- orientação solar -- passava a ser recusada.
       t ~ ('\m(bloco|torre|tr|bl|andar)\s*(,|e|eh|é)?\s*(o|a)?\s*' || unidade || '\M')
    OR t ~ ('\m' || unidade || '\s*(,|e|eh|é)?\s*(o|a)?\s*(bloco|torre|andar)\M')
    OR t ~ '\m(bloco|torre)\s*(,|e|eh|é)?\s*(o|a)?\s*andar\M'
    OR t ~ '\mandar\s*(,|e|eh|é)?\s*(o|a)?\s*(bloco|torre)\M')
  THEN
    RETURN true;
  END IF;

  -- Só quando o Tel apertar: andar e torre sozinhos passam a ser recusa.
  IF nivel = 'tudo' AND t ~ ('\mqual' || colagem || '(andar|bloco|torre)\M') THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$function$;
