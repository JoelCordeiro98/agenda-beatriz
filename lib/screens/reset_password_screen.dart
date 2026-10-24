import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repository.dart';
import '../util/auth_errors.dart';

/// Esqueci minha senha: e-mail + palavra de recuperação + senha nova.
class ResetPasswordScreen extends StatefulWidget {
  final String? email;
  const ResetPasswordScreen({super.key, this.email});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  late final _email = TextEditingController(text: widget.email ?? '');
  final _word = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _word.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final email = _email.text.trim();
    String? problem;
    if (!looksLikeEmail(email)) {
      problem = 'Digite um e-mail válido.';
    } else if (_word.text.trim().isEmpty) {
      problem = 'Digite a palavra de recuperação.';
    } else if (_password.text.length < 6) {
      problem = 'A senha nova precisa ter pelo menos 6 caracteres.';
    } else if (_password.text != _confirm.text) {
      problem = 'As senhas não são iguais.';
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
      final ok = await repo.resetPasswordWithWord(
        email: email,
        word: _word.text,
        newPassword: _password.text,
      );
      if (!ok) {
        setState(() {
          _loading = false;
          _error = 'E-mail ou palavra de recuperação não conferem.';
        });
        return;
      }
      await Supabase.instance.client.auth
          .signInWithPassword(email: email, password: _password.text);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).popUntil((r) => r.isFirst);
      messenger.showSnackBar(const SnackBar(
          content: Text('Senha alterada! Você já está conectada.')));
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
      appBar: AppBar(title: const Text('Recuperar senha')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Digite seu e-mail e a palavra de recuperação que você '
                    'escolheu ao criar a conta. Depois é só escolher a senha nova.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                        labelText: 'E-mail', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _word,
                    decoration: const InputDecoration(
                      labelText: 'Palavra de recuperação',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(
                      labelText: 'Nova senha',
                      helperText: 'Pelo menos 6 caracteres',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirm,
                    obscureText: true,
                    onSubmitted: (_) => _save(),
                    decoration: const InputDecoration(
                        labelText: 'Repita a nova senha',
                        border: OutlineInputBorder()),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _loading ? null : _save,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Salvar nova senha'),
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
