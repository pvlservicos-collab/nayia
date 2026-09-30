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
