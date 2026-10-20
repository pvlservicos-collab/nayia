"""Do nome que o corretor ESCREVEU ao nome que está no cadastro: bairro e condomínio.

Pedro, 09/10/2026: "Normalizar nomes de condomínios e bairros por uma tabela de apelidos editável (ex: 'Parque
Vile', 'Vile'). Se o nome não estiver na tabela, marcar duvidoso e sugerir o mais parecido."

A ordem, para cada nome:
  1. a tabela de apelidos dele (`privado.grupo_apelido`), que vence tudo;
  2. o que o banco da Nay já sabe: o bairro com o nome igual; o jeito curto de dizer o bairro
     (`bairro_normal`: "Parque 10", "pq 10" e "Parque Dez" são o Parque 10 de Novembro); o conjunto/avenida que
     vira bairro (`nai_lugar_citado`: "Vieiralves" é Nossa Senhora das Graças) e o condomínio do cadastro
     (`nay_condominios_candidatos`, as mesmas faixas que a Nay usa para atender);
  2b. um PEDAÇO do nome que só cabe em até 3 bairros ("Laranjeiras", "Distrito"): vale, mas sai duvidoso;
  3. o mais parecido: vale para a conta, mas sai marcado DUVIDOSO, com a sugestão na tela;
  4. nada parecido: "não reconheci", e o pedido não é comparado por lugar (não se chuta lugar).
"""
from __future__ import annotations

from grupos.texto import mobilia_pedida, normal, pede_elevador, pede_financiamento

PARECIDO_MINIMO = 0.55       # abaixo disso o "mais parecido" é só sugestão: não entra na conta


class Lugares:
    def __init__(self, conn):
        self.conn = conn
        self._guardado: dict[tuple[str, str], dict] = {}
        with conn.cursor() as cur:
            cur.execute("SELECT apelido, tipo, oficial FROM privado.grupo_apelido")
            self.apelidos = {a: (t, o) for a, t, o in cur.fetchall()}
            cur.execute("""SELECT DISTINCT btrim(b) FROM (SELECT bairro AS b FROM imoveis UNION SELECT bairro FROM bairro_zona) x
                            WHERE nullif(btrim(b), '') IS NOT NULL""")
            self.bairros = {normal(b): b for (b,) in cur.fetchall()}
            # como a Nay conhece cada bairro: o nome normalizado dela e o jeito curto ("parque 10")
            cur.execute("SELECT bairro, normal, dois FROM bairro_normal")
            self.da_nay = [(b, n or "", d or "") for b, n, d in cur.fetchall()]

    # ── bairro ──
    def bairro(self, escrito: str) -> dict:
        chave = normal(escrito)
        if ("b", chave) in self._guardado:
            return self._guardado[("b", chave)]
        r = {"escrito": escrito, "tipo": "bairro", "como": None, "oficiais": [], "sugestao": None}
        apelido = self.apelidos.get(chave)
        if apelido and apelido[0] == "bairro":
            r.update(como="apelido", oficiais=[apelido[1]])
        elif apelido and apelido[0] == "condominio":
            r = self.condominio(escrito)            # ele chamou de bairro o que a tabela diz que é condomínio
        elif chave in self.bairros:
            r.update(como="exato", oficiais=[self.bairros[chave]])
        else:
            with self.conn.cursor() as cur:
                cur.execute("SELECT nay_normalizar_lugar(%s, true)", (escrito,))
                da_nay = (cur.fetchone()[0] or "").strip()
                iguais = sorted({b for b, n, d in self.da_nay if da_nay and da_nay in (n, d)})
                pedacos = sorted({b for b, n, d in self.da_nay
                                  if len(da_nay) >= 5 and set(da_nay.split()) <= set(n.split())}) if not iguais else []
                cur.execute("SELECT nome, bairros FROM nai_lugar_citado(%s)", (escrito,))
                achados = [b for _, bairros in cur.fetchall() for b in (bairros or [])]
                if iguais:
                    r.update(como="exato", oficiais=iguais)
                elif achados:
                    r.update(como="lugar", oficiais=sorted(set(achados)))
                elif 1 <= len(pedacos) <= 3:
                    r.update(como="pedaco", oficiais=pedacos, sugestao=pedacos[0])
                else:
                    cur.execute("""SELECT p.b, similarity(nay_normalizar_lugar(p.b, true), nay_normalizar_lugar(%s, true))
                                     FROM (SELECT nay_bairro_parecido(%s) AS b) p WHERE p.b IS NOT NULL""", (escrito, escrito))
                    linha = cur.fetchone()
                    if linha and float(linha[1] or 0) >= PARECIDO_MINIMO:
                        r.update(como="parecido", oficiais=[linha[0]], sugestao=linha[0])
                    else:
                        # pode ser um condomínio que a IA leu como bairro
                        c = self.condominio(escrito)
                        if c["como"] in ("apelido", "exato"):
                            r = c
                        elif linha:
                            r["sugestao"] = linha[0]
        self._guardado[("b", chave)] = r
        return r

    # ── condomínio ──
    def _bairros_do(self, cur, nomes: list[str]) -> list[str]:
        if not nomes:
            return []
        cur.execute("""SELECT DISTINCT btrim(b) FROM (
                         SELECT c.bairro AS b FROM condominios c WHERE c.nome = ANY (%s)
                         UNION SELECT i.bairro FROM imoveis i WHERE i.condominio_nome = ANY (%s)) x
                        WHERE nullif(btrim(b), '') IS NOT NULL""", (nomes, nomes))
        return sorted(b for (b,) in cur.fetchall())

    def condominio(self, escrito: str) -> dict:
        chave = normal(escrito)
        if ("c", chave) in self._guardado:
            return self._guardado[("c", chave)]
        r = {"escrito": escrito, "tipo": "condominio", "como": None, "oficiais": [], "chaves": [], "bairros": [], "sugestao": None}
        with self.conn.cursor() as cur:
            apelido = self.apelidos.get(chave)
            if apelido and apelido[0] == "condominio":
                cur.execute("SELECT nay_chave_condominio(%s)", (apelido[1],))
                r.update(como="apelido", oficiais=[apelido[1]], chaves=[cur.fetchone()[0] or ""],
                         bairros=self._bairros_do(cur, [apelido[1]]))
            else:
                cur.execute("SELECT nay_chave_condominio(%s)", (escrito,))
                pedida = cur.fetchone()[0] or ""
                cur.execute("SELECT nome, faixa FROM nay_condominios_candidatos(%s) WHERE faixa IS NOT NULL ORDER BY faixa, nome LIMIT 12",
                            (escrito,))
                cands = cur.fetchall()
                melhor = cands[0][1] if cands else None
                nomes = [n for n, f in cands if f == melhor]
                if pedida and melhor is not None and melhor <= 2:
                    r.update(como="exato", oficiais=nomes, chaves=[pedida], bairros=self._bairros_do(cur, nomes))
                elif pedida and melhor == 3:
                    # ele escreveu um pedaço do nome: serve para a conta, mas pode ser outro condomínio
                    r.update(como="pedaco", oficiais=nomes, chaves=[pedida], bairros=self._bairros_do(cur, nomes),
                             sugestao=nomes[0])
                else:
                    # o cadastro de condomínios tem nomes sem imóvel nenhum: reconhece, mesmo sem ter o que oferecer
                    cur.execute("SELECT nome FROM condominios WHERE nay_chave_condominio(nome) = %s AND %s <> '' ORDER BY nome LIMIT 5",
                                (pedida, pedida))
                    do_cadastro = [n for (n,) in cur.fetchall()]
                    if do_cadastro:
                        r.update(como="exato", oficiais=do_cadastro, chaves=[pedida], bairros=self._bairros_do(cur, do_cadastro))
                    elif cands:
                        r["sugestao"] = cands[0][0]
        r["chaves"] = [c for c in r["chaves"] if c]
        if not r["chaves"]:
            r.update(como=None, oficiais=[])
        self._guardado[("c", chave)] = r
        return r


def _operacao_do_grupo(nome_do_grupo: str | None) -> str | None:
    """O grupo "Locação OFERTA e BUSCA" só tem pedido de aluguel. Só vale quando a mensagem não disse."""
    n = normal(nome_do_grupo)
    aluguel = any(p in n.split() for p in ("locacao", "aluguel", "alugueis", "locacoes"))
    venda = any(p in n.split() for p in ("venda", "vendas", "compra"))
    return "aluguel" if aluguel and not venda else "venda" if venda and not aluguel else None


def resolver(ficha: dict, grupo_nome: str | None, lugares: Lugares) -> tuple[dict, dict, list[str]]:
    """(pedido para a conta, o `local` que vai para a tela, campos que ficaram duvidosos)."""
    duvidosos: list[str] = []
    itens = [lugares.bairro(b) for b in ficha.get("bairros") or []]
    if ficha.get("condominio"):
        itens.append(lugares.condominio(ficha["condominio"]))

    bairros: list[str] = []
    condominios: list[str] = []
    chaves: list[str] = []
    bairros_dos_condominios: list[str] = []
    nao_reconhecidos: list[str] = []
    for it in itens:
        campo = "condominio" if it["escrito"] == ficha.get("condominio") else "bairros"
        if not it["como"]:
            nao_reconhecidos.append(it["escrito"])
            duvidosos.append(campo)
            continue
        if it["como"] in ("parecido", "pedaco"):
            duvidosos.append(campo)
        if it["tipo"] == "condominio":
            condominios += it["oficiais"]
            chaves += it["chaves"]
            bairros_dos_condominios += it["bairros"]
        else:
            bairros += it["oficiais"]

    operacao, origem = ficha.get("operacao"), ("mensagem" if ficha.get("operacao") else None)
    if not operacao:
        operacao = _operacao_do_grupo(grupo_nome)
        origem = "nome do grupo" if operacao else None

    todos_bairros = sorted(set(bairros) | (set(bairros_dos_condominios) if chaves else set()))
    pedido = {
        "operacao": operacao, "tipo": ficha.get("tipo"), "quartos": ficha.get("quartos"),
        "preco_max": ficha.get("preco_max"), "mobiliado": mobilia_pedida(ficha.get("trecho"), ficha.get("mobiliado")), "andar": ficha.get("andar"),
        "suite": ficha.get("suite"), "vagas": ficha.get("vagas"), "pet": ficha.get("pet"),
        # 15/10: pedido lido antes do campo existir (ou que a IA deixou escapar) vale pela frase do trecho
        "financiamento": ficha.get("financiamento") if ficha.get("financiamento") is not None
                         else (True if pede_financiamento(ficha.get("trecho")) else None),
        # 19/10: elevador é pilar; pedido lido antes do campo existir vale pela frase do trecho
        "elevador": ficha.get("elevador") if ficha.get("elevador") is not None
                    else (True if pede_elevador(ficha.get("trecho")) else None),
        "bairro_chaves": [normal(b) for b in todos_bairros],
        "condominio_chaves": sorted(set(chaves)),
        "condominio_sem_reconhecer": bool(ficha.get("condominio") and not chaves),
        # pediu lugar e NADA foi reconhecido: não se compara (nem se chuta)
        "local_nao_reconhecido": nao_reconhecidos if (itens and not bairros and not chaves) else [],
    }
    local = {
        "operacao": operacao, "operacao_origem": origem,
        "bairros": sorted(set(bairros)), "condominios": sorted(set(condominios)),
        "itens": [{k: it.get(k) for k in ("escrito", "tipo", "como", "oficiais", "sugestao")} for it in itens],
    }
    return pedido, local, sorted(set(duvidosos))
