import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repository.dart';
import '../util/auth_errors.dart';
import 'clients_screen.dart';
import 'services_screen.dart';
import 'work_hours_screen.dart';

class AjustesScreen extends StatelessWidget {
  /// Chamado quando algo que a Agenda usa (serviços, horários) foi alterado.
  final VoidCallback onChanged;

  const AjustesScreen({super.key, required this.onChanged});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair da conta?'),
        content: const Text('Os dados continuam salvos. É só entrar de novo.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sair')),
        ],
      ),
    );
    if (ok == true) await Supabase.instance.client.auth.signOut();
  }

  Future<void> _editRecoveryWord(BuildContext context) async {
    final word = TextEditingController();
    String? error;
    bool saving = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Palavra de recuperação'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Se esquecer a senha, você cria uma nova com o seu e-mail e '
                  'esta palavra. Escolha algo que só você saiba.'),
              const SizedBox(height: 12),
              TextField(
                controller: word,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nova palavra'),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (word.text.trim().length < 3) {
                        setLocal(() => error = 'Use pelo menos 3 letras.');
                        return;
                      }
                      setLocal(() => saving = true);
                      try {
                        await repo.setRecoveryWord(word.text.trim());
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setLocal(() {
                          saving = false;
                          error = authErrorPt(e);
                        });
                      }
                    },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    word.dispose();
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Palavra de recuperação salva.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.sell_outlined),
            title: const Text('Serviços e preços'),
            subtitle: const Text('O que aparece na hora de agendar'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, ServicesScreen(onChanged: onChanged)),
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Horários de trabalho'),
            subtitle: const Text('Os horários de cada dia da agenda'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, WorkHoursScreen(onChanged: onChanged)),
          ),
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: const Text('Clientes'),
            subtitle: const Text('Telefone, cliente fixa e retorno'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, const ClientsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('Palavra de recuperação'),
            subtitle: const Text('Usada para criar uma senha nova se esquecer'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editRecoveryWord(context),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sair'),
            subtitle: Text(email),
            onTap: () => _logout(context),
          ),
        ],
      ),
    );
  }
}
