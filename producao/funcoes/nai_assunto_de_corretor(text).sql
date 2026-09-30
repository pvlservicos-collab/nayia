CREATE OR REPLACE FUNCTION public.nai_assunto_de_corretor(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT x ~ ('(imovel|imoveis|apartamento|\mapto\M|\map\M|casa|kitnet|flat|sala comercial|terreno|'
              || 'aluguel|alugar|locacao|venda|vender|comprar|financ|'
              || 'visita|visitar|agendar|disponivel|disponibilidade|'
              || 'quarto|suite|banheiro|vaga|garagem|mobiliad|condominio|bairro|metragem|'
              || 'foto|fotos|imagem|imagens|fachada|card|anuncio|'
              || 'corretor|creci|cliente|proposta|valor|preco)')
     AND x !~ '(boleto|segunda via|contrato de trabalho|curriculo|vaga de emprego|processo seletivo)'
  FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS x) t;
$function$;
