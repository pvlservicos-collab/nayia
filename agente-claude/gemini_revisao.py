#!/usr/bin/env python3
"""A REVISÃO DA NAY PELO GEMINI (Pedro, 23/10/2026): "um modelo mais barato com o Gemini que vai analisar todas as
conversas da semana, separar o erro, e me mandar um markdown com conversa / erro, já mandando só os erros para o Claude
corrigir ... por enquanto só quero ele gerando os arquivos das conversas dessa semana".

  gemini_revisao.py                                  a semana de hoje (de segunda até hoje, Manaus)
  gemini_revisao.py --desde 2026-10-19 --ate 2026-10-23 [--modelo gemini-flash-latest] [--sem-importar]

O caminho:
  1. importar_nay.py exporta as conversas da Nay Parceria (nay-core, só leitura) para
     projetos/revisao-gemini/dados/conversas (um arquivo por corretor por dia, com o RESULTADO no fim);
  2. dados/semana/<desde>_a_<ate>/conversas.md: todas as conversas do período num markdown só (o que vai ao Gemini);
  3. o Gemini (API do Google, a chave em /etc/agente-claude/gemini.env) lê em partes, com o prompt do projeto
     (contexto.md), e devolve só as conversas com erro (nota < 90), em JSON;
  4. dados/semana/<desde>_a_<ate>/erros.md (e erros.json): conversa / erro, cada bloco com os erros e a conversa
     inteira, pronto para ir ao Claude corrigir. E uma conversa no quadro do projeto com o resumo.
Nada é corrigido nem enviado a ninguém: só arquivos.
"""
import argparse, json, os, sqlite3, subprocess, sys, time, urllib.error, urllib.request, uuid
from datetime import date, datetime, timedelta, timezone

BASE = "/opt/agente-claude"
PID = "revisao-gemini"
PROJ = os.path.join(BASE, "projetos", PID)
ENV = "/etc/agente-claude/gemini.env"
API = "https://generativelanguage.googleapis.com/v1beta/models/{m}:generateContent"
POR_PARTE = 150_000          # caracteres de conversa por chamada (o modelo aguenta mais; menor = leitura mais atenta)
NOTA_CORTE = 90

INSTRUCAO_DA_SAIDA = """
## A resposta (só JSON)
Você recebe várias conversas, cada uma começando com "=== CONVERSA <id> ===". Devolva SÓ as conversas com nota abaixo
de 90, com o id EXATAMENTE como veio. Conversa sem erro não entra. Se nenhuma tiver erro, a lista vem vazia."""

ESQUEMA = {
    "type": "OBJECT",
    "properties": {"conversas": {"type": "ARRAY", "items": {
        "type": "OBJECT",
        "properties": {
            "id": {"type": "STRING"}, "nota": {"type": "INTEGER"}, "resumo": {"type": "STRING"},
            "erros": {"type": "ARRAY", "items": {"type": "OBJECT", "properties": {
                "tipo": {"type": "STRING"}, "gravidade": {"type": "STRING", "enum": ["alta", "media", "baixa"]},
                "trecho": {"type": "STRING"}, "o_que_aconteceu": {"type": "STRING"}, "o_que_devia": {"type": "STRING"},
                "pista_para_o_claude": {"type": "STRING"}},
                "required": ["tipo", "gravidade", "trecho", "o_que_aconteceu", "o_que_devia", "pista_para_o_claude"]}}},
        "required": ["id", "nota", "resumo", "erros"]}}},
    "required": ["conversas"],
}


def chave() -> str:
    with open(ENV, encoding="utf-8") as f:
        for linha in f:
            if linha.startswith("GEMINI_API_KEY="):
                return linha.split("=", 1)[1].strip()
    raise SystemExit("sem GEMINI_API_KEY em " + ENV)


def hoje_manaus() -> date:
    return (datetime.now(timezone.utc) - timedelta(hours=4)).date()


def conversas_do_periodo(pasta_conv: str, desde: date, ate: date) -> list[tuple[str, str]]:
    """[(id, texto)]: id = 'AAAA-MM-DD/<tel4>-<n>', na ordem do dia e do arquivo."""
    saida = []
    d = desde
    while d <= ate:
        dia = os.path.join(pasta_conv, d.isoformat())
        if os.path.isdir(dia):
            for nome in sorted(os.listdir(dia)):
                if nome.endswith(".txt") and not nome.startswith("_"):
                    with open(os.path.join(dia, nome), encoding="utf-8") as f:
                        saida.append((f"{d.isoformat()}/{nome[:-4]}", f.read().strip()))
        d += timedelta(days=1)
    return saida


def em_partes(conversas: list[tuple[str, str]]) -> list[list[tuple[str, str]]]:
    partes, atual, tam = [], [], 0
    for cid, txt in conversas:
        if atual and tam + len(txt) > POR_PARTE:
            partes.append(atual)
            atual, tam = [], 0
        atual.append((cid, txt))
        tam += len(txt)
    return partes + ([atual] if atual else [])


def perguntar(modelo: str, prompt: str, parte: list[tuple[str, str]], k: str) -> tuple[list[dict], dict]:
    entrada = "\n\n".join(f"=== CONVERSA {cid} ===\n{txt}" for cid, txt in parte)
    corpo = {"systemInstruction": {"parts": [{"text": prompt + INSTRUCAO_DA_SAIDA}]},
             "contents": [{"role": "user", "parts": [{"text": entrada}]}],
             "generationConfig": {"temperature": 0.2, "responseMimeType": "application/json", "responseSchema": ESQUEMA}}
    ultimo = ""
    for tentativa in range(5):
        req = urllib.request.Request(API.format(m=modelo), data=json.dumps(corpo).encode(), method="POST",
                                     headers={"Content-Type": "application/json", "x-goog-api-key": k})
        try:
            with urllib.request.urlopen(req, timeout=600) as r:
                j = json.loads(r.read())
            texto = "".join(p.get("text", "") for p in j["candidates"][0]["content"]["parts"])
            return json.loads(texto).get("conversas") or [], j.get("usageMetadata") or {}
        except urllib.error.HTTPError as e:
            ultimo = f"HTTP {e.code}: {e.read()[:300].decode('utf-8', 'replace')}"
            if e.code not in (429, 500, 502, 503, 504):
                break
        except (urllib.error.URLError, TimeoutError, KeyError, IndexError, json.JSONDecodeError) as e:
            ultimo = f"{type(e).__name__}: {e}"
        time.sleep(10 * (tentativa + 1))
    raise RuntimeError(ultimo)


def markdown_das_conversas(conversas, desde, ate) -> str:
    cab = f"# Conversas da Nay Parceria, {desde:%d/%m} a {ate:%d/%m/%Y} ({len(conversas)} conversas)\n\n"
    return cab + "\n\n".join(f"## {cid}\n\n```text\n{txt}\n```" for cid, txt in conversas) + "\n"


def markdown_dos_erros(achadas, textos, desde, ate, modelo, n_total, n_partes, uso, falhas) -> str:
    alta = sum(1 for c in achadas if any(e["gravidade"] == "alta" for e in c["erros"]))
    mil = lambda n: f"{n:,}".replace(",", ".")  # noqa: E731
    linhas = [f"# Conversas com erro da Nay Parceria: {desde:%d/%m} a {ate:%d/%m/%Y}", "",
              f"O Gemini ({modelo}) leu {n_total} conversas em {n_partes} parte(s) e separou **{len(achadas)} com erro** "
              f"(nota abaixo de {NOTA_CORTE}), {alta} com erro grave. Tokens: {mil(uso['entrada'])} de entrada e "
              f"{mil(uso['saida'])} de saída.", ""]
    if falhas:
        linhas += [f"⚠️ {len(falhas)} parte(s) não foram lidas (o Gemini falhou): " + "; ".join(falhas), ""]
    linhas += ["Para o Claude: cada bloco é uma conversa da Nay Parceria com erro. Confira o erro na conversa, ache a "
               "regra da Nay (nay-core) que causou e corrija como diz o combinado do projeto Nay Parceria (revisão). "
               "Erro que a conversa não prova: não mexa.", ""]
    for n, c in enumerate(sorted(achadas, key=lambda x: (x["nota"], x["id"])), 1):
        dia, arq = c["id"].split("/", 1)
        linhas += [f"## {n}. {dia} · …{arq.split('-')[0]} · nota {c['nota']}", "", f"Arquivo: `dados/conversas/{c['id']}.txt`",
                   "", f"**Resumo:** {c['resumo']}", "", "**Erros**", ""]
        for i, e in enumerate(c["erros"], 1):
            trecho = "\n".join(f"     > {l}" for l in str(e["trecho"]).strip().splitlines() if l.strip())
            linhas += [f"{i}. **[{e['gravidade']}] {e['tipo']}**: {e['o_que_aconteceu']}",
                       f"   - Devia: {e['o_que_devia']}",
                       "   - Trecho:", trecho,
                       f"   - Pista para o Claude: {e['pista_para_o_claude']}"]
        linhas += ["", "**A conversa**", "", "```text", textos.get(c["id"], "(não achei o texto)"), "```", ""]
    return "\n".join(linhas) + "\n"


def no_quadro(titulo: str, pedido: str, resposta: str, ok: bool, uso: dict) -> None:
    """O resumo aparece no quadro do projeto (uma conversa nova), como as outras respostas do painel."""
    con = sqlite3.connect(os.path.join(BASE, "metricas.db"))
    t = datetime.now(timezone.utc).isoformat(timespec="seconds")
    cid = con.execute("INSERT INTO conversas (projeto, sessao, titulo, criada_em, atualizada_em) VALUES (?, ?, ?, ?, ?)",
                      (PID, str(uuid.uuid4()), titulo[:80], t, t)).lastrowid
    con.execute("INSERT INTO mensagens (conversa_id, papel, texto, inicio, origem) VALUES (?, 'voce', ?, ?, 'rotina')",
                (cid, pedido, t))
    con.execute("INSERT INTO mensagens (conversa_id, papel, texto, inicio, ok, tokens_entrada, tokens_saida, erro) "
                "VALUES (?, 'claude', ?, ?, ?, ?, ?, ?)",
                (cid, resposta if ok else None, t, 1 if ok else 0, uso.get("entrada"), uso.get("saida"),
                 None if ok else resposta[:2000]))
    con.commit()
    con.close()


def main():
    a = argparse.ArgumentParser()
    a.add_argument("--desde")
    a.add_argument("--ate")
    a.add_argument("--modelo")
    a.add_argument("--sem-importar", action="store_true")
    a.add_argument("--so-markdown", action="store_true", help="refaz o erros.md a partir do erros.json (sem o Gemini)")
    o = a.parse_args()
    ate = date.fromisoformat(o.ate) if o.ate else hoje_manaus()
    desde = date.fromisoformat(o.desde) if o.desde else ate - timedelta(days=ate.weekday())
    cfg = json.load(open(os.path.join(PROJ, "projeto.json"), encoding="utf-8"))
    modelo = o.modelo or cfg.get("modelo") or "gemini-flash-latest"
    pasta_conv = os.path.join(PROJ, "dados", "conversas")
    if o.so_markdown:
        saida = os.path.join(PROJ, "dados", "semana", f"{desde.isoformat()}_a_{ate.isoformat()}")
        conversas = conversas_do_periodo(pasta_conv, desde, ate)
        achadas = json.load(open(os.path.join(saida, "erros.json"), encoding="utf-8"))
        cab = open(os.path.join(saida, "erros.md"), encoding="utf-8").read().split("\n")[2]
        n_partes = len(em_partes(conversas))
        md = markdown_dos_erros(achadas, dict(conversas), desde, ate, modelo, len(conversas), n_partes,
                                {"entrada": 0, "saida": 0}, [])
        md = md.replace(md.split("\n")[2], cab, 1)        # a linha dos tokens fica a da rodada de verdade
        with open(os.path.join(saida, "erros.md"), "w", encoding="utf-8", newline="\n") as f:
            f.write(md)
        print("refeito:", os.path.join(saida, "erros.md"))
        return
    if not o.sem_importar:
        subprocess.run(["/usr/bin/python3", os.path.join(BASE, "importar_nay.py"), "--desde", desde.isoformat(),
                        "--ate", ate.isoformat(), "--saida", pasta_conv], check=True)
    conversas = conversas_do_periodo(pasta_conv, desde, ate)
    saida = os.path.join(PROJ, "dados", "semana", f"{desde.isoformat()}_a_{ate.isoformat()}")
    os.makedirs(saida, exist_ok=True)
    with open(os.path.join(saida, "conversas.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write(markdown_das_conversas(conversas, desde, ate))
    prompt = open(os.path.join(PROJ, "contexto.md"), encoding="utf-8").read()
    k = chave()
    textos = dict(conversas)
    achadas, falhas, uso = [], [], {"entrada": 0, "saida": 0}
    partes = em_partes(conversas)
    for n, parte in enumerate(partes, 1):
        try:
            lista, u = perguntar(modelo, prompt, parte, k)
        except RuntimeError as e:
            falhas.append(f"parte {n} ({parte[0][0]} a {parte[-1][0]}): {str(e)[:160]}")
            print(f"parte {n}/{len(partes)}: FALHOU {e}", flush=True)
            continue
        uso["entrada"] += int(u.get("promptTokenCount") or 0)
        uso["saida"] += int(u.get("candidatesTokenCount") or 0) + int(u.get("thoughtsTokenCount") or 0)
        validas = [c for c in lista if c.get("id") in textos and int(c.get("nota") or 100) < NOTA_CORTE and c.get("erros")]
        achadas += validas
        print(f"parte {n}/{len(partes)}: {len(parte)} conversas, {len(validas)} com erro", flush=True)
    with open(os.path.join(saida, "erros.json"), "w", encoding="utf-8") as f:
        json.dump(achadas, f, ensure_ascii=False, indent=1)
    md = markdown_dos_erros(achadas, textos, desde, ate, modelo, len(conversas), len(partes), uso, falhas)
    with open(os.path.join(saida, "erros.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write(md)
    rel = os.path.relpath(saida, PROJ)
    resumo = (f"Li {len(conversas)} conversas de {desde:%d/%m} a {ate:%d/%m} e separei **{len(achadas)} com erro**.\n\n"
              f"- Todas as conversas: `{rel}/conversas.md`\n- Só as com erro (para o Claude corrigir): `{rel}/erros.md`\n"
              + (f"- ⚠️ {len(falhas)} parte(s) falharam\n" if falhas else "")
              + "\n" + "\n".join(f"- …{c['id'].split('/', 1)[1].split('-')[0]} ({c['id'][:10]}), nota {c['nota']}: {c['resumo']}"
                                 for c in sorted(achadas, key=lambda x: x["nota"])[:15]))
    no_quadro(f"Revisão {desde:%d/%m} a {ate:%d/%m}",
              f"Revisar as conversas da Nay Parceria de {desde:%d/%m} a {ate:%d/%m} e separar só as com erro "
              f"(prompt: contexto.md do projeto).", resumo, ok=not (falhas and not achadas and len(falhas) == len(partes)),
              uso=uso)
    print(json.dumps({"conversas": len(conversas), "com_erro": len(achadas), "partes": len(partes), "falhas": len(falhas),
                      "uso": uso, "arquivos": [os.path.join(saida, "conversas.md"), os.path.join(saida, "erros.md")]},
                     ensure_ascii=False))


if __name__ == "__main__":
    main()
