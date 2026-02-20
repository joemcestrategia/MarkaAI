# -*- coding: utf-8 -*-
"""
Rewrites the build() method of StoreProfilePage:
- Logo goes INSIDE the FlexibleSpaceBar cover at bottom-left
- SliverToBoxAdapter has no extra Stack/margin for logo
- Compact, clean layout
"""
import re, sys

PATH = r'c:\src\MarkaAI\lib\modules\business\store_profile_page.dart'

with open(PATH, 'r', encoding='utf-8') as f:
    content = f.read()

BUILD_MARKER_START = '  @override\n  Widget build(BuildContext context) {'
BUILD_MARKER_END   = '\n  // Widget auxiliar para TextFields bonitos'

start = content.find(BUILD_MARKER_START)
end   = content.find(BUILD_MARKER_END)
if start == -1 or end == -1:
    print(f"ERROR: markers not found start={start} end={end}", file=sys.stderr)
    sys.exit(1)

print(f"Replacing build() at {start}..{end}")

NEW_BUILD = r'''  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5FB),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, -4),
              )
            ],
          ),
          child: SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                disabledBackgroundColor: AppColors.primaryPurple.withValues(alpha: 0.6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      "SALVAR ALTERAÇÕES",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryPurple))
          : CustomScrollView(
              slivers: [
                // ─── APP BAR com CAPA e LOGO embutido ────────────────────
                SliverAppBar(
                  expandedHeight: 200.0,
                  pinned: true,
                  backgroundColor: AppColors.primaryPurple,
                  title: Text(
                    _isSaving ? "Salvando..." : "Editar Perfil",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  centerTitle: true,
                  iconTheme: const IconThemeData(color: Colors.white),
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        // ── Imagem da Capa ──────────────────────────────
                        GestureDetector(
                          onTap: () => _pickAndEditImage(isCover: true),
                          child: _newCoverFile != null
                              ? (kIsWeb
                                  ? Image.network(_newCoverFile!.path, fit: BoxFit.cover)
                                  : Image.file(File(_newCoverFile!.path), fit: BoxFit.cover))
                              : (_coverUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: _coverUrl!,
                                      fit: BoxFit.cover,
                                      placeholder: (c, u) => Container(
                                          color: AppColors.primaryPurple.withValues(alpha: 0.2)),
                                    )
                                  : Container(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [AppColors.primaryPurple, Color(0xFF4A148C)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                      ),
                                      child: const Center(
                                          child: Icon(Icons.store, size: 60, color: Colors.white24)),
                                    )),
                        ),
                        // Overlay escurecido no bottom para legibilidade
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          height: 80,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.45),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // ── Logo circular na esquerda inferior ──────────
                        Positioned(
                          left: 16,
                          bottom: 12,
                          child: GestureDetector(
                            onTap: () => _pickAndEditImage(isCover: false),
                            child: Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                    border: Border.all(color: Colors.white, width: 3),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.25),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      )
                                    ],
                                  ),
                                  child: ClipOval(
                                    child: _newLogoFile != null
                                        ? (kIsWeb
                                            ? Image.network(_newLogoFile!.path, fit: BoxFit.cover)
                                            : Image.file(File(_newLogoFile!.path), fit: BoxFit.cover))
                                        : (_logoUrl != null
                                            ? CachedNetworkImage(
                                                imageUrl: _logoUrl!,
                                                fit: BoxFit.cover,
                                                placeholder: (c, u) =>
                                                    const CircularProgressIndicator(strokeWidth: 2),
                                                errorWidget: (c, u, e) =>
                                                    const Icon(Icons.store, color: Colors.grey, size: 32),
                                              )
                                            : Icon(Icons.add_a_photo,
                                                color: Colors.grey[300], size: 30)),
                                  ),
                                ),
                                // Botão de edição do logo
                                Container(
                                  margin: const EdgeInsets.only(right: 1, bottom: 1),
                                  padding: const EdgeInsets.all(5),
                                  decoration: const BoxDecoration(
                                    color: AppColors.primaryPurple,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.edit, color: Colors.white, size: 11),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // ── Botão editar capa (direita inferior) ────────
                        Positioned(
                          right: 14,
                          bottom: 14,
                          child: GestureDetector(
                            onTap: () => _pickAndEditImage(isCover: true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.camera_alt, color: Colors.white, size: 15),
                                  SizedBox(width: 5),
                                  Text("Alterar Capa",
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ─── FORMULÁRIO ───────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTextField(
                            controller: _nameController,
                            label: "Nome da Loja",
                            icon: Icons.store_mall_directory,
                            validator: (v) => v!.isEmpty ? "Campo obrigatório" : null,
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _descController,
                            label: "Descrição",
                            icon: Icons.description,
                            maxLines: 3,
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _addressController,
                            label: "Endereço",
                            icon: Icons.location_on,
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _phoneController,
                            label: "Telefone / WhatsApp",
                            icon: Icons.phone,
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 16),

                          // ── Link Personalizado ──────────────────────────
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.primaryPurple.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: AppColors.primaryPurple.withValues(alpha: 0.2)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.link,
                                        color: AppColors.primaryPurple, size: 18),
                                    const SizedBox(width: 8),
                                    const Text(
                                      "Link Personalizado da Loja",
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  "Crie um link único para seus clientes acessarem sua loja",
                                  style: TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                                const SizedBox(height: 10),
                                TextFormField(
                                  controller: _slugController,
                                  decoration: InputDecoration(
                                    labelText: "Seu Link (ex: afroED)",
                                    prefixIcon: const Icon(Icons.link,
                                        color: AppColors.primaryPurple),
                                    prefixText: "markaai.com.br/",
                                    prefixStyle: const TextStyle(
                                      color: AppColors.primaryPurple,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12)),
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) return null;
                                    if (v.length < 3) return "Mínimo 3 caracteres";
                                    if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(v)) {
                                      return "Apenas letras, números e hífen";
                                    }
                                    return null;
                                  },
                                  onChanged: (value) => setState(() {}),
                                ),
                                if (_slugController.text.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: Colors.green.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.check_circle,
                                            color: Colors.green, size: 16),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text("Seu link público:",
                                                  style: TextStyle(
                                                      fontSize: 10, color: Colors.grey)),
                                              const SizedBox(height: 2),
                                              SelectableText(
                                                "https://markaai.com.br/${_normalizeSlug(_slugController.text)}",
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.primaryPurple,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.copy, size: 18),
                                          color: AppColors.primaryPurple,
                                          tooltip: "Copiar link",
                                          onPressed: () {
                                            final link =
                                                "https://markaai.com.br/${_normalizeSlug(_slugController.text)}";
                                            Clipboard.setData(ClipboardData(text: link));
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text("Link copiado!"),
                                                backgroundColor: Colors.green,
                                                duration: Duration(seconds: 2),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          const SizedBox(height: 14),

                          // ── Redes Sociais ────────────────────────────────
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue.shade100),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.share,
                                        color: Colors.blue.shade700, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      "Redes Sociais",
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Colors.blue.shade700),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  "Conecte suas redes para seus clientes encontrarem você",
                                  style: TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                                const SizedBox(height: 10),
                                _buildTextField(
                                  controller: _instagramController,
                                  label: "Instagram (ex: @minha_loja)",
                                  icon: Icons.camera_alt,
                                ),
                                const SizedBox(height: 10),
                                _buildTextField(
                                  controller: _whatsappController,
                                  label: "WhatsApp Público (ex: 11999999999)",
                                  icon: Icons.phone,
                                  keyboardType: TextInputType.phone,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Vitrine de Serviços ─────────────────────────────────
                SliverToBoxAdapter(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.only(top: 4, bottom: 24),
                    child: _buildServicesShowcase(),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            ),
    );
  }

'''

new_content = content[:start] + NEW_BUILD + content[end + 1:]

with open(PATH, 'w', encoding='utf-8') as f:
    f.write(new_content)

print(f"Done! build() rewritten. {len(content)} -> {len(new_content)} chars")
