CREATE OR REPLACE FUNCTION public.nai_palavra_comum(p_palavra text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT lower(unaccent(coalesce(p_palavra, ''))) = ANY (ARRAY[
    'casa','casas','apartamento','apartamentos','apto','aptos','predio','sala','salas',
    'lote','lotes','terreno','cobertura','flat','loja','galpao','chacara','imovel','imoveis',
    'aluguel','alugar','locacao','venda','vender','comprar','cliente','clientes','corretor',
    'quarto','quartos','suite','suites','vaga','vagas','banheiro','banheiros','mobiliado',
    'semimobiliado','condominio','bairro','valor','valores','preco','precos','visita','visitar',
    'disponivel','procurando','procura','preciso','precisa','obrigado','obrigada','bom','boa',
    'dia','tarde','noite','tudo','bem','sim','nao','esse','essa','isso','aqui','ali','para',
    'pela','pelo','com','sem','mais','menos','muito','pouco','tambem','ainda','agora','depois',
    'manaus','amazonas','reais','mil','milhao','area','areas','metros','andar','novo','nova',
    'velho','antigo','grande','pequeno','melhor','pior','certo','errado','poder','pode','quer',
    'quero','tenho','tem','vou','vai','esta','estao','fica','ficam','manda','mandar','envia',
    'enviar','fotos','foto','video','audio','arquivo','whatsapp','grupo','link','site'
  ]);
$function$;
