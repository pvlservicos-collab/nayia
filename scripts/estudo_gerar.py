"""O PAINEL DE ESTUDOS da aba Inteligência (Pedro, 25/10/2026): "o código de todas as nays ... de forma bem didática ...
um raio-x de cada função que a nay usa para os seus atendimentos hoje ... como se fosse um fluxo mas vertical, uma função
por vez ... e uma opção exportar".

PASSO 1 (aqui, sem rede): lê o código de cada Nay, separa cada função (nome, arquivo, linhas, código, docstring), acha quem
chama quem e as funções do banco que o código usa (o .sql vivo de producao/funcoes). Grava
imob-easy/admin/dados/inteligencia/estudo-<nay>.json SEM as explicações.
PASSO 2 (scripts/estudo_explicar.py, no servidor com a Luna): escreve a explicação de cada função e junta no mesmo JSON.

  python scripts/estudo_gerar.py            todas as Nays
  python scripts/estudo_gerar.py leads      só uma
As ETAPAS de cada Nay (a ordem de um turno) estão aqui embaixo, em ETAPAS: arquivo inteiro ou "arquivo:funcao".
"""
from __future__ import annotations

import ast
import glob
import json
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORE = os.environ.get("NAY_CORE", r"C:\Users\pedro\nay-core")
SAIDA = os.path.join(RAIZ, "imob-easy", "admin", "dados", "inteligencia")
FUNCOES_SQL = os.path.join(RAIZ, "producao", "funcoes")

NAYS = {
    "parceria": {
        "nome": "Nay Parceria", "quem": "corretores, no número da parceria",
        "descricao": "A Nay nova (nay-core). O modelo só lê a mensagem; o código decide e um texto pronto responde.",
        "raiz": os.path.join(CORE, "nay"), "servidor": "/docker/nay-core/nay (container nay-core, /app/nay)",
        "arquivos": "**/*.py", "fora": ("painel/", "treino/", "__init__.py"),
        "etapas": [
            ("A mensagem chega", "O webhook (o endereço que a Z-API chama a cada mensagem) grava a mensagem crua; o normalizador tira duplicadas e transforma áudio em texto.", ["app.py", "entrada/webhook.py", "entrada/normalizar.py", "entrada/midia.py", "entrada/repo.py"], False),
            ("Espera terminar de escrever (a rajada)", "Junta as mensagens que chegaram em sequência e só segue depois do silêncio.", ["entrada/rajada.py", "worker.py"], False),
            ("Quem está falando", "Corretor da lista? Tel? Equipe? Quem não é atendido fica em silêncio.", ["identidade/contato.py", "pipeline.py:_porta"], False),
            ("Os prazos", "O imóvel em foco vence em 2 h; conversa parada 3 dias recomeça os filtros.", ["estado/prazos.py"], False),
            ("De qual imóvel se fala", "Código digitado, citação, card colado, nome de condomínio, a lista que acabou de sair.", ["contexto/resolver_imovel.py", "contexto/lugares.py", "contexto/varios_da_lista.py", "contexto/pedaco_de_nome.py", "contexto/palavras.py", "contexto/de_fora.py", "contexto/do_grupo.py", "pipeline.py:_lista_na_frente", "pipeline.py:_guardar_lista"], False),
            ("Atalhos sem modelo", "O óbvio resolvido por regra: cortesia, código, 'manda o que tem', 'o primeiro', o filtro respondido.", ["classificador/serve.py", "classificador/atalhos.py", "classificador/frases.py", "classificador/sinais.py", "classificador/valores.py"], False),
            ("O modelo lê (com reserva)", "A Luna devolve a intenção num formulário (JSON). Se cair, o DeepSeek; se também cair, a regex. Os três lado a lado.", ["pipeline.py:_classificar", "classificador/luna.py", "classificador/openrouter.py", "classificador/reserva.py", "classificador/schema.py"], True),
            ("A memória do pedido", "O que já foi dito fica: filtros, pedido novo, vários pedidos na mesma mensagem.", ["estado/memoria.py", "estado/filtros.py", "estado/pedido.py", "estado/multiplos.py", "estado/pergunta.py"], False),
            ("A máquina de estados", "Com a intenção e o estado da conversa, decide a ação: perguntar filtro, buscar, apresentar, dúvida, visita, escalar.", ["estado/maquina.py", "estado/acao.py", "estado/apresentar.py", "estado/escalada.py", "estado/visita.py"], False),
            ("As ferramentas (a ação vira dado)", "Cada ação tem a sua ferramenta; lado a lado as principais: buscar, dúvida, mandar o imóvel, visita.", ["acoes/buscar.py", "acoes/duvida.py", "acoes/responder_duvida.py", "acoes/responder_ficha.py", "acoes/enviar_imovel.py", "acoes/agenda.py"], True),
            ("Antes do card: confere", "Já mandei? Bate com o pedido? O Jev veta?", ["acoes/ja_enviei.py", "acoes/portao.py", "validador/coerencia.py", "classificador/jev.py", "acoes/varios.py", "acoes/preparo.py", "acoes/card_perguntas.py", "acoes/imagem.py", "acoes/grupo.py"], False),
            ("O que ela sabe (o cérebro)", "O catálogo, a ficha, os bairros, os condomínios, os apelidos e as respostas fixas.", ["cerebro/cerebro.py", "cerebro/catalogo.py", "cerebro/ficha.py", "cerebro/ficha_varios.py", "cerebro/respostas_fixas.py", "cerebro/apelidos.py", "cerebro/bairros.py", "cerebro/condominios.py", "cerebro/regioes.py", "cerebro/proximos.py", "cerebro/proprietario.py", "cerebro/fonte.py", "cerebro/repo.py"], False),
            ("Escreve e confere (texto pronto + paredes)", "O texto pronto com os dados certos e o validador: valor e código só de ferramenta, nunca parceria, sem emoji.", ["acoes/executar.py", "compositor/compor.py", "validador/validar.py"], False),
            ("Sai", "A caixa de saída na ordem, o envio pela Z-API, os follow-ups e o ERRO do Tel.", ["saida/caixa.py", "saida/enviador.py", "saida/zapi.py", "saida/followup.py", "saida/erro_do_tel.py", "saida/visita_velha.py", "saida/repo.py"], False),
            ("O turno inteiro e o rastro", "O pipeline liga as etapas na ordem e grava o rastro (trace) de cada uma.", ["pipeline.py", "nos.py", "trace/trace.py", "estado/repo.py"], False),
        ]},
    "leads": {
        "nome": "Nay Leads", "quem": "clientes da OLX e orgânicos, no 8595",
        "descricao": "A Nay do WhatsApp de leads (nay-olx). O Mestre (JEV) escolhe o caminho, o Atendimento (Luna) escreve, as paredes conferem.",
        "raiz": os.path.join(RAIZ, "nay-olx", "olx"), "servidor": "/root/nay-olx/olx (serviço nay-olx)",
        "arquivos": ["whatsapp.py", "agentes.py", "paredes.py", "modelo.py", "ia.py", "banco.py", "visita.py", "grupo.py", "worker.py", "config.py"],
        "etapas": [
            ("Quem escreveu e ficou quieto", "A fila: quem mandou mensagem e ficou 20 s em silêncio; o orgânico novo vira lead.", ["whatsapp.py:_fila", "whatsapp.py:responder", "whatsapp.py:descobrir_organicos", "whatsapp.py:abrir"], False),
            ("As portas", "A equipe está na conversa? Já respondeu? Passou do limite? Só agradeceu?", ["whatsapp.py:_responder_um", "whatsapp.py:_gente_escreveu", "whatsapp.py:novas_depois_da_equipe", "whatsapp.py:so_agradeceu"], False),
            ("O que ela lê (o turno)", "A conversa, as fichas dos imóveis citados, os imóveis da conversa e a visita aberta, num texto só.", ["whatsapp.py:_conversa", "whatsapp.py:_conversa_daqui", "whatsapp.py:da_equipe_no_crm", "whatsapp.py:montar_turno", "whatsapp.py:imoveis_da_conversa", "whatsapp.py:_fichas_citadas", "whatsapp.py:codigos_citados"], False),
            ("O Mestre escolhe o caminho", "Perguntas fechadas ao JEV: quer imóvel? dúvida? visita? fotos? equipe? só cortesia?", ["agentes.py:planejar", "agentes.py:jev", "agentes.py:prompt_para", "agentes.py:partes_do_prompt"], False),
            ("O Atendimento escreve", "A Luna com o prompt da Nay Leads devolve os balões, as ações e os filtros.", ["modelo.py", "whatsapp.py:pergunta_a_toa", "whatsapp.py:finalidade_pelo_valor", "whatsapp.py:quartos_que_ela_disse", "whatsapp.py:acoes_da", "whatsapp.py:_filtros"], False),
            ("As paredes", "Valor e código só do que o turno trouxe; nunca parceria, negativa, bastidor; volta uma vez ao modelo.", ["paredes.py"], False),
            ("Fala", "Manda os balões, sem repetir, e para se a equipe entrar no meio.", ["whatsapp.py:_falar", "whatsapp.py:_baloes_do", "whatsapp.py:mandar_texto"], False),
            ("As ações (lado a lado)", "Cada ação do modelo vira trabalho: fotos/card, buscar (com o veto), visita, perguntar à equipe.", ["whatsapp.py:_fazer", "whatsapp.py:mandar_imovel", "whatsapp.py:_buscar_e_mandar", "agentes.py:filtrar_imoveis", "visita.py"], True),
            ("O rastro dos agentes", "Cada passo vira um evento: o Registro de fluxos e a aba Arquitetura do CRM.", ["agentes.py:registrar", "agentes.py:passo", "agentes.py:atendimento", "agentes.py:acao", "agentes.py:humano"], False),
        ]},
    "olx": {
        "nome": "Nay da OLX", "quem": "quem escreve no chat do anúncio da OLX",
        "descricao": "A Nay do chat da OLX (nay-olx/olx/nay.py): pede o WhatsApp e passa o lead para a Nay Leads.",
        "raiz": os.path.join(RAIZ, "nay-olx", "olx"), "servidor": "/root/nay-olx/olx (serviço nay-olx)",
        "arquivos": ["nay.py", "chat.py", "paredes.py"],
        "etapas": [
            ("O chat da OLX", "Lê as conversas do chat da OLX pelo navegador e manda as respostas.", ["chat.py"], False),
            ("Decide o que dizer", "O modelo lê a conversa e o anúncio e decide: pedir o WhatsApp, encaminhar, ou passar para gente.", ["nay.py:montar_turno", "nay.py:decidir", "nay.py:_perfil", "nay.py:_ficha"], False),
            ("As paredes", "Sem emoji, link, telefone; valor e código só do turno; nunca parceria nem negativa.", ["nay.py:limpar_balao", "paredes.py"], False),
        ]},
    "corretores": {
        "nome": "Nay Corretores", "quem": "corretor que oferece imóvel no 8595",
        "descricao": "A Nay que recebe o corretor (nay-olx/olx/buscas.py): pergunta o imóvel, cadastra como parceiro e avisa as buscas.",
        "raiz": os.path.join(RAIZ, "nay-olx", "olx"), "servidor": "/root/nay-olx/olx (serviço nay-olx)",
        "arquivos": ["buscas.py", "parceiro.py", "busca_olx.py"],
        "etapas": [
            ("Quem é corretor", "Pede parceria ou diz que é corretor: não vira lead, vai para a Nay Corretores.", ["buscas.py:parece_corretor"], False),
            ("A busca do cliente", "O que a base deu; sem o perfil exato, os grupos, os anunciantes da OLX e os corretores.", ["buscas.py"], False),
            ("A busca na OLX e o parceiro", "A ordem de busca na OLX e o pré-cadastro do imóvel do parceiro.", ["busca_olx.py", "parceiro.py"], True),
        ]},
    "captacao": {
        "nome": "Nay Captação", "quem": "proprietários, pelo número oficial e pela OLX",
        "descricao": "A Nay que fala com os donos (nay-captacao): um agente com ferramentas e um portão de saída.",
        "raiz": os.path.join(RAIZ, "nay-captacao", "captacao"), "servidor": "/root/nay-captacao/captacao (serviço nay-captacao)",
        "arquivos": "*.py", "fora": ("__init__.py",),
        "etapas": [
            ("O serviço", "Atende quem escreveu e, quando ligado, dispara o modelo que abre a conversa.", ["worker.py", "disparo.py"], False),
            ("O turno do proprietário", "Junta as mensagens do intervalo e monta o cabeçalho que o modelo lê.", ["turno.py", "atender.py"], False),
            ("O agente e as ferramentas", "O modelo, o prompt e o laço das ferramentas (guardar a situação, a ficha, a indicação...).", ["modelo.py", "ferramentas.py", "contrato.py", "venda.py"], False),
            ("O portão de saída", "O que o modelo escreveu vira os balões que saem, ou nada.", ["resposta.py", "envio.py"], False),
            ("A resposta vai ao cadastro", "A resposta do dono vira campo do imóvel; o palpite da fila do cadastro rápido.", ["cadastro.py", "preparar.py", "palpite.py"], False),
            ("A Nay dos proprietários da OLX", "O dono que anunciou na OLX, pelo WhatsApp da parceria, com o roteiro do Pedro.", ["olx.py"], False),
        ]},
    "cadastro": {
        "nome": "Nay Cadastro", "quem": "o Tel no grupo de cadastro e o corretor no privado",
        "descricao": "O cadastro de imóvel pelo WhatsApp (nay-cadastro): o modelo só LÊ; o código decide a próxima pergunta.",
        "raiz": os.path.join(RAIZ, "nay-cadastro", "cadastro"), "servidor": "/root/nay-cadastro/cadastro (serviço nay-cadastro)",
        "arquivos": "*.py", "fora": ("__init__.py",),
        "etapas": [
            ("O serviço", "A cada 3 s lê o grupo, trata as respostas do privado e começa as conversas da fila.", ["worker.py"], False),
            ("A leva do grupo", "As mensagens que o Tel encaminha de uma vez são UM imóvel.", ["leva.py", "no_grupo.py", "condominio.py"], False),
            ("O modelo só lê", "Tira os dados do texto e da resposta do corretor; não decide nada.", ["modelo.py", "ficha.py"], False),
            ("O código pergunta", "O modelo de cadastro: o que falta, em que ordem, uma pergunta por vez, e o fim.", ["campos.py", "fluxo.py", "no_privado.py", "autorizacao.py"], False),
            ("Grava e manda", "O mesmo caminho da aba Editar imóvel e a saída pela parceria ou pelo 8595.", ["site.py", "envio.py", "banco.py"], True),
        ]},
}

SQL_NOME = re.compile(r"\b((?:olx|site|nai|nay|crm|core|captacao|busca|privado\.[a-z_]+|agente)[a-z0-9_]*)\s*\(", re.I)


def _arquivos(cfg: dict) -> list[str]:
    raiz = cfg["raiz"]
    if isinstance(cfg["arquivos"], list):
        return [os.path.join(raiz, a) for a in cfg["arquivos"] if os.path.exists(os.path.join(raiz, a))]
    fora = cfg.get("fora", ())
    fs = sorted(glob.glob(os.path.join(raiz, cfg["arquivos"]), recursive=True))
    return [f for f in fs if "__pycache__" not in f and not any(x in f.replace("\\", "/") for x in fora)]


def _sqls_vivos() -> dict[str, str]:
    """nome da função -> arquivo .sql vivo (producao/funcoes/<nome>(<tipos>).sql)."""
    vivos = {}
    for f in glob.glob(os.path.join(FUNCOES_SQL, "*.sql")):
        nome = os.path.basename(f).split("(")[0]
        vivos.setdefault(nome.lower(), f)
    return vivos


def gerar(chave: str, cfg: dict, vivos: dict) -> dict:
    raiz = cfg["raiz"]
    funcoes: dict[str, dict] = {}
    arquivos = []
    for f in _arquivos(cfg):
        rel = os.path.relpath(f, raiz).replace("\\", "/")
        fonte = open(f, encoding="utf-8").read()
        linhas = fonte.split("\n")
        m = ast.parse(fonte)
        ids = []

        def visitar(no, classe=None):
            for n in ast.iter_child_nodes(no):
                if isinstance(n, ast.ClassDef):
                    visitar(n, n.name)
                elif isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    nome = f"{classe}.{n.name}" if classe else n.name
                    fid = f"{rel}:{nome}"
                    ini = min([d.lineno for d in n.decorator_list] + [n.lineno])
                    codigo = "\n".join(linhas[ini - 1:n.end_lineno])
                    chama = sorted({(c.func.id if isinstance(c.func, ast.Name) else c.func.attr)
                                    for c in ast.walk(n) if isinstance(c, ast.Call)
                                    and isinstance(c.func, (ast.Name, ast.Attribute))})
                    sqls = sorted({s.split(".")[-1].lower() for s in SQL_NOME.findall(codigo)} & set(vivos))
                    funcoes[fid] = {"id": fid, "nome": nome, "arquivo": rel, "linha": ini, "fim": n.end_lineno,
                                    "codigo": codigo, "doc": ast.get_docstring(n) or "", "chama_nomes": chama,
                                    "sql": sqls, "tipo": "python"}
                    ids.append(fid)
        visitar(m)
        arquivos.append({"caminho": rel, "servidor": cfg["servidor"].split(" ")[0] + "/" + rel, "linhas": len(linhas),
                         "doc": ast.get_docstring(m) or "", "funcoes": ids, "codigo": fonte})
    # quem chama quem (pelo nome; o do mesmo arquivo vem primeiro)
    por_nome: dict[str, list[str]] = {}
    for fid, fn in funcoes.items():
        por_nome.setdefault(fn["nome"].split(".")[-1], []).append(fid)
    for fid, fn in funcoes.items():
        alvos = []
        for nome in fn.pop("chama_nomes"):
            cands = por_nome.get(nome, [])
            mesmo = [c for c in cands if c.split(":")[0] == fn["arquivo"]]
            alvos += (mesmo or cands)[:2]
        fn["chama"] = [a for a in dict.fromkeys(alvos) if a != fid]
    for fid, fn in funcoes.items():
        fn["chamada_por"] = sorted(o for o, x in funcoes.items() if fid in x["chama"])
    # as funções do banco que o código usa
    for nome in sorted({s for fn in funcoes.values() for s in fn["sql"]}):
        caminho = vivos[nome]
        sid = f"banco:{nome}"
        funcoes[sid] = {"id": sid, "nome": nome, "arquivo": "banco (naydb)", "linha": 1, "fim": 0,
                        "codigo": open(caminho, encoding="utf-8").read(), "doc": "", "chama": [], "tipo": "sql",
                        "servidor": f"naydb, função public.{nome} (foto: producao/funcoes/{os.path.basename(caminho)})",
                        "chamada_por": sorted(fid for fid, fn in funcoes.items() if nome in fn.get("sql", []))}
    # as etapas: arquivo inteiro ou arquivo:funcao
    etapas, usados = [], set()
    for titulo, expl, refs, lado in cfg["etapas"]:
        fids = []
        for r in refs:
            if ":" in r:
                if r in funcoes:
                    fids.append(r)
                else:
                    print(f"  [{chave}] etapa '{titulo}': não achei {r}", file=sys.stderr)
            else:
                fids += [a["funcoes"] for a in arquivos if a["caminho"] == r][0] if any(a["caminho"] == r for a in arquivos) else []
                if not any(a["caminho"] == r for a in arquivos):
                    print(f"  [{chave}] etapa '{titulo}': não achei o arquivo {r}", file=sys.stderr)
        fids = [f for f in dict.fromkeys(fids) if f not in usados]
        usados.update(fids)
        etapas.append({"titulo": titulo, "explicacao": expl, "lado_a_lado": lado, "funcoes": fids})
    sobra = [f for f in funcoes if f not in usados and not f.startswith("banco:")]
    if sobra:
        etapas.append({"titulo": "As outras funções", "explicacao": "O resto do código desta Nay, por arquivo.",
                       "lado_a_lado": False, "funcoes": sobra})
    banco = [f for f in funcoes if f.startswith("banco:")]
    if banco:
        etapas.append({"titulo": "As funções do banco que ela usa", "explicacao": "O que o código chama no banco (naydb), como está vivo hoje.",
                       "lado_a_lado": False, "funcoes": banco})
    return {"nay": chave, "nome": cfg["nome"], "quem": cfg["quem"], "descricao": cfg["descricao"],
            "servidor": cfg["servidor"], "etapas": etapas, "arquivos": arquivos, "funcoes": funcoes}


def main() -> None:
    os.makedirs(SAIDA, exist_ok=True)
    vivos = _sqls_vivos()
    quais = sys.argv[1:] or list(NAYS)
    for chave in quais:
        d = gerar(chave, NAYS[chave], vivos)
        destino = os.path.join(SAIDA, f"estudo-{chave}.json")
        antigo = json.load(open(destino, encoding="utf-8")) if os.path.exists(destino) else {}
        # as explicações já escritas (passo 2) ficam, se o código da função não mudou
        for fid, fn in d["funcoes"].items():
            velho = (antigo.get("funcoes") or {}).get(fid)
            if velho and velho.get("codigo") == fn["codigo"] and velho.get("explicacao"):
                for k in ("explicacao", "passos", "jargoes", "tags", "resumo"):
                    if k in velho:
                        fn[k] = velho[k]
        json.dump(d, open(destino, "w", encoding="utf-8"), ensure_ascii=False)
        n_sql = sum(1 for f in d["funcoes"].values() if f["tipo"] == "sql")
        print(f"{chave}: {len(d['arquivos'])} arquivos, {len(d['funcoes']) - n_sql} funções, {n_sql} do banco, "
              f"{len(d['etapas'])} etapas -> {os.path.getsize(destino) // 1024} KB")


if __name__ == "__main__":
    main()
