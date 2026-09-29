BEGIN;
CREATE OR REPLACE FUNCTION public.nai_rodar_casos()
 RETURNS TABLE(passou boolean, regra text, frase text, esperado text, deu text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE c record; v text;
BEGIN
  FOR c IN SELECT * FROM nai_caso WHERE ativo ORDER BY id LOOP
    v := CASE c.pergunta
      WHEN 'tipo'       THEN coalesce(nai_tipo_pedido(c.frase), '-')
      WHEN 'tipo_canon' THEN coalesce(nai_tipo_canonico(c.frase), '-')
      WHEN 'negocio'    THEN coalesce(nay_negocio_pedido(c.frase), '-')
      WHEN 'cortesia'   THEN nai_e_so_cortesia(c.frase)::text
      WHEN 'oferta'     THEN nai_oferece_imovel(c.frase)::text
      WHEN 'anuncio'    THEN nai_e_anuncio_dele(c.frase)::text
      WHEN 'catalogo'   THEN nai_pergunta_de_catalogo(c.frase)::text
      WHEN 'link'       THEN nai_e_link_de_produto(c.frase)::text
      WHEN 'pede_lista' THEN nai_pede_os_valores(c.frase)::text
      WHEN 'sem_bairro' THEN nai_sem_preferencia_de_bairro(c.frase)::text
      WHEN 'de_imovel'  THEN nai_e_assunto_de_locacao(c.frase)::text
      WHEN 'imoveis'    THEN nai_imoveis_pedidos(c.frase, '')::text
      WHEN 'passe'      THEN nai_passe_do_citado(nai_imoveis_pedidos(c.frase, ''))::text
      WHEN 'texto_limpo' THEN nai_texto_sem_os_barrados(c.frase)
      WHEN 'nomes'      THEN nai_corrigir_nomes(c.frase)
      WHEN 'valor'      THEN coalesce(nay_maior_valor(c.frase)::text, '-')
      WHEN 'pelo_nome'  THEN nai_imovel_pelo_condominio(c.frase, '')::text  -- 190
      WHEN 'negocio_valor' THEN coalesce(nai_negocio_pelo_valor(c.frase), '-')  -- 190
      WHEN 'tipo_conversa'    THEN coalesce(nai_tipo_das_falas(string_to_array(c.frase, ' || ')), '-')
      WHEN 'negocio_conversa' THEN coalesce(nai_negocio_das_falas(string_to_array(c.frase, ' || ')), '-')
      ELSE '(pergunta desconhecida: ' || c.pergunta || ')'
    END;
    passou := (v = c.esperado);
    regra := c.regra; frase := c.frase; esperado := c.esperado; deu := v;
    RETURN NEXT;
  END LOOP;
END;
$function$;

INSERT INTO nai_caso (quando, quem, frase, pergunta, esperado, regra, ativo) VALUES
 ('2026-09-29', 'Sulivam 29/09', 'Ela precisa de mais um cômodo P escritório Ideal 3 quartos', 'nomes',
  'Ela precisa de mais um cômodo P escritório Ideal 3 quartos', 'palavra de gente não vira nome de bairro (cômodo -> Coroado)', true),
 ('2026-09-29', 'corpus 14d', 'estou aqui dentro do condominio', 'nomes',
  'estou aqui dentro do condominio', 'palavra conhecida não é trocada (dentro -> Centro)', true),
 ('2026-09-29', 'corpus 14d', 'tem na luar ponta negra?', 'nomes',
  'tem na luar ponta negra?', 'palavra conhecida só troca por uma letra (luar -> life)', true),
 ('2026-09-29', 'Ponta Negra 29/09', 'Grato Vou encaminhar Tem Vieira Alves e Adrianópolis 3 quartos ?', 'pelo_nome',
  '{}', 'nome de bairro não é pista de condomínio (Adrianópolis -> Jardim Adrianópolis 5748)', true),
 ('2026-09-29', 'Ponta Negra 29/09', 'Me passa a sua lista de vc tem disponível na ponta negra ii de 7mil', 'negocio_valor',
  'locacao', 'o valor diz o negócio da conversa (7 mil = locação)', true),
 ('2026-09-29', 'Ponta Negra 29/09', 'Tem Vieira Alves e Adrianópolis 3 quartos ?', 'negocio_valor',
  '-', '3 quartos não é valor', true),
 ('2026-09-29', 'corpus', 'Bloco 13 apto 1601', 'negocio_valor',
  '-', 'número de apartamento não é valor', true),
 ('2026-09-29', 'Ponta Negra 29/09', 'Me passa a sua lista na ponta negra ii de 7mil || Tem Vieira Alves e Adrianópolis 3 quartos ?', 'negocio_conversa',
  'locacao', 'a conversa guarda o negócio: pediu 7 mil de manhã, segue locação à tarde', true);
COMMIT;
