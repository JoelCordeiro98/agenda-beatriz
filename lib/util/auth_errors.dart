import 'package:supabase_flutter/supabase_flutter.dart';

/// Traduz os erros de login/cadastro do Supabase para mensagens em português.
String authErrorPt(Object e) {
  if (e is PostgrestException) {
    final pm = e.message.toLowerCase();
    if (pm.contains('locked')) {
      return 'Muitas tentativas erradas. Tente de novo daqui a 30 minutos.';
    }
    if (pm.contains('weak_password')) {
      return 'A senha precisa ter pelo menos 6 caracteres.';
    }
    if (pm.contains('word_too_short')) {
      return 'A palavra de recuperação precisa ter pelo menos 3 letras.';
    }
    return 'Não foi possível concluir. Tente de novo.';
  }
  if (e is! AuthException) {
    return 'Sem conexão. Verifique a internet e tente de novo.';
  }
  final m = e.message.toLowerCase();
  final code = (e.code ?? '').toLowerCase();

  if (code.contains('rate_limit') || m.contains('rate limit') || e.statusCode == '429') {
    return 'Muitas tentativas. Espere alguns minutos e tente de novo.';
  }
  if (code == 'user_already_exists' || m.contains('already registered')) {
    return 'Já existe uma conta com esse e-mail. Use "Entrar" ou "Esqueci minha senha".';
  }
  if (code == 'email_not_confirmed' || m.contains('not confirmed')) {
    return 'Falta confirmar o e-mail com o código que enviamos.';
  }
  if (code == 'invalid_credentials' || m.contains('invalid login')) {
    return 'E-mail ou senha incorretos.';
  }
  if (code == 'otp_expired' || m.contains('expired') || m.contains('token')) {
    return 'Código inválido ou vencido. Peça um novo código.';
  }
  if (code == 'same_password') {
    return 'A nova senha precisa ser diferente da anterior.';
  }
  if (code == 'weak_password' || m.contains('password should')) {
    return 'Senha fraca. Use pelo menos 6 caracteres.';
  }
  if (code == 'signup_disabled' || m.contains('signups not allowed')) {
    return 'O cadastro de novas contas está desativado.';
  }
  if (m.contains('timeout') || m.contains('timed out') || e.statusCode == '504') {
    return 'O servidor demorou para enviar o e-mail com o código. Tente de novo em alguns minutos.';
  }
  if (m.contains('not authorized') || m.contains('error sending')) {
    return 'Não foi possível enviar o e-mail agora. Tente mais tarde.';
  }
  return 'Não foi possível concluir: ${e.message}';
}

bool isEmailNotConfirmed(Object e) =>
    e is AuthException &&
    ((e.code ?? '') == 'email_not_confirmed' ||
        e.message.toLowerCase().contains('not confirmed'));

bool looksLikeEmail(String s) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s.trim());
