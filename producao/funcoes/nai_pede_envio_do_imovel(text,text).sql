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
