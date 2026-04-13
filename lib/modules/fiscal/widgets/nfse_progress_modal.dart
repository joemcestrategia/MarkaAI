import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class NfseProgressStep {
  final String label;
  bool isDone;
  bool isError;
  bool isCurrent;

  NfseProgressStep({
    required this.label,
    this.isDone = false,
    this.isError = false,
    this.isCurrent = false,
  });
}

class NfseProgressModal extends StatefulWidget {
  final String title;
  final List<NfseProgressStep> steps;
  final String? errorMessage;

  const NfseProgressModal({
    super.key,
    required this.title,
    required this.steps,
    this.errorMessage,
  });

  @override
  State<NfseProgressModal> createState() => _NfseProgressModalState();
}

class _NfseProgressModalState extends State<NfseProgressModal> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.receipt_long_rounded, color: AppColors.primaryPurple),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...widget.steps.asMap().entries.map((entry) {
            final index = entry.key;
            final step = entry.value;
            return _buildStep(step, index == widget.steps.length - 1);
          }),
          if (widget.errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (widget.errorMessage != null)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
      ],
    );
  }

  Widget _buildStep(NfseProgressStep step, bool isLast) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: step.isDone
                    ? Colors.green
                    : (step.isError
                        ? Colors.red
                        : (step.isCurrent ? AppColors.primaryPurple : Colors.grey.shade300)),
              ),
              child: step.isDone
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : (step.isError
                      ? const Icon(Icons.close, color: Colors.white, size: 14)
                      : (step.isCurrent
                          ? const Padding(
                              padding: EdgeInsets.all(4),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : null)),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 20,
                color: step.isDone ? Colors.green : Colors.grey.shade300,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              step.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: step.isCurrent ? FontWeight.bold : FontWeight.normal,
                color: step.isError
                    ? Colors.red
                    : (step.isDone ? Colors.green : (step.isCurrent ? Colors.black87 : Colors.grey)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
