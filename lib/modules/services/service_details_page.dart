import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_colors.dart';

class ServiceDetailsPage extends StatelessWidget {
  final DocumentSnapshot doc;
  final VoidCallback onClose;
  final VoidCallback onEdit;

  const ServiceDetailsPage({
    super.key,
    required this.doc,
    required this.onClose,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    List<dynamic> fotos = data['fotos_urls'] ?? [];

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          color: Colors.white,
          height: constraints.maxHeight, // Garante altura total do pai
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- 1. HEADER FIXO ---
              Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                    border:
                        Border(bottom: BorderSide(color: Colors.grey[200]!))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Detalhes",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        IconButton(
                            icon: const Icon(Icons.edit,
                                color: AppColors.primaryPurple),
                            onPressed: onEdit,
                            tooltip: "Editar"),
                        const SizedBox(width: 4),
                        // Ãcone X ou Seta dependendo de onde estiver, mas X é universal
                        IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: onClose,
                            tooltip: "Fechar"),
                      ],
                    ),
                  ],
                ),
              ),

              // --- CONTEÚDO ROLÃVEL (Lista + Infos) ---
              // Usamos Expanded aqui para que o Scroll ocupe o restão da tela
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // GALERIA (Agora rola junto para não ocupar espaço fixo em tela pequena)
                      if (fotos.isNotEmpty)
                        SizedBox(
                          height: 250,
                          width: double.infinity,
                          child: PageView.builder(
                            itemCount: fotos.length,
                            itemBuilder: (context, i) => Stack(
                              fit: StackFit.expand,
                              children: [
                                CachedNetworkImage(
                                  imageUrl: fotos[i],
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) =>
                                      Container(color: Colors.grey[100]),
                                  errorWidget: (context, url, error) =>
                                      const Icon(Icons.error),
                                ),
                                Positioned(
                                  bottom: 10,
                                  right: 10,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                        color:
                                            Colors.black.withValues(alpha: 0.5),
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    child: Text("${i + 1}/${fotos.length}",
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 10)),
                                  ),
                                )
                              ],
                            ),
                          ),
                        ),

                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // NOME E STATUS
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(data['nome'] ?? "",
                                          style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          _buildBadge(
                                              data['categoria'] ?? "Serviço",
                                              AppColors.primaryPurple),
                                          const SizedBox(width: 8),
                                          if (data['ativo'] == false)
                                            _buildBadge("INATIVO", Colors.red),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),

                            // CARDS
                            Row(
                              children: [
                                Expanded(
                                    child: _buildInfoCard(
                                        Icons.timer_outlined,
                                        "Duração",
                                        "${data['tempo_min']} min")),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: _buildInfoCard(Icons.attach_money,
                                        "Valor", "R\$ ${data['preco']}")),
                              ],
                            ),

                            const SizedBox(height: 24),
                            const Divider(),
                            const SizedBox(height: 16),

                            // DESCRIÇÃO
                            const Text("Descrição",
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey)),
                            const SizedBox(height: 8),
                            Text(
                              data['descricao']?.toString().isNotEmpty == true
                                  ? data['descricao']
                                  : "Nenhuma descrição informada.",
                              style: const TextStyle(
                                  fontSize: 15,
                                  height: 1.5,
                                  color: Colors.black87),
                            ),

                            // Espaço extra no final para scroll não cortar
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6)),
      child: Text(text,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }

  Widget _buildInfoCard(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 18, color: Colors.black87),
          ),
          const SizedBox(width: 12),
          Expanded(
            // Adicionado para evitar overflow de texto
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
