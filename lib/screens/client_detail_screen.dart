import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../repository.dart';
import '../util/format.dart';
import '../util/whatsapp.dart';
import '../widgets/client_avatar.dart';
import '../widgets/new_appointment_sheet.dart';
import 'clients_screen.dart';

/// Ficha da cliente: números, fotos das unhas e histórico de atendimentos.
class ClientDetailScreen extends StatefulWidget {
  final String clientId;
  const ClientDetailScreen({super.key, required this.clientId});

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  Client? _client;
  ClientStats _stats = const ClientStats();
  List<Appointment> _history = [];
  Map<String, String> _photos = {};
  bool _loading = true;
  bool _changed = false;
  String? _error;

  static final _date = DateFormat('dd/MM/yyyy');

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
      final c = await repo.client(widget.clientId);
      var stats = const ClientStats();
      try {
        stats = await repo.clientStats(widget.clientId);
      } catch (_) {}
      final history = await repo.clientHistory(widget.clientId);
      final photos = await repo.photoUrls([
        c?.photoPath,
        for (final a in history) a.nailPhotoPath,
      ]);
      if (!mounted) return;
      setState(() {
        _client = c;
        _stats = stats;
        _history = history;
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

  Future<void> _edit() async {
    final c = _client;
    if (c == null) return;
    final saved = await showClientSheet(context,
        client: c, photoUrl: c.photoPath == null ? null : _photos[c.photoPath]);
    if (saved == true) {
      _changed = true;
      _load();
    }
  }

  Future<void> _schedule() async {
    final c = _client;
    if (c == null) return;
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
      clientName: c.name,
      clientId: c.id,
      title: 'Agendar ${firstName(c.name)}',
    );
    if (saved != null && mounted) {
      _snack('Agendado para ${shortDateTime(saved)}');
      _changed = true;
      _load();
    }
  }

  Future<void> _chat() async {
    final c = _client;
    if (c == null) return;
    final ok = await openWhatsApp(
        phone: c.phone, text: 'Oi, ${firstName(c.name)}! 💅 ');
    if (!ok && mounted) _snack('Não consegui abrir o WhatsApp.');
  }

  void _openPhoto(String url, Appointment a) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
            ListTile(
              title: Text(_date.format(a.startsAt)),
              subtitle: a.items.isEmpty ? null : Text(a.servicesLabel),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_client?.name ?? 'Cliente'),
          actions: [
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _client == null ? null : _edit,
            ),
          ],
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _client == null) {
      return Center(
        child: TextButton(
            onPressed: _load, child: Text(_error ?? 'Cliente não encontrada.')),
      );
    }
    final theme = Theme.of(context);
    final c = _client!;
    final nails = [
      for (final a in _history)
        if (a.nailPhotoPath != null && _photos[a.nailPhotoPath] != null) a,
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ------------------------------------------------ cabeçalho
          Row(
            children: [
              ClientAvatar(
                name: c.name,
                radius: 36,
                photoUrl: c.photoPath == null ? null : _photos[c.photoPath],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(c.name,
                              style: theme.textTheme.titleLarge,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (c.isRegular) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.star, color: Colors.amber, size: 20),
                        ],
                      ],
                    ),
                    if (c.phone != null) Text(c.phone!),
                    Text('Retorno a cada ${c.intervalDays} dias',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _schedule,
                  icon: const Icon(Icons.event),
                  label: const Text('Agendar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: waNumber(c.phone) == null ? null : _chat,
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('WhatsApp'),
                ),
              ),
            ],
          ),
          if (c.notes != null && c.notes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              color: theme.colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.sticky_note_2_outlined),
                    const SizedBox(width: 8),
                    Expanded(child: Text(c.notes!)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),

          // ------------------------------------------------ números
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Stat('Última visita',
                  _stats.lastVisit == null ? '—' : _date.format(_stats.lastVisit!)),
              _Stat('Próximo horário',
                  _stats.nextVisit == null ? '—' : shortDateTime(_stats.nextVisit!)),
              _Stat('Visitas', '${_stats.visits}'),
              _Stat('Faltas', '${_stats.noShows}'),
              _Stat('Total gasto', money.format(_stats.totalSpent)),
            ],
          ),

          // ------------------------------------------------ fotos das unhas
          if (nails.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Fotos das unhas', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: nails.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final a = nails[i];
                  final url = _photos[a.nailPhotoPath]!;
                  return InkWell(
                    onTap: () => _openPhoto(url, a),
                    borderRadius: BorderRadius.circular(12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(url,
                          width: 110, height: 110, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                                width: 110,
                                color: theme.colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.broken_image_outlined),
                              )),
                    ),
                  );
                },
              ),
            ),
          ],

          // ------------------------------------------------ histórico
          const SizedBox(height: 20),
          Text('Histórico', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          if (_history.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Nenhum atendimento ainda.'),
            )
          else
            for (final a in _history)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(switch (a.status) {
                  ApptStatus.concluido => Icons.check_circle,
                  ApptStatus.faltou => Icons.person_off_outlined,
                  _ => Icons.schedule,
                },
                    color: switch (a.status) {
                      ApptStatus.concluido => Colors.green,
                      ApptStatus.faltou => Colors.orange,
                      _ => theme.colorScheme.primary,
                    }),
                title: Text(shortDateTime(a.startsAt)),
                subtitle: Text([
                  if (a.items.isNotEmpty) a.servicesLabel,
                  if (a.status == ApptStatus.faltou) 'faltou',
                  if (a.status == ApptStatus.agendado) 'agendado',
                  if (a.status == ApptStatus.concluido && a.paymentMethod != null)
                    PaymentMethod.label(a.paymentMethod),
                ].join(' · ')),
                trailing: a.status == ApptStatus.concluido
                    ? Text(money.format(a.total), style: theme.textTheme.titleSmall)
                    : null,
              ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 100),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(value,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
