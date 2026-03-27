import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Um StreamBuilder robusto para Supabase que lida com:
/// 1. Dados iniciais via Future (cache-first) para evitar telas brancas.
/// 2. Erros de timeout do Realtime (RealtimeSubscribeException).
/// 3. Botão de retry padronizado.
/// 4. Persistência do último dado conhecido em caso de erro momentâneo de conexão.
class SupabaseStreamWidget<T> extends StatefulWidget {
  final Stream<T> stream;
  final Future<T>? initialFuture;
  final Widget Function(BuildContext context, T data) builder;
  final Widget Function(BuildContext context, Object error)? errorBuilder;
  final Widget Function(BuildContext context)? loadingBuilder;
  final Widget Function(BuildContext context)? emptyBuilder;
  final bool Function(T data)? isEmpty;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final bool showLoadingOnStreamWaiting;

  const SupabaseStreamWidget({
    super.key,
    required this.stream,
    this.initialFuture,
    required this.builder,
    this.errorBuilder,
    this.loadingBuilder,
    this.emptyBuilder,
    this.isEmpty,
    this.errorMessage,
    this.onRetry,
    this.showLoadingOnStreamWaiting = false,
  });

  @override
  State<SupabaseStreamWidget<T>> createState() => _SupabaseStreamWidgetState<T>();
}

class _SupabaseStreamWidgetState<T> extends State<SupabaseStreamWidget<T>> {
  T? _lastData;
  bool _hasHadData = false;

  @override
  void initState() {
    super.initState();
    _handleInitialFuture();
  }

  Future<void> _handleInitialFuture() async {
    if (widget.initialFuture != null) {
      try {
        final data = await widget.initialFuture!;
        if (mounted && !_hasHadData) {
          setState(() {
            _lastData = data;
          });
        }
      } catch (e) {
        // Erro no future inicial é ignorado para deixar o stream tentar carregar
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      stream: widget.stream,
      builder: (context, snapshot) {
        // Se houver dados novos, atualiza o cache local
        if (snapshot.hasData) {
          _lastData = snapshot.data;
          _hasHadData = true;
        }

        // PRIORIDADE 1: Erro
        if (snapshot.hasError) {
          final error = snapshot.error!;
          
          // Se já temos algum dado (do future ou do stream anterior), mostramos ele
          // Mas talvez com um pequeno indicador de erro ou apenas o dado para não quebrar a UX
          if (_lastData != null && !_isCriticalError(error)) {
            return widget.builder(context, _lastData as T);
          }

          if (widget.errorBuilder != null) {
            return widget.errorBuilder!(context, error);
          }

          return _DefaultErrorWidget(
            error: error,
            message: widget.errorMessage,
            onRetry: widget.onRetry,
          );
        }

        // PRIORIDADE 2: Loading (Apenas se não tivermos nada em cache/lastData)
        if (snapshot.connectionState == ConnectionState.waiting && _lastData == null) {
          if (widget.loadingBuilder != null) {
            return widget.loadingBuilder!(context);
          }
          return const Center(child: CircularProgressIndicator(color: AppColors.primaryPurple, strokeWidth: 2));
        }

        // OPCIONAL: Mostrar loading mesmo com lastData se configurado
        if (snapshot.connectionState == ConnectionState.waiting && widget.showLoadingOnStreamWaiting) {
           return const Center(child: CircularProgressIndicator(color: AppColors.primaryPurple, strokeWidth: 2));
        }

        final data = _lastData;

        // PRIORIDADE 3: Vazio
        if (data == null || (widget.isEmpty != null && widget.isEmpty!(data))) {
          if (widget.emptyBuilder != null) {
            return widget.emptyBuilder!(context);
          }
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                const Text("Nenhum dado encontrado.", style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        // PRIORIDADE 4: Sucesso
        return widget.builder(context, data);
      },
    );
  }

  bool _isCriticalError(Object error) {
    // Erros de timeout do Realtime não são críticos se tivermos dados antigos
    if (error.toString().contains('RealtimeSubscribeException')) return false;
    if (error.toString().contains('timedOut')) return false;
    return false; // Por padrão, tenta mostrar o último dado
  }
}

class _DefaultErrorWidget extends StatelessWidget {
  final Object error;
  final String? message;
  final VoidCallback? onRetry;

  const _DefaultErrorWidget({
    required this.error,
    this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    String displayError = error.toString();
    if (displayError.contains('RealtimeSubscribeException') || displayError.contains('timedOut')) {
      displayError = "A conexão em tempo real demorou muito a responder.";
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, color: Colors.orange, size: 64),
            const SizedBox(height: 16),
            Text(
              message ?? 'Erro ao carregar: $displayError',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: 200,
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('TENTAR NOVAMENTE'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
