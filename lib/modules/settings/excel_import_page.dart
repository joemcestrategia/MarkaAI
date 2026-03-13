import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../core/services/session_service.dart';
import '../../core/theme/app_colors.dart';

class ExcelImportPage extends StatefulWidget {
  const ExcelImportPage({super.key});

  @override
  State<ExcelImportPage> createState() => _ExcelImportPageState();
}

class _ExcelImportPageState extends State<ExcelImportPage> {
  bool _isLoading = false;
  String _logs =
      "Ferramenta de Gestão de Histórico.\n\nUse o botão ROXO para importar.\nUse o botão VERMELHO para limpar erros de importação.";
  double _progress = 0.0;

  // --- HELPERS ---
  String _getCellValue(CellValue? value) {
    if (value == null) return "";
    if (value is TextCellValue) return value.value.toString();
    if (value is DoubleCellValue) return value.value.toString();
    if (value is IntCellValue) return value.value.toString();
    return value.toString();
  }

  double _parseCurrency(CellValue? value) {
    if (value == null) return 0.0;
    try {
      if (value is DoubleCellValue) return value.value;
      if (value is IntCellValue) return value.value.toDouble();
      String text =
          _getCellValue(value).replaceAll('R\$', '').replaceAll(' ', '').trim();
      if (text.isEmpty) return 0.0;
      if (text.contains(',')) {
        text = text.replaceAll('.', '').replaceAll(',', '.');
      }
      return double.tryParse(text) ?? 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  // --- FUNÇÃO DE IMPORTAÇÃO ---
  Future<void> _pickAndUploadFile() async {
    setState(() {
      _isLoading = true;
      _logs = "Lendo arquivo...";
    });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );

      if (result == null) {
        setState(() {
          _isLoading = false;
          _logs += "\nCancelado.";
        });
        return;
      }

      PlatformFile file = result.files.first;
      if (file.bytes == null) throw "Erro de leitura.";

      var excel = Excel.decodeBytes(file.bytes!);
      final shopId = await SessionService.getShopId();
      if (shopId == null) throw "Erro de login.";

      var table = excel.tables[excel.tables.keys.first];
      if (table == null) throw "Planilha vazia.";

      int totalRows = table.maxRows;
      setState(() => _logs += "\nArquivo carregado. $totalRows linhas.");

      CollectionReference appointments =
          FirebaseFirestore.instance.collection('appointments');
      int importedCount = 0;

      for (int i = 1; i < table.rows.length; i++) {
        var row = table.rows[i];
        if (row.length < 7) continue;

        var cellData = row[0]?.value;
        var cellCliente = row[1]?.value;
        var cellServico = row[2]?.value;
        var cellMaoObra = row[3]?.value;
        var cellCusto = row[4]?.value;
        var cellDescProd = row[5]?.value;
        var cellTotal = row[6]?.value;

        if (cellData == null || cellCliente == null) continue;

        DateTime date;
        try {
          if (cellData is DateCellValue) {
            date =
                DateTime(cellData.year, cellData.month, cellData.day, 12, 0, 0);
          } else {
            date = DateFormat('dd/MM/yyyy').parse(_getCellValue(cellData));
          }
        } catch (e) {
          continue;
        }
        date = DateTime(date.year, date.month, date.day, 12, 0, 0);

        double valMaoObra = _parseCurrency(cellMaoObra);
        double valCusto = _parseCurrency(cellCusto);
        double valTotal = _parseCurrency(cellTotal);

        if (valTotal == 0 && (valMaoObra > 0 || valCusto > 0)) {
          valTotal = valMaoObra + valCusto;
        }

        String nomeServico = _getCellValue(cellServico);
        String descProd = _getCellValue(cellDescProd).trim();
        if (descProd.isNotEmpty && descProd.toLowerCase() != "null") {
          nomeServico += " + $descProd";
        }

        await appointments.add({
          'shopId': shopId,
          'client_name': _getCellValue(cellCliente),
          'service_name': nomeServico,
          'valor_mao_de_obra': valMaoObra,
          'valor_produtos': valCusto,
          'valor_total': valTotal,
          'data_agendamento': Timestamp.fromDate(date),
          'status': 'concluido',
          'historico_importado':
              true, // Marca crucial para podermos apagar depois
          'created_at': FieldValue.serverTimestamp(),
        });

        importedCount++;
        if (i % 10 == 0) {
          setState(() {
            _progress = i / table.rows.length;
            _logs += "\nImportado: ${_getCellValue(cellCliente)}";
          });
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }

      setState(() {
        _isLoading = false;
        _progress = 1.0;
        _logs += "\n\n✅ SUCESSO! $importedCount registros importados.";
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _logs += "\nâŒ ERRO: $e";
      });
    }
  }

  // --- ðŸ—‘ï¸ FUNÇÃO DE LIMPEZA (NOVA) ---
  Future<void> _deleteImportedHistory() async {
    // Confirmação de Segurança
    bool confirm = await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Apagar Importações?"),
            content: const Text(
                "Isso excluirá TODOS os registros marcados como 'Histórico Importado' desta loja.\n\nDados lançados manualmente NÃO serão afetados.\n\nTem a certeza?"),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Cancelar")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Apagar Tudo",
                    style: TextStyle(color: Colors.white)),
              )
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    setState(() {
      _isLoading = true;
      _logs = "Iniciando limpeza...";
    });

    try {
      final shopId = await SessionService.getShopId();
      if (shopId == null) throw "Erro de login.";

      // Busca apenas os documentos importados
      var collection = FirebaseFirestore.instance.collection('appointments');
      var snapshot = await collection
          .where('shopId', isEqualTo: shopId)
          .where('historico_importado', isEqualTo: true) // O Segredo está aqui
          .get();

      int total = snapshot.docs.length;
      setState(() => _logs += "\nEncontrados $total registros para exclusão.");

      if (total == 0) {
        setState(() {
          _isLoading = false;
          _logs += "\nNenhum histórico importado encontrado.";
        });
        return;
      }

      // Deleta em Lotes (Batch) para ser rápido
      WriteBatch batch = FirebaseFirestore.instance.batch();
      int count = 0;
      int deletedCount = 0;

      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
        count++;
        deletedCount++;

        // O Firestore limita batches a 500 operações
        if (count >= 400) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          count = 0;
          setState(() => _logs += "\nLimpando lote... ($deletedCount/$total)");
        }
      }

      // Comita o restante
      if (count > 0) await batch.commit();

      setState(() {
        _isLoading = false;
        _logs +=
            "\n\nðŸ—‘ï¸ LIMPEZA CONCLUÍDA!\n$deletedCount registros apagados.";
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text("Histórico importado apagado!")));
    } catch (e) {
      setState(() {
        _isLoading = false;
        _logs += "\nâŒ ERRO AO APAGAR: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gestão de Histórico"),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.grey.shade300)),
              child: Column(
                children: [
                  const Icon(Icons.backup_table,
                      size: 40, color: AppColors.primaryPurple),
                  const SizedBox(height: 10),
                  const Text("Importar / Limpar",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 20),

                  if (_isLoading)
                    LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        color: AppColors.primaryPurple),
                  const SizedBox(height: 20),

                  // BOTÃO DE IMPORTAR
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _pickAndUploadFile,
                      icon: const Icon(Icons.upload_file, color: Colors.white),
                      label: Text(
                          _isLoading ? "PROCESSANDO..." : "CARREGAR PLANILHA"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryPurple,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),

                  const SizedBox(height: 15),

                  // ðŸ—‘ï¸ BOTÃO DE APAGAR (NOVO)
                  SizedBox(
                    width: double.infinity,
                    height: 45,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _deleteImportedHistory,
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                      label: const Text("LIMPAR IMPORTAÇÕES ANTERIORES",
                          style: TextStyle(
                              color: Colors.red, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          backgroundColor: Colors.red.withValues(alpha: 0.05)),
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(10)),
                child: SingleChildScrollView(
                    reverse: true,
                    child: Text(_logs,
                        style: const TextStyle(
                            color: Colors.greenAccent,
                            fontFamily: 'monospace',
                            fontSize: 11))),
              ),
            )
          ],
        ),
      ),
    );
  }
}
