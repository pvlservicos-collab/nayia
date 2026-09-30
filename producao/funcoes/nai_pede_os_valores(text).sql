CREATE OR REPLACE FUNCTION public.nai_pede_os_valores(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT s ~ ('(quais? (sao )?(os )?(valor|preco)|'
           || '(valor|preco)e?s? que (voce|vc|tu) tem|'
           || 'quanto (ta|esta|e) (o )?(aluguel|valor)|'
           || 'o que (voce|vc|tu) tem|'
           || 'que que (voce|vc) tem|'
           || 'todas as opcoes|todas opcoes|todos os (imoveis|que tiver)|'
           || 'me (manda|passa|mostra) (tudo|todas|todos|a lista|as opcoes)|'
           || '(tem|teria) (alguma|algum|algo)\M|'
           || 'ja tem (alguma|algum)\M|'
           || 'quais (voce|vc) tem|quais tem\M)')
    FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS s) x;
$function$;
