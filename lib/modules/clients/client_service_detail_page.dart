import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import '../../core/theme/app_colors.dart';
import '../schedule/booking_page.dart'; 

class ClientServiceDetailPage extends StatefulWidget {
  final Map<String, dynamic> serviceData;
  final String serviceId;

  const ClientServiceDetailPage({
    super.key, 
    required this.serviceData, 
    required this.serviceId
  });

  @override
  State<ClientServiceDetailPage> createState() => _ClientServiceDetailPageState();
}

class _ClientServiceDetailPageState extends State<ClientServiceDetailPage> {
  int _currentImageIndex = 0;
  late final PageController _pageController;
  Map<String, dynamic>? _selectedVariation;
  bool _isNavigating = false; 

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentImageIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _goToBooking() async {
    // Validação de variação
    final variations = widget.serviceData['variations'] as List?;
    if (variations != null && variations.isNotEmpty && _selectedVariation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Por favor, escolha uma opção (Variação) acima."), 
          backgroundColor: Colors.orange
        ),
      );
      return;
    }

    setState(() => _isNavigating = true);

    try {
      DocumentSnapshot shopDoc;
      
      // Busca dados da loja para passar para o Booking
      if (widget.serviceData['shopId'] != null) {
        shopDoc = await FirebaseFirestore.instance
            .collection('shops')
            .doc(widget.serviceData['shopId'])
            .get();
            
        if (!shopDoc.exists) throw "Loja não encontrada.";
      } else {
        throw "ID da loja não encontrado.";
      }

      if (!mounted) return;

      // Navega para o BookingPage OBRIGANDO a passar o serviço
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BookingPage(
            shop: shopDoc,
            serviceId: widget.serviceId,       // OBRIGATÓRIO
            serviceData: widget.serviceData,   // OBRIGATÓRIO
            selectedVariation: _selectedVariation,
          ),
        ),
      );

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Erro: $e"), 
          backgroundColor: Colors.red
        ),
      );
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List photos = widget.serviceData['fotos_urls'] ?? [];
    final bool hasPhotos = photos.isNotEmpty;
    final variations = widget.serviceData['variations'] as List?;
    final bool hasVariations = variations != null && variations.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // AppBar expansível com imagem do serviço
              SliverAppBar(
                expandedHeight: 400,
                pinned: true,
                backgroundColor: AppColors.primaryPurple,
                leading: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      hasPhotos
                        ? PageView.builder(
                            controller: _pageController,
                            onPageChanged: (index) {
                              setState(() => _currentImageIndex = index);
                            },
                            itemCount: photos.length,
                            itemBuilder: (context, index) {
                              final img = photos[index];
                              return CachedNetworkImage(
                                imageUrl: img,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  color: Colors.grey[200],
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      color: AppColors.primaryPurple,
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: Colors.grey[300],
                                  child: const Icon(Icons.broken_image, size: 80),
                                ),
                              );
                            },
                          )
                        : Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.primaryPurple,
                                  AppColors.primaryPurple.withValues(alpha: 0.7),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Icon(
                              Icons.spa,
                              size: 120,
                              color: Colors.white,
                            ),
                          ),
                      
                      // Indicador de páginas (se houver múltiplas fotos)
                      if (hasPhotos && photos.length > 1)
                        Positioned(
                          bottom: 16,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              photos.length,
                              (index) => Container(
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _currentImageIndex == index
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.4),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              
              // Conteúdo do serviço
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Nome do serviço
                      Text(
                        widget.serviceData['nome'] ?? "Serviço",
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Preço e duração
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "R\$ ${widget.serviceData['preco']}",
                              style: TextStyle(
                                fontSize: 22,
                                color: Colors.green[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryPurple.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.access_time,
                                  size: 18,
                                  color: AppColors.primaryPurple,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  "${widget.serviceData['tempo_min'] ?? '30'} min",
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppColors.primaryPurple,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      // Descrição
                      if (widget.serviceData['descricao'] != null &&
                          widget.serviceData['descricao'].toString().isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Text(
                          "Descrição",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.serviceData['descricao'],
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey[700],
                            height: 1.5,
                          ),
                        ),
                      ],
                      
                      // Variações
                      if (hasVariations) ...[
                        const SizedBox(height: 24),
                        const Text(
                          "Escolha uma opção",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: variations.map<Widget>((v) {
                            final isSelected = _selectedVariation == v;
                            return ChoiceChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "${v['name']}",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: isSelected 
                                          ? Colors.white 
                                          : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "R\$ ${v['price']}",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isSelected 
                                          ? Colors.white 
                                          : Colors.green[700],
                                    ),
                                  ),
                                ],
                              ),
                              selected: isSelected,
                              selectedColor: AppColors.primaryPurple,
                              backgroundColor: Colors.white,
                              side: BorderSide(
                                color: isSelected 
                                    ? AppColors.primaryPurple 
                                    : Colors.grey.shade300,
                                width: isSelected ? 2 : 1,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              onSelected: (val) => setState(() {
                                _selectedVariation = val ? v : null;
                              }),
                            );
                          }).toList(),
                        ),
                      ],
                      
                      const SizedBox(height: 100), // Espaço para o botão fixo
                    ],
                  ),
                ),
              ),
            ],
          ),
          
          // Botão de agendamento fixo na parte inferior
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isNavigating ? null : _goToBooking,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      disabledBackgroundColor: Colors.grey[300],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isNavigating 
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          "AGENDAR ESSE SERVIÇO",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}