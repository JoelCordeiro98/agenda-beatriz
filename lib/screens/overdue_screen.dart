import 'package:flutter/material.dart';

import '../models.dart';
import '../repository.dart';
import '../util/format.dart';
import '../util/whatsapp.dart';
import '../widgets/client_avatar.dart';
import '../widgets/new_appointment_sheet.dart';

/// Clientes que já passaram do prazo de retorno e não têm horário marcado.
class OverdueScreen extends StatefulWidget {
  const OverdueScreen({super.key});

  @override
  State<OverdueScreen> createState() => _OverdueScreenState();
}

class _OverdueScreenState extends State<OverdueScreen> {
  bool _onlyRegular = true;
  List<OverdueClient> _list = [];
  Map<String, String> _photos = {};
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
      final list = await repo.overdueClients(onlyRegular: _onlyRegular);
      final photos = await repo.photoUrls(list.map((o) => o.client.photoPath));
      if (!mounted) return;
      setState(() {
        _list = list;
        _photos = photos;
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
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _message(OverdueClient o) async {
    final days = DateTime.now().difference(o.lastVisit).inDays;
    final ok = await openWhatsApp(
        phone: o.client.phone, text: comeBackMessage(o.client, days));
    if (!ok && mounted) _snack('Não consegui abrir o WhatsApp.');
  }

  Future<void> _schedule(OverdueClient o) async {
    List<Service> services;
    List<Client> clients;
    try {
      services = await repo.services();
      clients = await repo.clients();
    } catch (_) {
      _snack('Sem conexão. Tente de novo.');
      return;
    }
    if (!mounted) return;
    final n = DateTime.now();
    final saved = await showNewAppointmentSheet(
      context,
      initialDateTime: DateTime(n.year, n.month, n.day + 1, 8),
      clients: clients,
      services: services,
      clientName: o.client.name,
      clientId: o.client.id,
      title: 'Agendar ${firstName(o.client.name)}',
    );
    if (saved != null && mounted) {
      _snack('Agendado para ${shortDateTime(saved)}');
      _load();
    }
  }

  String _lateLabel(OverdueClient o) {
    final since = DateTime.now().difference(o.lastVisit).inDays;
    final last = 'última visita há $since dias';
    return o.daysLate == 0 ? '$last · vence hoje' : '$last · ${o.daysLate} dias de atraso';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes sumidas')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Só clientes fixas'),
                  selected: _onlyRegular,
                  onSelected: (_) {
                    setState(() => _onlyRegular = true);
                    _load();
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Todas'),
                  selected: !_onlyRegular,
                  onSelected: (_) {
                    setState(() => _onlyRegular = false);
                    _load();
                  },
                ),
              ],
            ),
          ),
          Expanded(child: _body(theme)),
        ],
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: TextButton(onPressed: _load, child: Text(_error!)));
    }
    if (_list.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Ninguém sumido por aqui! 🎉\nTodas estão em dia ou já têm horário marcado.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        itemCount: _list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final o = _list[i];
          final c = o.client;
          return Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ListTile(
                    leading: ClientAvatar(
                      name: c.name,
                      photoUrl: c.photoPath == null ? null : _photos[c.photoPath],
                    ),
                    title: Text(c.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(_lateLabel(o)),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _schedule(o),
                        icon: const Icon(Icons.event, size: 18),
                        label: const Text('Agendar'),
                      ),
                      FilledButton.icon(
                        onPressed: () => _message(o),
                        icon: const Icon(Icons.chat_outlined, size: 18),
                        label: const Text('Chamar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
