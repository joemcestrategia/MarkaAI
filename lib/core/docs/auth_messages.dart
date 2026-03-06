class AuthMessages {
  static const String telefoneJaCadastrado =
      "Este telefone já está vinculado a uma conta. Faça login para continuar.";

  static const String emailJaCadastrado =
      "Este e-mail já está cadastrado. Faça login ou recupere sua senha.";

  static const String contaSimilarEncontrada =
      "Encontramos uma conta com dados semelhantes. É você? Faça login para continuar.";

  static String vincularSocial(String provedor) {
    return "Já existe uma conta com este e-mail. Deseja vincular seu $provedor a esta conta?";
  }

  static const String telefoneInvalido =
      "Informe um telefone válido com DDD. Ex: (11) 99999-9999";
}
