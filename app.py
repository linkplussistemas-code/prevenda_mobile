import os
import json
import re
from functools import lru_cache
from flask import Flask, jsonify, request, send_from_directory
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

JSON_PATH = r"Z:\linkplus64\web\produtos.json"
CLIENTES_JSON_PATH = r"Z:\linkplus64\web\clientes.json"
PASTA_WEB = r"Z:\linkplus64\web"
PASTA_TERMINAL = r"Z:\linkplus64\terminal"
PASTA_ATUALIZACAO_PRECOS = r"Z:\LINKPLUS64\TERMINAL\ATUALIZACAOPRECOS"
IMAGENS_DIR = r"Z:\LINKPLUS64\IMAGENS"
ARQUIVO_CELULARES = os.path.join(PASTA_WEB, "CELULAR.TXT")

@app.before_request
def log_request_info():
    print(f"\n[REQUISIÇÃO]: {request.method} {request.path}")

def validar_celular_autorizado(celular, permissao_necessaria=None):
    """
    Valida se o celular está cadastrado e se possui a permissão requerida.
    Formato no arquivo celular.txt: NUMERO|PERMISSAO
    Exemplo: 11999998888|1 (1 = Completo, 0 = Incompleto/Restrito)
    Se o arquivo contiver apenas o número (sem '|'), assume permissão '1' por padrão.
    """
    if not celular:
        return False
    if not os.path.exists(ARQUIVO_CELULARES):
        os.makedirs(PASTA_WEB, exist_ok=True)
        with open(ARQUIVO_CELULARES, "w", encoding="utf-8") as f:
            f.write("")
        return False
    try:
        celular_limpo = str(celular).strip()
        with open(ARQUIVO_CELULARES, "r", encoding="utf-8") as f:
            for linha in f:
                linha_str = linha.strip()
                if not linha_str:
                    continue
                
                if "|" in linha_str:
                    partes = linha_str.split("|", 1)
                    num_cadastrado = partes[0].strip()
                    permissao_cadastrada = partes[1].strip()
                else:
                    num_cadastrado = linha_str
                    permissao_cadastrada = "1"
                
                if num_cadastrado == celular_limpo:
                    if permissao_necessaria is not None:
                        return permissao_cadastrada == str(permissao_necessaria)
                    return True
    except Exception as e:
        print(f"[ERRO AO VALIDAR CELULAR]: {str(e)}")
    return False

def sanitizar_e_carregar_json(json_str):
    json_limpo = re.sub(r'\\(?!["\\/bfnrt]|u[0-9a-fA-F]{4})', r"\\\\", json_str)
    return json.loads(json_limpo, strict=False)

def ler_arquivo_com_encoding_seguro(caminho):
    try:
        with open(caminho, "r", encoding="utf-8") as f:
            return f.read()
    except UnicodeDecodeError:
        with open(caminho, "r", encoding="latin-1") as f:
            return f.read()

@app.route("/produtos", methods=["GET"])
def produtos():
    celular = request.headers.get("X-Celular") or request.args.get("celular")
    if os.path.exists(ARQUIVO_CELULARES):
        with open(ARQUIVO_CELULARES, "r", encoding="utf-8") as f:
            tem_cadastros = any(linha.strip() for linha in f)
        if tem_cadastros and not validar_celular_autorizado(celular):
            return jsonify({"erro": "Acesso não autorizado."}), 403
    try:
        conteudo = ler_arquivo_com_encoding_seguro(JSON_PATH)
        dados = sanitizar_e_carregar_json(conteudo)
        return jsonify(dados), 200
    except Exception as e:
        return jsonify({"erro": str(e)}), 500

@app.route("/clientes", methods=["GET"])
def clientes():
    celular = request.headers.get("X-Celular") or request.args.get("celular")
    if os.path.exists(ARQUIVO_CELULARES):
        with open(ARQUIVO_CELULARES, "r", encoding="utf-8") as f:
            tem_cadastros = any(linha.strip() for linha in f)
        if tem_cadastros and not validar_celular_autorizado(celular):
            return jsonify({"erro": "Acesso não autorizado."}), 403
    try:
        if not os.path.exists(CLIENTES_JSON_PATH):
            return jsonify({"erro": "Ficheiro clientes.json não encontrado."}), 404
        conteudo = ler_arquivo_com_encoding_seguro(CLIENTES_JSON_PATH)
        dados = sanitizar_e_carregar_json(conteudo)
        return jsonify(dados), 200
    except Exception as e:
        return jsonify({"erro": str(e)}), 500

@app.route("/listar-comandas", methods=["GET"])
def listar_comandas():
    celular_requisicao = str(request.headers.get("X-Celular") or request.args.get("celular") or "").strip()
    if os.path.exists(ARQUIVO_CELULARES):
        with open(ARQUIVO_CELULARES, "r", encoding="utf-8") as f:
            tem_cadastros = any(linha.strip() for linha in f)
        if tem_cadastros and not validar_celular_autorizado(celular_requisicao):
            return jsonify({"erro": "Acesso negado."}), 403
    try:
        if not os.path.exists(PASTA_TERMINAL):
            return jsonify({"comandas": []}), 200
        comandas_encontradas = []
        for arquivo in os.listdir(PASTA_TERMINAL):
            if arquivo.lower().endswith(".txt"):
                caminho_arquivo = os.path.join(PASTA_TERMINAL, arquivo)
                num_comanda = os.path.splitext(arquivo)[0]
                itens_comanda = []
                celular_no_arquivo = ""
                try:
                    with open(caminho_arquivo, "r", encoding="utf-8", errors="ignore") as f:
                        linhas = f.readlines()
                        for i, linha in enumerate(linhas):
                            linha_limpa = linha.strip()
                            if i == 0 and "Celular:" in linha_limpa:
                                try:
                                    partes_cel = linha_limpa.split("Celular:")
                                    if len(partes_cel) > 1:
                                        celular_no_arquivo = partes_cel[1].split(")")[0].strip()
                                except:
                                    pass
                            if linha_limpa.startswith("---") or not linha_limpa:
                                continue
                            partes = linha_limpa.split("|")
                            if len(partes) >= 5:
                                itens_comanda.append({
                                    "codigo": partes[0],
                                    "barras": partes[1],
                                    "desc": partes[2],
                                    "qtd": float(partes[3].replace(',', '.')) if partes[3] else 1.0,
                                    "preco": float(partes[4].replace(',', '.')) if partes[4] else 0.0,
                                    "chave": partes[5] if len(partes) > 5 else "",
                                    "ncm": partes[6] if len(partes) > 6 else "",
                                    "cfop": partes[7] if len(partes) > 7 else "",
                                    "st": partes[8] if len(partes) > 8 else "",
                                    "cest": partes[9] if len(partes) > 9 else "",
                                    "total": float(partes[3].replace(',', '.')) * float(partes[4].replace(',', '.')) if partes[3] and partes[4] else 0.0
                                })
                except Exception as ex:
                    print(f"[AVISO] Erro ao ler comanda {arquivo}: {ex}")
                if not celular_requisicao or not celular_no_arquivo or celular_no_arquivo == celular_requisicao:
                    comandas_encontradas.append({"comanda": num_comanda, "itens": itens_comanda})
        return jsonify({"comandas": comandas_encontradas}), 200
    except Exception as e:
        return jsonify({"erro": str(e)}), 500

@app.route("/salvar-comanda", methods=["POST", "GET"])
@app.route("/fechar-comanda", methods=["POST", "GET"])
def salvar_comanda():
    try:
        dados = request.get_json(silent=True) or request.args.to_dict() or {}
        celular = dados.get("celular") or request.headers.get("X-Celular")
        if os.path.exists(ARQUIVO_CELULARES):
            with open(ARQUIVO_CELULARES, "r", encoding="utf-8") as f:
                tem_cadastros = any(linha.strip() for linha in f)
            if tem_cadastros and not validar_celular_autorizado(celular):
                return jsonify({"erro": "Acesso negado."}), 403
        comanda_num = dados.get("comanda") or dados.get("numeroComanda") or "001"
        cnpj = dados.get("cnpj") or ""
        itens = dados.get("itens") or dados.get("produtos") or []
        os.makedirs(PASTA_TERMINAL, exist_ok=True)
        caminho_arquivo = os.path.join(PASTA_TERMINAL, f"{comanda_num}.txt")
        with open(caminho_arquivo, "w", encoding="utf-8") as f:
            f.write(f"--- COMANDA {comanda_num} | CNPJ: {cnpj} (Celular: {celular}) ---\n")
            if isinstance(itens, list):
                for item in itens:
                    if isinstance(item, dict):
                        codigo = item.get("codigo") or item.get("cod") or item.get("id") or ""
                        barras = item.get("barras") or ""
                        descricao = item.get("descricao") or item.get("desc") or item.get("nome") or ""
                        quantidade = item.get("qtd") or item.get("quantidade") or 1
                        preco = item.get("preco") or item.get("valor") or 0.0
                        chave = item.get("chave") or ""
                        ncm = item.get("ncm") or ""
                        cfop = item.get("cfop") or ""
                        st = item.get("st") or ""
                        cest = item.get("cest") or ""
                        f.write(f"{codigo}|{barras}|{descricao}|{quantidade}|{preco}|{chave}|{ncm}|{cfop}|{st}|{cest}\n")
                    else:
                        f.write(f"{item}\n")
        return jsonify({"sucesso": True, "mensagem": f"Comanda {comanda_num} salva."}), 200
    except Exception as e:
        return jsonify({"erro": str(e)}), 500

@app.route("/gerar-precos", methods=["POST", "GET"])
def gerar_precos():
    try:
        celular = request.headers.get("X-Celular") or request.args.get("celular")
        if os.path.exists(ARQUIVO_CELULARES):
            with open(ARQUIVO_CELULARES, "r", encoding="utf-8") as f:
                tem_cadastros = any(linha.strip() for linha in f)
            # Requer permissão 1 (Completo)
            if tem_cadastros and not validar_celular_autorizado(celular, permissao_necessaria="1"):
                return jsonify({"erro": "Acesso negado. Permissão insuficiente para gerar preços."}), 403
                
        conteudo = ler_arquivo_com_encoding_seguro(JSON_PATH)
        dados = sanitizar_e_carregar_json(conteudo)
        lista_produtos = dados['produtos'] if isinstance(dados, dict) and 'produtos' in dados else dados
        os.makedirs(PASTA_ATUALIZACAO_PRECOS, exist_ok=True)
        with open(os.path.join(PASTA_ATUALIZACAO_PRECOS, "PRECOS.TXT"), "w", encoding="utf-8") as f:
            for p in lista_produtos:
                if isinstance(p, dict):
                    codigo = p.get("codigo") or p.get("cod") or p.get("id") or ""
                    chave = p.get("chave") or ""
                    preco = p.get("preco") or p.get("valor") or "0.00"
                    f.write(f"{codigo}|{chave}|{preco}\n")
        return jsonify({"sucesso": True}), 200
    except Exception as e:
        return jsonify({"erro": str(e)}), 500

@app.route("/api/atualizar-preco", methods=["POST"])
def atualizar_preco():
    try:
        celular = request.headers.get("X-Celular") or request.args.get("celular")
        if os.path.exists(ARQUIVO_CELULARES):
            with open(ARQUIVO_CELULARES, "r", encoding="utf-8") as f:
                tem_cadastros = any(linha.strip() for linha in f)
            # Requer permissão 1 (Completo)
            if tem_cadastros and not validar_celular_autorizado(celular, permissao_necessaria="1"):
                return jsonify({"detail": "Acesso negado. Permissão insuficiente para alteração de preço."}), 403

        dados = request.get_json(silent=True) or {}
        codigo = str(dados.get("codigo", "")).strip()
        preco = dados.get("preco")
        if not codigo or preco is None:
            return jsonify({"detail": "Dados incompletos."}), 400
        os.makedirs(PASTA_ATUALIZACAO_PRECOS, exist_ok=True)
        with open(os.path.join(PASTA_ATUALIZACAO_PRECOS, "ALTERACAO_PONTUAL.TXT"), "a", encoding="utf-8") as f:
            f.write(f"{codigo}|{preco}\n")
        return jsonify({"sucesso": True}), 200
    except Exception as e:
        return jsonify({"detail": str(e)}), 500

@lru_cache(maxsize=200)
def _obter_caminho_imagem_cached(filename):
    if not os.path.exists(IMAGENS_DIR):
        return None
    caminho_completo = os.path.join(IMAGENS_DIR, filename)
    if os.path.exists(caminho_completo):
        return caminho_completo
    nome_base, _ = os.path.splitext(filename)
    for ext in [".jpeg", ".jpg", ".png", ".JPG", ".JPEG", ".PNG", ".BMP", ".bmp", ".webp", ".WEBP"]:
        arquivo_teste = os.path.join(IMAGENS_DIR, f"{nome_base}{ext}")
        if os.path.exists(arquivo_teste):
            return arquivo_teste
    return None

@app.route("/imagens/<path:filename>", methods=["GET"])
def servir_imagem(filename):
    try:
        caminho_arquivo = _obter_caminho_imagem_cached(filename)
        if caminho_arquivo and os.path.exists(caminho_arquivo):
            diretorio, nome_ficheiro = os.path.split(caminho_arquivo)
            return send_from_directory(diretorio, nome_ficheiro)
        return jsonify({"erro": "Não encontrada."}), 404
    except Exception as e:
        return jsonify({"erro": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=True)