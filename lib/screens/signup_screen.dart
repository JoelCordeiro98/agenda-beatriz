import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repository.dart';
import '../util/auth_errors.dart';

/// Criar conta: e-mail, senha e palavra de recuperação. Não envia e-mail.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _word = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _word.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final email = _email.text.trim();
    final word = _word.text.trim();
    String? problem;
    if (!looksLikeEmail(email)) {
      problem = 'Digite um e-mail válido.';
    } else if (_password.text.length < 6) {
      problem = 'A senha precisa ter pelo menos 6 caracteres.';
    } else if (_password.text != _confirm.text) {
      problem = 'As senhas não são iguais.';
    } else if (word.length < 3) {
      problem = 'Escolha uma palavra de recuperação com pelo menos 3 letras.';
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client.auth
          .signUp(email: email, password: _password.text);
      if (res.session == null) {
        // "Confirm email" ainda está ligado no Supabase.
        setState(() {
          _loading = false;
          _error = 'A conta foi criada, mas o servidor está pedindo confirmação '
              'por e-mail. Desligue "Confirm email" no Supabase.';
        });
        return;
      }
      String msg = 'Conta criada! Bem-vinda 💅';
      try {
        await repo.setRecoveryWord(word);
      } catch (_) {
        msg = 'Conta criada! Cadastre a palavra de recuperação em Ajustes.';
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).popUntil((r) => r.isFirst);
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = authErrorPt(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Criar conta')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                        labelText: 'E-mail', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(
                      labelText: 'Senha',
                      helperText: 'Pelo menos 6 caracteres',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirm,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Repita a senha',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 20),
                  Text('Palavra de recuperação',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Se esquecer a senha, é com ela que você cria uma nova. '
                    'Escolha algo fácil de lembrar e que só você saiba, '
                    'como o nome do seu primeiro bichinho.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _word,
                    onSubmitted: (_) => _create(),
                    decoration: const InputDecoration(
                      labelText: 'Palavra de recuperação',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _loading ? null : _create,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Criar conta'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
