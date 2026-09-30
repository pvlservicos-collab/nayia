CREATE OR REPLACE FUNCTION public.nai_oferece_imovel(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE COST 300
AS $function$
  WITH t AS (SELECT lower(unaccent(coalesce(p_texto, ''))) AS s)
  SELECT
    -- ------------------------------------------------------------------
    -- 1. ele se oferece para mandar ("se quiser te envio", "posso passar")
    ( (   s ~ '(se|caso) (voce |vc |tu |o sr |a sra )?quiser(es)?[ ,]*(eu )?(te |lhe )?(envio|mando|passo|encaminho|mostro|enviar|mandar|passar)'
       OR s ~ 'quer(es)? que eu ?(te |lhe )?(envie|mande|passe|cadastre|encaminhe|mostre)'
       OR s ~ 'posso ?(te |lhe )?(enviar|mandar|passar|encaminhar)'
       OR s ~ '(quero|gostaria de|preciso|como (faco|faz) (para|pra)) (cadastrar|colocar) ?(meu|um|uns|o)? ?(imovel|imoveis|apartamento|apto|casa)'
       OR s ~ '(voces|vcs) (pegam|aceitam|fazem|trabalham com|querem) (captacao|imove|apartamento|administracao)')
      AND s !~ '(cpf|\mrg\M|documento|contrato|comprovante|ficha|\mprint|\maudio\M|localizacao|\mo numero\M|deposito|\mchave)' )
    OR
    -- ------------------------------------------------------------------
    -- 2. ele diz que TEM um, COM artigo ("eu tenho um Living Confort tambem")
    ( s ~ '\m(eu )?(tenho|possuo)\M (um|uma|uns|umas|dois|duas|outro|outra|mais um|mais uma)\M'
      AND s !~ '\m(cliente|comprador|inquilin|interessad|visita|proposta|duvida|pergunta|horario|reuniao|compromisso|minuto|problema|detalhe|amigo|corretor|garagem|vaga)' )
    OR
    -- ------------------------------------------------------------------
    -- 3. NOVO -- ele diz que TEM, SEM artigo, e emenda atributo de imovel.
    --    "Tenho vista do sol mobiliado por 10 mil"
    --    "Tenho vivenda verde p locacao tbm. 110m2, mobiliado."
    --    E o jeito real de escrever. O atributo logo depois e o que separa
    --    isto de "tenho reuniao as 3" -- so vira oferta se o que vem na
    --    sequencia for coisa de imovel.
    ( s ~ '\m(eu )?(tenho|possuo)\M[^.!?;]{0,70}\m(mobiliad|semimobiliad|semi ?mobiliad|quartos?|suites?|m2|metros|locacao|alugar|aluguel|venda|vender|condominio|kitnet|flat|cobertura)\M'
      -- SEM `\M` no fim desta lista, de proposito: com ele, `\mcliente\M`
      -- nao casa com "clientes" -- e "tenho dois CLIENTES: um quer 2
      -- quartos no Aleixo" virava oferta. Foi o unico falso positivo do
      -- teste contra 4 dias de mensagens reais. O ramo 2 ja era assim.
      AND s !~ '\m(cliente|comprador|inquilin|interessad|visita|proposta|duvida|pergunta|horario|reuniao|compromisso|minuto|problema|detalhe|amigo|corretor|garagem|vaga)'
      -- a mesma demanda escrita sem a palavra "cliente"
      AND s !~ '\m(procur|pedido de|demanda|busca por)' )
    OR
    -- ------------------------------------------------------------------
    -- 4. NOVO -- ele pergunta COMO ANUNCIAR com a gente.
    --    "Como funciona pra voce anunciar?" / "quero anunciar com voces"
    --
    --    A EXCECAO E OBRIGATORIA: "posso anunciar os imoveis de VOCES?" e
    --    o contrario disto -- e corretor pedindo para divulgar o NOSSO
    --    catalogo, e o prompt manda responder que pode. Sem a excecao,
    --    esse corretor cairia na secretaria e levaria um cadastro.
    ( s ~ '\m(como (funciona|faco|faria|posso)|quero|queria|gostaria de)\M[^.!?;]{0,45}\m(anunciar|divulgar|publicar|colocar a venda|colocar para alugar)\M'
      AND s !~ '\m(de voces|de vcs|dai|seus imoveis|os imoveis de voces|imoveis de voces|com os seus|de voce)\M' )
  FROM t;
$function$;
