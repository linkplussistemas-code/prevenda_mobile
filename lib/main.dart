import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  runApp(const LinuxTerminalApp());
}

class LinuxTerminalApp extends StatelessWidget {
  const LinuxTerminalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LinkPlusAppMobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const TerminalScreen(),
    );
  }
}

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class CnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String text = newValue.text.replaceAll(RegIndex.notDigits, '');
    if (text.length > 14) text = text.substring(0, 14);

    String formatted = '';
    if (text.isNotEmpty) {
      if (text.length <= 2) {
        formatted = text;
      } else if (text.length <= 5) {
        formatted = '${text.substring(0, 2)}.${text.substring(2)}';
      } else if (text.length <= 8) {
        formatted = '${text.substring(0, 2)}.${text.substring(2, 5)}.${text.substring(5)}';
      } else if (text.length <= 12) {
        formatted = '${text.substring(0, 2)}.${text.substring(2, 5)}.${text.substring(5, 8)}/${text.substring(8)}';
      } else {
        formatted = '${text.substring(0, 2)}.${text.substring(2, 5)}.${text.substring(5, 8)}/${text.substring(8, 12)}-${text.substring(12)}';
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class RegIndex {
  static final RegExp notDigits = RegExp(r'\D');
}

extension ListExtension<E> on List<E> {
  int indexMatchOr(int defaultValue, bool Function(E) test) {
    for (int i = 0; i < length; i++) {
      if (test(this[i])) return i;
    }
    return defaultValue;
  }
}

class _TerminalScreenState extends State<TerminalScreen> {
  final TextEditingController _buscaController = TextEditingController();
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _celularController = TextEditingController();
  final FocusNode _buscaFocusNode = FocusNode();

  List<dynamic> _todosProdutos = [];
  List<dynamic> _produtosFiltrados = [];
  List<dynamic> _todosClientes = [];
  List _comanda = [];
  bool _mostrarComanda = false;
  String? _numeroComandaAtual;
  
  String _baseUrl = "https://pulsate-cure-spotlight.ngrok-free.dev";
  String _meuCelularId = "123456";
  bool _carregando = false;
  String _mensagemErro = "";
  bool _modoOfflineAtivo = false;

  final Map<String, Uint8List?> _cacheImagensMemoria = {};

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoesIniciais();
  }

  Future<void> _carregarConfiguracoesIniciais() async {
    final prefs = await SharedPreferences.getInstance();
    final urlSalva = prefs.getString('servidor_ip') ?? "pulsate-cure-spotlight.ngrok-free.dev";

    String? celularSalvo = prefs.getString('meu_celular_id');
    if (celularSalvo == null || celularSalvo.isEmpty) {
      celularSalvo = (100000 + Random().nextInt(900000)).toString();
      await prefs.setString('meu_celular_id', celularSalvo);
    }

    setState(() {
      _ipController.text = urlSalva;
      _celularController.text = celularSalvo!;
      _meuCelularId = celularSalvo;
      _atualizarBaseUrl(urlSalva);
    });

    await _carregarDadosGerais();
  }

  void _atualizarBaseUrl(String inputIp) {
    String limpo = inputIp.trim();
    if (limpo.endsWith('/')) {
      limpo = limpo.substring(0, limpo.length - 1);
    }

    if (!limpo.startsWith("http://") && !limpo.startsWith("https://")) {
      if (limpo.contains("ngrok")) {
        limpo = "https://$limpo";
      } else {
        limpo = "http://$limpo";
      }
    }
    _baseUrl = limpo;
  }

  Future<void> _salvarConfiguracoes(String novoEnd, String novoCelular) async {
    final prefs = await SharedPreferences.getInstance();
    String celularFinal = novoCelular.trim();
    if (celularFinal.isEmpty) {
      celularFinal = _meuCelularId;
    }

    await prefs.setString('servidor_ip', novoEnd.trim());
    await prefs.setString('meu_celular_id', celularFinal);

    setState(() {
      _atualizarBaseUrl(novoEnd);
      _meuCelularId = celularFinal;
      _celularController.text = celularFinal;
      _cacheImagensMemoria.clear();
    });

    _exibirMensagem("Configurações salvas com sucesso!");
    _carregarDadosGerais();
  }

  Future<File> _getArquivoLocal(String nomeArquivo) async {
    final diretorio = await getApplicationDocumentsDirectory();
    return File('${diretorio.path}/$nomeArquivo');
  }

  Future<void> _carregarDadosGerais() async {
    setState(() {
      _carregando = true;
      _mensagemErro = "";
    });

    await _carregarProdutos();
    await _carregarClientes();

    setState(() {
      _carregando = false;
    });
  }

  Future<void> _carregarProdutos() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/produtos?celular=$_meuCelularId'),
        headers: {
          'Content-Type': 'application/json',
          'X-Celular': _meuCelularId,
          'ngrok-skip-browser-warning': 'true',
        },
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final decodedData = jsonDecode(response.body);
        List<dynamic> listaProdutos = [];
        if (decodedData is Map && decodedData.containsKey('produtos')) {
          listaProdutos = decodedData['produtos'];
        } else if (decodedData is List) {
          listaProdutos = decodedData;
        }

        final arquivoLocal = await _getArquivoLocal('produtos_cache.json');
        await arquivoLocal.writeAsString(jsonEncode(listaProdutos));

        setState(() {
          _todosProdutos = listaProdutos;
          _modoOfflineAtivo = false;
        });
      } else {
        _carregarProdutosOffline();
      }
    } catch (e) {
      _carregarProdutosOffline();
    }
  }

  Future<void> _carregarProdutosOffline() async {
    try {
      final arquivoLocal = await _getArquivoLocal('produtos_cache.json');
      if (await arquivoLocal.exists()) {
        final conteudo = await arquivoLocal.readAsString();
        final decodedData = jsonDecode(conteudo);
        setState(() {
          _todosProdutos = decodedData is List ? decodedData : [];
          _modoOfflineAtivo = true;
          _mensagemErro = "MODO OFFLINE: Usando cache local de produtos.";
        });
      } else {
        setState(() {
          _mensagemErro = "Sem conexão e sem cache de produtos local.";
        });
      }
    } catch (e) {
      setState(() {
        _mensagemErro = "Erro ao carregar produtos offline: $e";
      });
    }
  }

  Future<void> _carregarClientes() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/clientes?celular=$_meuCelularId'),
        headers: {
          'Content-Type': 'application/json',
          'X-Celular': _meuCelularId,
          'ngrok-skip-browser-warning': 'true',
        },
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final decodedData = jsonDecode(response.body);
        List<dynamic> listaClientes = [];
        if (decodedData is Map && decodedData.containsKey('clientes')) {
          listaClientes = decodedData['clientes'];
        } else if (decodedData is List) {
          listaClientes = decodedData;
        }

        final arquivoLocal = await _getArquivoLocal('clientes_cache.json');
        await arquivoLocal.writeAsString(jsonEncode(listaClientes));

        setState(() {
          _todosClientes = listaClientes;
        });
      } else {
        _carregarClientesOffline();
      }
    } catch (e) {
      _carregarClientesOffline();
    }
  }

  Future<void> _carregarClientesOffline() async {
    try {
      final arquivoLocal = await _getArquivoLocal('clientes_cache.json');
      if (await arquivoLocal.exists()) {
        final conteudo = await arquivoLocal.readAsString();
        final decodedData = jsonDecode(conteudo);
        setState(() {
          _todosClientes = decodedData is List ? decodedData : [];
        });
      }
    } catch (_) {}
  }

  Future<Uint8List?> _obterBytesImagem(String codigo) async {
    if (_cacheImagensMemoria.containsKey(codigo)) {
      return _cacheImagensMemoria[codigo];
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/imagens/$codigo.jpeg'),
        headers: {
          'ngrok-skip-browser-warning': 'true',
          'X-Celular': _meuCelularId,
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        _cacheImagensMemoria[codigo] = response.bodyBytes;
        return response.bodyBytes;
      }
    } catch (_) {}

    _cacheImagensMemoria[codigo] = null;
    return null;
  }

  void _abrirScannerCamera() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('LEITOR DE CÓDIGO DE BARRAS', style: TextStyle(color: Color(0xFF00FF66), fontSize: 14, fontFamily: 'monospace')),
            backgroundColor: const Color(0xFF111111),
            iconTheme: const IconThemeData(color: Color(0xFF00FF66)),
          ),
          body: MobileScanner(
            onDetect: (BarcodeCapture capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  final String codigoLido = barcode.rawValue!;
                  Navigator.pop(context);
                  setState(() {
                    _buscaController.text = codigoLido;
                  });
                  _aoSubmeterBusca(codigoLido);
                  break;
                }
              }
            },
          ),
        ),
      ),
    );
  }

  Future<void> _enviarRequisicaoPrecos() async {
    setState(() => _carregando = true);
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/gerar-precos?celular=$_meuCelularId'),
        headers: {
          'Content-Type': 'application/json',
          'X-Celular': _meuCelularId,
          'ngrok-skip-browser-warning': 'true',
        },
      ).timeout(const Duration(seconds: 10));

      setState(() => _carregando = false);

      if (response.statusCode == 200) {
        _exibirMensagem("PRECOS.TXT gerado com sucesso no servidor!");
      } else if (response.statusCode == 403) {
        _exibirMensagem("Acesso Negado: Permissão insuficiente para gerar preços.");
      } else {
        _exibirMensagem("Erro ao gerar arquivo de preços.");
      }
    } catch (e) {
      setState(() => _carregando = false);
      _exibirMensagem("Falha de conexão para gerar preços.");
    }
  }

  Future<void> _enviarPrecoAlteradoModal(String codigoProduto, double novoPreco) async {
    setState(() => _carregando = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/atualizar-preco'),
        headers: {
          'Content-Type': 'application/json',
          'X-Celular': _meuCelularId,
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({
          'codigo': codigoProduto,
          'preco': novoPreco,
        }),
      );

      setState(() => _carregando = false);

      if (response.statusCode == 200) {
        _exibirMensagem("Preço atualizado com sucesso no servidor!");
        _carregarDadosGerais();
      } else {
        final decoded = jsonDecode(response.body);
        _exibirMensagem("Erro: ${decoded['detail'] ?? decoded['erro'] ?? 'Desconhecido'}");
      }
    } catch (e) {
      setState(() => _carregando = false);
      _exibirMensagem("Falha de conexão ao atualizar preço.");
    }
  }

  void _abrirModalAtualizarPreco() {
    showDialog(
      context: context,
      builder: (context) {
        String termoBuscaProd = "";
        dynamic produtoSelecionado;
        final TextEditingController precoController = TextEditingController();

        return StatefulBuilder(
          builder: (context, setStateModal) {
            final produtosFiltradosPreco = _todosProdutos.where((p) {
              final cod = (p['codigo'] ?? p['cod'] ?? '').toString().toLowerCase();
              final desc = (p['descricao'] ?? p['desc'] ?? p['nome'] ?? '').toString().toLowerCase();
              return cod.contains(termoBuscaProd.toLowerCase()) || desc.contains(termoBuscaProd.toLowerCase());
            }).toList();

            return AlertDialog(
              backgroundColor: const Color(0xFF111111),
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: Color(0xFF00FF66)),
                borderRadius: BorderRadius.circular(8),
              ),
              title: const Text("Atualizar Preços Servidor LinkPlus", style: TextStyle(color: Color(0xFF00FF66), fontFamily: 'monospace')),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Digite o Código ou Nome do Produto...',
                        labelStyle: TextStyle(color: Color(0xFF00FF66)),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FF66))),
                      ),
                      onChanged: (val) {
                        setStateModal(() {
                          termoBuscaProd = val;
                          produtoSelecionado = null;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    if (produtoSelecionado == null)
                      Expanded(
                        child: ListView.builder(
                          itemCount: produtosFiltradosPreco.length,
                          itemBuilder: (context, index) {
                            final p = produtosFiltradosPreco[index];
                            final cod = p['codigo'] ?? p['cod'] ?? '';
                            final nome = p['descricao'] ?? p['desc'] ?? p['nome'] ?? '';
                            final precoAtual = p['preco'] ?? p['valor'] ?? '0.00';

                            return ListTile(
                              dense: true,
                              title: Text("$cod - $nome", style: const TextStyle(color: Colors.white, fontSize: 12)),
                              subtitle: Text("Atual: R\$ $precoAtual", style: const TextStyle(color: Colors.white54, fontSize: 10)),
                              onTap: () {
                                setStateModal(() {
                                  produtoSelecionado = p;
                                  precoController.text = precoAtual.toString();
                                });
                              },
                            );
                          },
                        ),
                      )
                    else ...[
                      const SizedBox(height: 20),
                      Text(
                        "Selecionado: ${produtoSelecionado['codigo']} - ${produtoSelecionado['descricao'] ?? produtoSelecionado['desc']}",
                        style: const TextStyle(color: Color(0xFF00FF66), fontSize: 13, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: precoController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: const InputDecoration(
                          labelText: 'Novo Preço (R\$)',
                          labelStyle: TextStyle(color: Color(0xFF00FF66)),
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FF66))),
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextButton(
                        onPressed: () {
                          setStateModal(() {
                            produtoSelecionado = null;
                          });
                        },
                        child: const Text("Escolher outro produto", style: TextStyle(color: Colors.amberAccent)),
                      )
                    ]
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
                ),
                if (produtoSelecionado != null)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF66)),
                    onPressed: () {
                      final codProd = (produtoSelecionado['codigo'] ?? produtoSelecionado['cod']).toString();
                      final novoPreco = double.tryParse(precoController.text.trim().replaceAll(',', '.')) ?? 0.0;

                      Navigator.pop(context);
                      _enviarPrecoAlteradoModal(codProd, novoPreco);
                    },
                    child: const Text('ATUALIZAR', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  )
              ],
            );
          },
        );
      },
    );
  }

  void _aoSubmeterBusca(String texto) {
    final query = texto.trim().toLowerCase();
    if (query.isEmpty) return;

    if (query == 'f') {
      _buscaController.clear();
      if (_comanda.isEmpty) {
        _buscarComandasSalvas();
      } else {
        _solicitarNumeroComandaECnpj();
      }
      return;
    }

    if (query == 'c') {
      setState(() {
        _comanda.clear();
        _produtosFiltrados.clear();
        _buscaController.clear();
        _mostrarComanda = false;
        _numeroComandaAtual = null;
      });
      _exibirMensagem("Comanda zerada com sucesso!");
      return;
    }

    if (query == 'd') {
      if (_comanda.isNotEmpty) {
        setState(() {
          _comanda.removeLast();
          _produtosFiltrados.clear();
          _buscaController.clear();
          if (_comanda.isEmpty) {
            _mostrarComanda = false;
            _numeroComandaAtual = null;
          }
        });
        _exibirMensagem("Último item removido!");
      } else {
        _exibirMensagem("Comanda já está vazia.");
        _buscaController.clear();
      }
      return;
    }

    final produtoExato = _todosProdutos.firstWhere(
      (p) {
        final codigoStr = (p['codigo'] ?? p['cod'] ?? '').toString().trim();
        final barrasStr = (p['barras'] ?? '').toString().trim();
        return (codigoStr.toLowerCase() == query) || (barrasStr.toLowerCase() == query);
      },
      orElse: () => null,
    );

    if (produtoExato != null) {
      _buscaController.clear();
      setState(() => _produtosFiltrados.clear());
      _pedirQuantidade(produtoExato);
    } else {
      _exibirMensagem("Produto não encontrado.");
    }
  }

  void _aoDigitarBusca(String texto) {
    final query = texto.trim().toLowerCase();

    if (query.isEmpty || query == 'f' || query == 'c' || query == 'd') {
      setState(() => _produtosFiltrados.clear());
      return;
    }

    final palavrasBusca = query.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();

    final resultados = _todosProdutos.where((p) {
      final codigoStr = (p['codigo'] ?? p['cod'] ?? '').toString().trim();
      final barrasStr = (p['barras'] ?? '').toString().trim();
      final desc = (p['descricao'] ?? p['desc'] ?? p['nome'] ?? '').toString().toLowerCase();

      final codLower = codigoStr.toLowerCase();
      final barrasLower = barrasStr.toLowerCase();

      if (codLower.contains(query) || barrasLower.contains(query)) {
        return true;
      }

      bool atendeTodasAsPalavras = palavrasBusca.every((palavra) => desc.contains(palavra));
      return atendeTodasAsPalavras;
    }).toList();

    setState(() => _produtosFiltrados = resultados);
  }

  Widget _destacarTextoBusca(String textoCompleto, String termoBusca) {
    if (termoBusca.isEmpty) {
      return Text(textoCompleto, style: const TextStyle(color: Colors.white, fontSize: 13));
    }

    final palavras = termoBusca.trim().toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (palavras.isEmpty) {
      return Text(textoCompleto, style: const TextStyle(color: Colors.white, fontSize: 13));
    }

    List<TextSpan> spans = [];
    String textoLower = textoCompleto.toLowerCase();

    Set<int> indicesDestacados = {};
    for (var palavra in palavras) {
      int idx = textoLower.indexOf(palavra);
      while (idx != -1) {
        for (int i = idx; i < idx + palavra.length; i++) {
          indicesDestacados.add(i);
        }
        idx = textoLower.indexOf(palavra, idx + 1);
      }
    }

    if (indicesDestacados.isEmpty) {
      return Text(textoCompleto, style: const TextStyle(color: Colors.white, fontSize: 13));
    }

    String buffer = '';
    bool? ultimoFoiVerde;

    for (int i = 0; i < textoCompleto.length; i++) {
      bool ehVerde = indicesDestacados.contains(i);
      if (ultimoFoiVerde == null || ultimoFoiVerde == ehVerde) {
        buffer += textoCompleto[i];
        ultimoFoiVerde = ehVerde;
      } else {
        spans.add(TextSpan(
          text: buffer,
          style: TextStyle(
            color: ultimoFoiVerde! ? const Color(0xFF00FF66) : Colors.white,
            fontWeight: ultimoFoiVerde! ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ));
        buffer = textoCompleto[i];
        ultimoFoiVerde = ehVerde;
      }
    }
    if (buffer.isNotEmpty) {
      spans.add(TextSpan(
        text: buffer,
        style: TextStyle(
          color: ultimoFoiVerde! ? const Color(0xFF00FF66) : Colors.white,
          fontWeight: ultimoFoiVerde! ? FontWeight.bold : FontWeight.normal,
          fontSize: 13,
        ),
      ));
    }

    return RichText(text: TextSpan(children: spans));
  }

  void _pedirQuantidade(dynamic produto) {
    final TextEditingController qtdController = TextEditingController(text: "1");
    final codigoProduto = (produto['codigo'] ?? produto['cod'] ?? '').toString().trim();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111111),
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFF00FF66)),
            borderRadius: BorderRadius.circular(8),
          ),
          title: Text(
            produto['descricao'] ?? produto['desc'] ?? 'PRODUTO',
            style: const TextStyle(color: Color(0xFF00FF66), fontSize: 14, fontFamily: 'monospace'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 120,
                width: 120,
                decoration: BoxDecoration(
                  color: Colors.black,
                  border: Border.all(color: const Color(0xFF00FF66)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: FutureBuilder<Uint8List?>(
                    future: _obterBytesImagem(codigoProduto),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.done &&
                          snapshot.hasData &&
                          snapshot.data != null) {
                        return Image.memory(snapshot.data!, fit: BoxFit.cover);
                      }
                      return const Center(
                        child: Icon(Icons.broken_image, color: Colors.white30, size: 40),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Preço: R\$ ${produto['preco'] ?? produto['valor'] ?? '0.00'} (${produto['unidade'] ?? 'UN'})",
                style: const TextStyle(color: Colors.white70, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: qtdController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 18),
                decoration: const InputDecoration(
                  labelText: 'Quantidade',
                  labelStyle: TextStyle(color: Color(0xFF00FF66)),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FF66))),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FF66))),
                ),
                onSubmitted: (_) {
                  final qtd = double.tryParse(qtdController.text.replaceAll(',', '.')) ?? 1.0;
                  _adicionarAComanda(produto, qtd);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF66)),
              onPressed: () {
                final qtd = double.tryParse(qtdController.text.replaceAll(',', '.')) ?? 1.0;
                _adicionarAComanda(produto, qtd);
                Navigator.pop(context);
              },
              child: const Text('INCLUIR', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            )
          ],
        );
      },
    );
  }

  void _adicionarAComanda(dynamic produto, double quantidade) {
    final codigoItem = produto['codigo'] ?? produto['cod'] ?? '';
    final precoVal = produto['preco'] ?? produto['valor'] ?? 0.0;
    final precoNum = precoVal is num ? precoVal.toDouble() : double.tryParse(precoVal.toString()) ?? 0.0;

    setState(() {
      _comanda.add({
        'codigo': codigoItem,
        'barras': produto['barras'] ?? '',
        'desc': produto['descricao'] ?? produto['desc'] ?? '',
        'preco': precoNum,
        'qtd': quantidade,
        'total': precoNum * quantidade,
        'chave': produto['chave'] ?? '',
        'ncm': produto['ncm'] ?? '',
        'cfop': produto['cfop'] ?? '',
        'st': produto['st'] ?? '',
        'cest': produto['cest'] ?? '',
      });
      _produtosFiltrados.clear();
      _buscaController.clear();
      _mostrarComanda = true;
    });
    _exibirMensagem("Item adicionado à comanda!");
  }

  bool _validarCnpj(String cnpj) {
    if (cnpj.isEmpty) return true;
    String numeros = cnpj.replaceAll(RegExp(r'\D'), '');
    if (numeros.length != 14) return false;
    if (RegExp(r'^(\d)\1{13}$').hasMatch(numeros)) return false;

    List<int> digitos = numeros.split('').map(int.parse).toList();
    List<int> multiplicadores1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    int soma = 0;
    for (int i = 0; i < 12; i++) {
      soma += digitos[i] * multiplicadores1[i];
    }
    int resto = soma % 11;
    int dv1 = (resto < 2) ? 0 : (11 - resto);

    if (dv1 != digitos[12]) return false;

    List<int> multiplicadores2 = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    soma = 0;
    for (int i = 0; i < 13; i++) {
      soma += digitos[i] * multiplicadores2[i];
    }
    resto = soma % 11;
    int dv2 = (resto < 2) ? 0 : (11 - resto);

    return dv2 == digitos[13];
  }

  Future<void> _buscarComandasSalvas() async {
    setState(() => _carregando = true);
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/listar-comandas?celular=$_meuCelularId'),
        headers: {
          'Content-Type': 'application/json',
          'X-Celular': _meuCelularId,
          'ngrok-skip-browser-warning': 'true',
        },
      ).timeout(const Duration(seconds: 10));

      setState(() => _carregando = false);

      if (response.statusCode == 200) {
        final decodedData = jsonDecode(response.body);
        List<dynamic> listaComandas = [];
        if (decodedData is Map && decodedData.containsKey('comandas')) {
          listaComandas = decodedData['comandas'];
        } else if (decodedData is List) {
          listaComandas = decodedData;
        }

        if (listaComandas.isEmpty) {
          _exibirMensagem("Nenhuma comanda encontrada para este celular.");
          return;
        }

        _mostrarModalSelecaoComandas(listaComandas);
      } else {
        _exibirMensagem("Erro ao listar comandas salvas.");
      }
    } catch (e) {
      setState(() => _carregando = false);
      _exibirMensagem("Falha ao conectar para buscar comandas.");
    }
  }

  void _mostrarModalSelecaoComandas(List<dynamic> comandas) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111111),
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFF00FF66)),
            borderRadius: BorderRadius.circular(8),
          ),
          title: const Text("SELECIONAR COMANDA", style: TextStyle(color: Color(0xFF00FF66), fontFamily: 'monospace')),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: comandas.length,
              itemBuilder: (context, index) {
                final comanda = comandas[index];
                final numComanda = comanda['comanda']?.toString() ?? 'N/A';
                final qtdItens = comanda['itens'] != null ? (comanda['itens'] as List).length : 0;

                return ListTile(
                  title: Text("Comanda: $numComanda", style: const TextStyle(color: Colors.white, fontFamily: 'monospace')),
                  subtitle: Text("Itens: $qtdItens", style: const TextStyle(color: Colors.white54, fontFamily: 'monospace', fontSize: 11)),
                  trailing: const Icon(Icons.arrow_forward_ios, color: Color(0xFF00FF66), size: 16),
                  onTap: () {
                    Navigator.pop(context);
                    _carregarComandaParaTela(comanda);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
            ),
          ],
        );
      },
    );
  }

  void _carregarComandaParaTela(dynamic comandaData) {
    setState(() {
      _comanda.clear();
      _numeroComandaAtual = comandaData['comanda']?.toString();

      List<dynamic> itensSalvos = comandaData['itens'] ?? [];
      for (var item in itensSalvos) {
        final precoNum = double.tryParse((item['preco'] ?? 0).toString()) ?? 0.0;
        final qtdNum = double.tryParse((item['qtd'] ?? 1).toString()) ?? 1.0;
        _comanda.add({
          'codigo': item['codigo'] ?? '',
          'barras': item['barras'] ?? '',
          'desc': item['desc'] ?? item['descricao'] ?? '',
          'preco': precoNum,
          'qtd': qtdNum,
          'total': precoNum * qtdNum,
          'chave': item['chave'] ?? '',
          'ncm': item['ncm'] ?? '',
          'cfop': item['cfop'] ?? '',
          'st': item['st'] ?? '',
          'cest': item['cest'] ?? '',
        });
      }
      _mostrarComanda = _comanda.isNotEmpty;
    });
    _exibirMensagem("Comanda $_numeroComandaAtual carregada com sucesso!");
  }

  void _solicitarNumeroComandaECnpj() {
    if (_comanda.isEmpty) {
      _exibirMensagem("Nenhum item na comanda para fechar.");
      return;
    }

    final TextEditingController numComandaController = TextEditingController(text: _numeroComandaAtual ?? "");
    final TextEditingController cnpjController = TextEditingController();
    final TextEditingController observacaoController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return AlertDialog(
              backgroundColor: const Color(0xFF111111),
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: Color(0xFF00FF66)),
                borderRadius: BorderRadius.circular(8),
              ),
              title: const Text("GRAVAR / FECHAR COMANDA", style: TextStyle(color: Color(0xFF00FF66), fontFamily: 'monospace')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: numComandaController,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 18),
                      decoration: const InputDecoration(
                        labelText: 'Número da Comanda',
                        labelStyle: TextStyle(color: Color(0xFF00FF66)),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FF66))),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FF66))),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: cnpjController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [CnpjInputFormatter()],
                      style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 18),
                      decoration: InputDecoration(
                        labelText: 'CNPJ do Cliente (Opcional)',
                        hintText: '00.000.000/0000-00',
                        hintStyle: const TextStyle(color: Colors.white24),
                        labelStyle: const TextStyle(color: Color(0xFF00FF66)),
                        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FF66))),
                        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FF66))),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search, color: Color(0xFF00FF66)),
                          tooltip: "Buscar no clientes.json",
                          onPressed: () {
                            _mostrarModalBuscaClientes(cnpjController);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: observacaoController,
                      keyboardType: TextInputType.text,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 16),
                      decoration: const InputDecoration(
                        labelText: 'Observações (Opcional)',
                        hintText: 'Ex: Entregar na mesa 12',
                        hintStyle: TextStyle(color: Colors.white24),
                        labelStyle: TextStyle(color: Color(0xFF00FF66)),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FF66))),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FF66))),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF66)),
                  onPressed: () {
                    final comandaNum = numComandaController.text.trim();
                    final cnpjNum = cnpjController.text.trim();
                    final observacaoText = observacaoController.text.trim();

                    if (comandaNum.isEmpty) {
                      _exibirMensagem("Informe o número da comanda!");
                      return;
                    }
                    if (cnpjNum.isNotEmpty && !_validarCnpj(cnpjNum)) {
                      _exibirMensagem("CNPJ inválido! Verifique os dígitos.");
                      return;
                    }

                    Navigator.of(dialogContext).pop();
                    _enviarEGravarComanda(comandaNum, cnpjNum, observacaoText);
                  },
                  child: const Text('GRAVAR', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                )
              ],
            );
          },
        );
      },
    );
  }

  void _mostrarModalBuscaClientes(TextEditingController cnpjController) {
    if (_todosClientes.isEmpty) {
      _exibirMensagem("Nenhum cliente carregado no clientes.json.");
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        String termoBusca = "";
        return StatefulBuilder(
          builder: (context, setStateModal) {
            final clientesFiltrados = _todosClientes.where((c) {
              final nome = (c['nomecli'] ?? '').toString().toLowerCase();
              final cnpj = (c['cnpj'] ?? '').toString().toLowerCase();
              return nome.contains(termoBusca.toLowerCase()) || cnpj.contains(termoBusca);
            }).toList();

            return AlertDialog(
              backgroundColor: const Color(0xFF111111),
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: Color(0xFF00FF66)),
                borderRadius: BorderRadius.circular(8),
              ),
              title: const Text("SELECIONAR CLIENTE", style: TextStyle(color: Color(0xFF00FF66), fontFamily: 'monospace')),
              content: SizedBox(
                width: double.maxFinite,
                height: 350,
                child: Column(
                  children: [
                    TextField(
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Filtrar por nome ou CNPJ...',
                        hintStyle: TextStyle(color: Colors.white30),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FF66))),
                      ),
                      onChanged: (val) {
                        setStateModal(() {
                          termoBusca = val;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.builder(
                        itemCount: clientesFiltrados.length,
                        itemBuilder: (context, index) {
                          final cli = clientesFiltrados[index];
                          final nomeCli = cli['nomecli'] ?? 'SEM NOME';
                          final cnpjCli = cli['cnpj']?.toString() ?? '';
                          final chaveCli = cli['chavecli']?.toString() ?? '';

                          return ListTile(
                            dense: true,
                            title: Text(nomeCli, style: const TextStyle(color: Colors.white, fontSize: 13)),
                            subtitle: Text("CNPJ: $cnpjCli | Chave: $chaveCli", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                            onTap: () {
                              cnpjController.text = cnpjCli;
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _enviarEGravarComanda(String numeroComanda, String cnpj, String observacao) async {
    final dadosComanda = {
      'celular': _meuCelularId,
      'comanda': numeroComanda,
      'cnpj': cnpj.isEmpty ? "NAO INFORMADO" : cnpj,
      'observacao': observacao.isEmpty ? "" : observacao,
      'itens': _comanda,
    };

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/fechar-comanda'),
        headers: {
          'Content-Type': 'application/json',
          'X-Celular': _meuCelularId,
        },
        body: jsonEncode(dadosComanda),
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        setState(() {
          _comanda.clear();
          _mostrarComanda = false;
          _numeroComandaAtual = null;
        });
        _exibirMensagem("Comanda $numeroComanda gravada com sucesso no servidor!");
      } else {
        await _salvarComandaOfflineEmMassa(dadosComanda, numeroComanda);
      }
    } catch (e) {
      await _salvarComandaOfflineEmMassa(dadosComanda, numeroComanda);
    }
  }

  Future<void> _salvarComandaOfflineEmMassa(Map<String, dynamic> dadosComanda, String numeroComanda) async {
    try {
      final arquivoLocal = await _getArquivoLocal('comandas_pendentes.json');
      List<dynamic> listaPendentes = [];
      if (await arquivoLocal.exists()) {
        final conteudo = await arquivoLocal.readAsString();
        listaPendentes = jsonDecode(conteudo) is List ? jsonDecode(conteudo) : [];
      }
      listaPendentes.add(dadosComanda);
      await arquivoLocal.writeAsString(jsonEncode(listaPendentes));

      setState(() {
        _comanda.clear();
        _mostrarComanda = false;
        _numeroComandaAtual = null;
      });

      _exibirMensagem("OFFLINE: Comanda $numeroComanda salva na fila local para envio em massa!");
    } catch (e) {
      _exibirMensagem("Erro ao salvar comanda offline: $e");
    }
  }

  Future<void> _sincronizarComandasPendentes() async {
    setState(() => _carregando = true);
    try {
      final arquivoLocal = await _getArquivoLocal('comandas_pendentes.json');
      if (!await arquivoLocal.exists()) {
        setState(() => _carregando = false);
        _exibirMensagem("Nenhuma comanda pendente offline.");
        return;
      }

      final conteudo = await arquivoLocal.readAsString();
      List<dynamic> listaPendentes = jsonDecode(conteudo);

      if (listaPendentes.isEmpty) {
        setState(() => _carregando = false);
        _exibirMensagem("Nenhuma comanda pendente offline.");
        return;
      }

      int enviadasComSucesso = 0;
      List<dynamic> aindaPendentes = [];

      for (var comanda in listaPendentes) {
        try {
          final response = await http.post(
            Uri.parse('$_baseUrl/fechar-comanda'),
            headers: {
              'Content-Type': 'application/json',
              'X-Celular': _meuCelularId,
            },
            body: jsonEncode(comanda),
          ).timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            enviadasComSucesso++;
          } else {
            aindaPendentes.add(comanda);
          }
        } catch (_) {
          aindaPendentes.add(comanda);
        }
      }

      await arquivoLocal.writeAsString(jsonEncode(aindaPendentes));
      setState(() => _carregando = false);

      _exibirMensagem("Sincronização em massa: $enviadasComSucesso enviadas para o servidor!");
    } catch (e) {
      setState(() => _carregando = false);
      _exibirMensagem("Erro na sincronização em massa: $e");
    }
  }

  void _exibirMensagem(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: Colors.green, duration: const Duration(seconds: 3)),
    );
  }

  void _abrirModalConfiguracao() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111111),
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFF00FF66)),
            borderRadius: BorderRadius.circular(8),
          ),
          title: const Text("CONFIGURAÇÕES", style: TextStyle(color: Color(0xFF00FF66), fontFamily: 'monospace')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _ipController,
                style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  labelText: 'IP Local ou Ngrok',
                  labelStyle: TextStyle(color: Color(0xFF00FF66)),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FF66))),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FF66))),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _celularController,
                style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  labelText: 'ID / Número deste Celular',
                  labelStyle: TextStyle(color: Color(0xFF00FF66)),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FF66))),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FF66))),
                ),
              ),
              const SizedBox(height: 15),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                icon: const Icon(Icons.cloud_upload, color: Colors.white),
                label: const Text("Sincronizar Comandas Offline (Massa)", style: TextStyle(color: Colors.white)),
                onPressed: () {
                  Navigator.pop(context);
                  _sincronizarComandasPendentes();
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF66)),
              onPressed: () {
                _salvarConfiguracoes(_ipController.text, _celularController.text);
                Navigator.pop(context);
              },
              child: const Text('SALVAR', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            )
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const greenTerminal = Color(0xFF00FF66);
    double totalGeral = _comanda.fold(0.0, (sum, item) => sum + (item['total'] as double));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: Text(
          _numeroComandaAtual != null ? "LinkPlusAppMobile - Comanda: $_numeroComandaAtual" : "LinkPlusAppMobile 1.0",
          style: const TextStyle(fontSize: 12, color: greenTerminal, fontFamily: 'monospace'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload, color: Colors.blueAccent),
            tooltip: "Descarregar Pedidos Offline em Massa",
            onPressed: _sincronizarComandasPendentes,
          ),
          IconButton(
            icon: const Icon(Icons.edit_note, color: greenTerminal),
            tooltip: "Atualizar Preço Individual",
            onPressed: _abrirModalAtualizarPreco,
          ),
          IconButton(
            icon: const Icon(Icons.price_change, color: greenTerminal),
            tooltip: "Gerar PRECOS.TXT Geral",
            onPressed: _enviarRequisicaoPrecos,
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: greenTerminal),
            onPressed: _abrirModalConfiguracao,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: greenTerminal),
            onPressed: _carregarDadosGerais,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF111111),
                border: Border(bottom: BorderSide(color: greenTerminal, width: 1)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: greenTerminal, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _buscaController,
                      focusNode: _buscaFocusNode,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.go,
                      style: const TextStyle(color: greenTerminal, fontFamily: 'monospace', fontSize: 14),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Nome, EAN, Cód ou comandos (f, c, d)',
                        hintStyle: TextStyle(color: Colors.white30, fontSize: 12),
                      ),
                      onChanged: _aoDigitarBusca,
                      onSubmitted: _aoSubmeterBusca,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.camera_alt, color: greenTerminal, size: 24),
                    tooltip: "Ler Código de Barras com a Câmara",
                    onPressed: _abrirScannerCamera,
                  ),
                ],
              ),
            ),

            if (_carregando)
              const Padding(
                padding: EdgeInsets.all(12.0),
                child: CircularProgressIndicator(color: greenTerminal),
              ),

            if (_mensagemErro.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(_mensagemErro, style: TextStyle(color: _modoOfflineAtivo ? Colors.orangeAccent : Colors.redAccent, fontSize: 11, fontFamily: 'monospace')),
              ),

            if (_produtosFiltrados.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                color: const Color(0xFF181818),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _produtosFiltrados.length,
                  itemBuilder: (context, index) {
                    final p = _produtosFiltrados[index];
                    final codigoExibido = (p['codigo'] ?? p['cod'] ?? '').toString().trim();
                    final barrasExibida = (p['barras'] ?? '').toString().trim();
                    final String nomeProduto = (p['descricao'] ?? p['desc'] ?? p['nome'] ?? '').toString();

                    return ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF222222),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: greenTerminal.withOpacity(0.3)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: FutureBuilder<Uint8List?>(
                            future: _obterBytesImagem(codigoExibido),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.done &&
                                  snapshot.hasData &&
                                  snapshot.data != null) {
                                return Image.memory(snapshot.data!, fit: BoxFit.cover);
                              }
                              return const Icon(Icons.image_not_supported, color: Colors.white24, size: 20);
                            },
                          ),
                        ),
                      ),
                      title: _destacarTextoBusca(nomeProduto, _buscaController.text),
                      subtitle: Text(
                        "Cód: $codigoExibido | EAN: $barrasExibida",
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                      trailing: Text(
                        "R\$ ${p['preco'] ?? p['valor'] ?? ''}",
                        style: const TextStyle(color: greenTerminal),
                      ),
                      onTap: () {
                        _pedirQuantidade(p);
                      },
                    );
                  },
                ),
              ),

            if (_mostrarComanda) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                color: const Color(0xFF111111),
                child: const Text(
                  "COD.....DESC...............................QTD.VALOR",
                  style: TextStyle(color: greenTerminal, fontSize: 10, fontFamily: 'monospace'),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _comanda.length,
                  itemBuilder: (context, index) {
                    final item = _comanda[index];
                    final codFormatado = item['codigo'].toString().padLeft(5, '0');

                    return ListTile(
                      dense: true,
                      title: Text(
                        "$codFormatado | ${item['desc']}",
                        style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
                      ),
                      subtitle: Text(
                        "Qtd: ${item['qtd']}",
                        style: const TextStyle(color: Colors.white54, fontFamily: 'monospace', fontSize: 10),
                      ),
                      trailing: Text(
                        "R\$ ${item['total'].toStringAsFixed(2)}",
                        style: const TextStyle(color: greenTerminal, fontFamily: 'monospace', fontSize: 12),
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                color: const Color(0xFF111111),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "TOTAL: R\$ ${totalGeral.toStringAsFixed(2)}",
                      style: const TextStyle(color: greenTerminal, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                    ),
                    Text(
                      "ITENS: ${_comanda.length}",
                      style: const TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ] else
              const Expanded(
                child: Center(
                  child: Text(
                    "Digite para buscar o próximo produto...\n(Ou digite 'f' com a tela vazia para carregar uma comanda)",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white24, fontFamily: 'monospace'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}