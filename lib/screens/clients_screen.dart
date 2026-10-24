import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../repository.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  List<Client> _clients = [];
  String _query = '';
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
      final list = await repo.clients();
      if (!mounted) return;
      setState(() {
        _clients = list;
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

  /// "(83) 98888-7777" -> "5583988887777"
  static String? _waNumber(String? phone) {
    if (phone == null) return null;
    var digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10 || digits.length == 11) digits = '55$digits';
    return digits.length >= 12 ? digits : null;
  }

  Future<void> _whatsapp(Client c) async {
    final n = _waNumber(c.phone);
    if (n == null) return;
    final ok = await launchUrl(Uri.parse('https://wa.me/$n'),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não consegui abrir o WhatsApp.')));
    }
  }

  Future<void> _edit([Client? c]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ClientSheet(client: c),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final visible = q.isEmpty
        ? _clients
        : _clients.where((c) => c.name.toLowerCase().contains(q)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Cliente'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Buscar cliente',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child:
                            TextButton(onPressed: _load, child: Text(_error!)))
                    : visible.isEmpty
                        ? Center(
                            child: Text(_clients.isEmpty
                                ? 'As clientes aparecem aqui ao agendar.'
                                : 'Nenhuma cliente encontrada.'))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 96),
                              itemCount: visible.length,
                              itemBuilder: (_, i) {
                                final c = visible[i];
                                final details = [
                                  if (c.phone != null) c.phone!,
                                  'retorno a cada ${c.intervalDays} dias',
                                ].join(' · ');
                                return ListTile(
                                  leading: Icon(
                                    c.isRegular
                                        ? Icons.star
                                        : Icons.person_outline,
                                    color: c.isRegular ? Colors.amber : null,
                                  ),
                                  title: Text(c.name),
                                  subtitle: Text(details),
                                  onTap: () => _edit(c),
                                  trailing: _waNumber(c.phone) == null
                                      ? null
                                      : IconButton(
                                          tooltip: 'Chamar no WhatsApp',
                                          icon: const Icon(Icons.chat_outlined),
                                          onPressed: () => _whatsapp(c),
                                        ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _ClientSheet extends StatefulWidget {
  final Client? client;
  const _ClientSheet({this.client});

  @override
  State<_ClientSheet> createState() => _ClientSheetState();
}

class _ClientSheetState extends State<_ClientSheet> {
  late final _name = TextEditingController(text: widget.client?.name ?? '');
  late final _phone = TextEditingController(text: widget.client?.phone ?? '');
  late final _notes = TextEditingController(text: widget.client?.notes ?? '');
  late int _interval = widget.client?.intervalDays ?? 30;
  late bool _regular = widget.client?.isRegular ?? false;
  bool _saving = false;
  String? _error;

  static const _intervals = [14, 21, 28, 35, 42];

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Digite o nome.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await repo.saveClient(
        id: widget.client?.id,
        name: name,
        phone: _phone.text.trim(),
        intervalDays: _interval,
        isRegular: _regular,
        notes: _notes.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Não foi possível salvar. Verifique a internet.';
        });
      }
    }
  }

  String _intervalLabel(int d) => d % 7 == 0 ? '${d ~/ 7} semanas' : '$d dias';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = {..._intervals, _interval}.toList()..sort();

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.client == null ? 'Nova cliente' : 'Editar cliente',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Nome', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'WhatsApp (com DDD)',
                hintText: '(83) 98888-7777',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Cliente fixa'),
              subtitle: const Text('Volta sempre e deixa o retorno marcado'),
              value: _regular,
              onChanged: (v) => setState(() => _regular = v),
            ),
            const SizedBox(height: 4),
            Text('Retorno sugerido a cada', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in options)
                  ChoiceChip(
                    label: Text(_intervalLabel(d)),
                    selected: _interval == d,
                    onSelected: (_) => setState(() => _interval = d),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notes,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Observações (opcional)',
                hintText: 'Ex.: prefere formato amendoado',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_saving ? 'Salvando…' : 'Salvar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
