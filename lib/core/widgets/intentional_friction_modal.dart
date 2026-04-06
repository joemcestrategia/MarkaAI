import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class IntentionalFrictionModal extends StatefulWidget {
  final String title;
  final Widget content;
  final String expectedPhrase;
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;

  const IntentionalFrictionModal({
    super.key,
    required this.title,
    required this.content,
    required this.expectedPhrase,
    required this.onConfirm,
    this.onCancel,
  });

  @override
  State<IntentionalFrictionModal> createState() => _IntentionalFrictionModalState();
}

class _IntentionalFrictionModalState extends State<IntentionalFrictionModal> {
  final TextEditingController _controller = TextEditingController();
  bool _isButtonEnabled = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_validateInput);
  }

  void _validateInput() {
    final input = _controller.text.trim().toUpperCase();
    final expected = widget.expectedPhrase.trim().toUpperCase();
    setState(() {
      _isButtonEnabled = input == expected;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_validateInput);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 10,
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryPurple,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              DefaultTextStyle(
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
                child: widget.content,
              ),
              const SizedBox(height: 24),
              Text(
                'Digite "${widget.expectedPhrase}" para confirmar:',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                autofocus: true,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: widget.expectedPhrase,
                  hintStyle: TextStyle(color: Colors.grey[300]),
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primaryPurple, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isButtonEnabled ? widget.onConfirm : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  disabledForegroundColor: Colors.grey[500],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'CONFIRMAR',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  if (widget.onCancel != null) {
                    widget.onCancel!();
                  } else {
                    Navigator.pop(context);
                  }
                },
                child: Text(
                  'Cancelar',
                  style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
