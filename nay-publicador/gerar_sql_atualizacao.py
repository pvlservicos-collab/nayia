"""
Prompt 5 do guia: gera o SQL de atualização a partir de catalogo.json e da
exportação CSV do banco. NÃO roda nada — só escreve atualiza.sql.

Uso:
    .venv/bin/python gerar_sql_atualizacao.py

Colunas que o site fornece e que por isso entram nos INSERT/UPDATE:
  codigo, condominio (-> condominio_nome), endereco (-> logradouro), bairro,
  complemento, area (-> area_util, ver ressalva no cabeçalho do SQL gerado),
  quartos, suites, banheiros, vagas, valor_venda, valor_aluguel, e_parceiro.

Colunas de `imoveis` que o site NÃO fornece (ficam sem valor nos INSERT dos
códigos novos): tipo, status, disponivel, area_total, vagas_cobertas, sol,
andar, taxa_condominio, iptu, mobilia, descricao, caracteristicas, origem,
bloqueado, motivo_bloqueio, travado, travado_motivo, travado_em, extras,
captado_por, captado_em.
"""
from comparar_catalogo import carregar_site, carregar_banco

CATALOGO = "catalogo.json"
BANCO_CSV = "imoveis_export.csv"
SAIDA = "atualiza.sql"

COLUNAS_UPDATE_COMUM = [
    "condominio_nome", "bairro", "valor_venda", "valor_aluguel", "e_parceiro",
]

COLUNAS_INSERT = [
    "codigo", "condominio_nome", "logradouro", "bairro", "complemento",
    "area_util", "quartos", "suites", "banheiros", "vagas",
    "valor_venda", "valor_aluguel", "e_parceiro", "publicado_no_site",
]

COLUNAS_SEM_DADO_DO_SITE = [
    "tipo", "status", "disponivel", "area_total", "vagas_cobertas", "sol",
    "andar", "taxa_condominio", "iptu", "mobilia", "descricao",
    "caracteristicas", "origem", "bloqueado", "motivo_bloqueio", "travado",
    "travado_motivo", "travado_em", "extras", "captado_por", "captado_em",
    "administrado",
]


def sql_str(valor):
    if valor is None:
        return "NULL"
    return "'" + str(valor).replace("'", "''") + "'"


def sql_num(valor):
    return "NULL" if valor is None else str(valor)


def sql_bool(valor):
    return "TRUE" if valor else "FALSE"


def gerar():
    site = carregar_site(CATALOGO)
    banco = carregar_banco(BANCO_CSV)

    codigos_site = set(site)
    codigos_banco = set(banco)
    em_ambos = sorted(codigos_site & codigos_banco, key=int)
    so_no_site = sorted(codigos_site - codigos_banco, key=int)
    so_no_banco = sorted(codigos_banco - codigos_site, key=int)

    linhas = []
    linhas.append("-- Gerado por gerar_sql_atualizacao.py (Prompt 5)")
    linhas.append(f"-- Fonte site: {CATALOGO} | Fonte banco: {BANCO_CSV}")
    linhas.append(f"-- em_ambos={len(em_ambos)} so_no_site={len(so_no_site)} so_no_banco={len(so_no_banco)}")
    linhas.append("-- Nenhum DELETE. Não roda sozinho -- revisar e aplicar manualmente.")
    linhas.append("-- Ressalva: 'area' do site é gravada em area_util; area_total não vem do site.")
    linhas.append("")

    # 1) coluna nova
    linhas.append("-- 1) coluna precisa_confirmacao")
    linhas.append(
        "ALTER TABLE imoveis ADD COLUMN IF NOT EXISTS "
        "precisa_confirmacao boolean NOT NULL DEFAULT false;"
    )
    linhas.append("")

    # 2) UPDATE nos que existem nos dois lados
    linhas.append(f"-- 2) UPDATE nos {len(em_ambos)} códigos que existem no site e no banco")
    for codigo in em_ambos:
        s = site[codigo]
        linhas.append(
            "UPDATE imoveis SET "
            f"condominio_nome = {sql_str(s['condominio'])}, "
            f"bairro = {sql_str(s['bairro'])}, "
            f"valor_venda = {sql_num(s['valor_venda'])}, "
            f"valor_aluguel = {sql_num(s['valor_aluguel'])}, "
            f"e_parceiro = {sql_bool(s['e_parceiro'])}, "
            "sincronizado_em = now() "
            f"WHERE codigo = {sql_str(codigo)};"
        )
    linhas.append("")

    # 3) INSERT nos novos
    linhas.append(f"-- 3) INSERT nos {len(so_no_site)} códigos só no site (novos desde 10/08)")
    for codigo in so_no_site:
        s = site[codigo]
        valores = {
            "codigo": sql_str(codigo),
            "condominio_nome": sql_str(s["condominio"]),
            "logradouro": sql_str(s["endereco"]),
            "bairro": sql_str(s["bairro"]),
            "complemento": sql_str(s["complemento"]),
            "area_util": sql_num(s["area"]),
            "quartos": sql_num(s["quartos"]),
            "suites": sql_num(s["suites"]),
            "banheiros": sql_num(s["banheiros"]),
            "vagas": sql_num(s["vagas"]),
            "valor_venda": sql_num(s["valor_venda"]),
            "valor_aluguel": sql_num(s["valor_aluguel"]),
            "e_parceiro": sql_bool(s["e_parceiro"]),
            "publicado_no_site": "TRUE",
        }
        colunas = COLUNAS_INSERT + ["sincronizado_em", "criado_em"]
        valores_sql = [valores[c] for c in COLUNAS_INSERT] + ["now()", "now()"]
        linhas.append(
            f"INSERT INTO imoveis ({', '.join(colunas)}) "
            f"VALUES ({', '.join(valores_sql)});"
        )
    linhas.append("")

    # 4) marca precisa_confirmacao e publicado_no_site=false nos só-no-banco,
    # sem tocar disponivel (mesmo fato: sem anúncio hoje, não indisponível)
    linhas.append(
        f"-- 4) marca precisa_confirmacao=true e publicado_no_site=false nos "
        f"{len(so_no_banco)} só no banco (NÃO mexe em disponivel)"
    )
    lista_codigos = ", ".join(sql_str(c) for c in so_no_banco)
    linhas.append(
        "UPDATE imoveis SET precisa_confirmacao = true, publicado_no_site = false, "
        "sincronizado_em = now() "
        f"WHERE codigo IN ({lista_codigos});"
    )
    linhas.append("")

    linhas.append("-- 5) verificação: administrado que virou parceiro na varredura")
    linhas.append("-- Se o CHECK do banco estiver ativo, o UPDATE já falhou antes.")
    linhas.append("-- Este SELECT é a rede de segurança para quando o CHECK não existir.")
    linhas.append(
        "SELECT codigo, condominio_nome FROM imoveis "
        "WHERE e_parceiro AND administrado;"
    )
    linhas.append("")

    with open(SAIDA, "w", encoding="utf-8") as f:
        f.write("\n".join(linhas) + "\n")

    total_comandos = 1 + len(em_ambos) + len(so_no_site) + 1
    print(f"Gravado em {SAIDA}")
    print(f"em_ambos (UPDATE): {len(em_ambos)}")
    print(f"so_no_site (INSERT): {len(so_no_site)}")
    print(f"so_no_banco (UPDATE precisa_confirmacao): {len(so_no_banco)}")
    print(f"total de comandos SQL: {total_comandos}")
    print()
    print("Colunas de imoveis SEM dado do site nos INSERT (ficam de fora):")
    print("  " + ", ".join(COLUNAS_SEM_DADO_DO_SITE))


if __name__ == "__main__":
    gerar()
