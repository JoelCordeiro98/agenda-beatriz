import 'package:flutter/material.dart';

import '../models.dart';
import '../repository.dart';
import '../util/format.dart';

class ServicesScreen extends StatefulWidget {
  final VoidCallback onChanged;
  const ServicesScreen({super.key, required this.onChanged});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  List<Service> _services = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await repo.allServices();
      if (!mounted) return;
      setState(() {
        _services = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar. Verifique a internet.';
      });
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _edit([Service? s]) async {
    final name = TextEditingController(text: s?.name ?? '');
    final price =
        TextEditingController(text: s == null ? '' : priceText(s.defaultPrice));
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(s == null ? 'Novo serviço' : 'Editar serviço'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: s == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: price,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Preço', prefixText: r'R$ '),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
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
              onPressed: () async {
                final n = name.text.trim();
                final p = parsePrice(price.text);
                if (n.isEmpty || p == null) {
                  setLocal(() => error = 'Preencha o nome e o preço.');
                  return;
                }
                try {
                  await repo.saveService(id: s?.id, name: n, price: p);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (_) {
                  setLocal(() => error = 'Não foi possível salvar.');
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    name.dispose();
    price.dispose();
    if (saved == true) {
      widget.onChanged();
      _load();
    }
  }

  Future<void> _toggle(Service s, bool active) async {
    try {
      await repo.setServiceActive(s.id, active);
      widget.onChanged();
      _load();
    } catch (_) {
      _snack('Não foi possível salvar. Verifique a internet.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Serviços e preços')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Serviço'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: TextButton(onPressed: _load, child: Text(_error!)))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        'Toque para mudar nome ou preço. Desligue a chave para '
                        'esconder um serviço da agenda sem perder o histórico.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    for (final s in _services)
                      ListTile(
                        title: Text(
                          s.name,
                          style: s.active
                              ? null
                              : TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant),
                        ),
                        subtitle: Text(s.active
                            ? money.format(s.defaultPrice)
                            : '${money.format(s.defaultPrice)} · escondido'),
                        onTap: () => _edit(s),
                        trailing: Switch(
                          value: s.active,
                          onChanged: (v) => _toggle(s, v),
                        ),
                      ),
                  ],
                ),
    );
  }
}
