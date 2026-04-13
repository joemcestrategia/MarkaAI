import 'package:flutter/material.dart';

class AuthErrorData {
  final String title;
  final String message;
  final IconData icon;

  AuthErrorData({
    required this.title,
    required this.message,
    this.icon = Icons.error_outline,
  });
}

class AuthErrorHandler {
  static AuthErrorData handle(String errorCode) {
    switch (errorCode) {
      case 'RATE_LIMIT':
        return AuthErrorData(
          title: 'Muitas tentativas',
          message: 'Calma aí! Por segurança, aguarde alguns minutos antes de tentar novamente.',
          icon: Icons.timer_outlined,
        );
      case 'INVALID_CREDENTIALS':
        return AuthErrorData(
          title: 'Dados Incorretos',
          message: 'E-mail ou senha não conferem. Verifique os dados e tente de novo.',
          icon: Icons.lock_outline,
        );
      case 'EMAIL_NOT_CONFIRMED':
        return AuthErrorData(
          title: 'Confirmação Pendente',
          message: 'Quase lá! Você precisa confirmar seu e-mail antes de entrar. Verifique sua caixa de entrada.',
          icon: Icons.mark_email_unread_outlined,
        );
      case 'USER_NOT_FOUND':
        return AuthErrorData(
          title: 'Usuário não encontrado',
          message: 'Não encontramos nenhuma conta com este e-mail. Verifique a digitação ou crie uma nova conta.',
          icon: Icons.person_search_outlined,
        );
      case 'EMAIL_ALREADY_EXISTS':
        return AuthErrorData(
          title: 'E-mail em uso',
          message: 'Este e-mail já está cadastrado. Tente fazer login ou recupere sua senha.',
          icon: Icons.info_outline,
        );
      case 'WEAK_PASSWORD':
        return AuthErrorData(
          title: 'Senha Fraca',
          message: 'Sua senha deve ter pelo menos 6 caracteres para garantir sua segurança.',
          icon: Icons.security_outlined,
        );
      case 'NETWORK_ERROR':
        return AuthErrorData(
          title: 'Erro de Conexão',
          message: 'Não conseguimos conectar aos nossos servidores. Verifique sua internet.',
          icon: Icons.wifi_off_outlined,
        );
      default:
        return AuthErrorData(
          title: 'Ops! Algo deu errado',
          message: 'Ocorreu um erro inesperado ao processar sua solicitação. Tente novamente em instantes.',
          icon: Icons.error_outline,
        );
    }
  }
}
