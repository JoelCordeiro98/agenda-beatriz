import 'package:flutter/material.dart';

import '../models.dart';
import '../repository.dart';
import '../util/format.dart';
import '../util/whatsapp.dart';
import '../widgets/client_avatar.dart';

/// Lembretes: clientes de um dia (começa em amanhã) com WhatsApp pronto.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  late DateTime _day = () {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + 1);
  }();
  List<Appointment> _appts = [];
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
      final appts = await repo.appointmentsBetween(
          _day, DateTime(_day.year, _day.month, _day.day + 1));
      final open = appts.where((a) => a.status == ApptStatus.agendado).toList();
      final photos = await repo.photoUrls(open.map((a) => a.clientPhotoPath));
      if (!mounted) return;
      setState(() {
        _appts = open;
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

  void _move(int days) {
    setState(() => _day = DateTime(_day.year, _day.month, _day.day + days));
    _load();
  }

  Future<void> _send(Appointment a) async {
    final ok = await openWhatsApp(
      phone: a.clientPhone,
      text: reminderMessage(a, today: DateTime.now()),
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não consegui abrir o WhatsApp.')));
      return;
    }
    try {
      await repo.markReminderSent(a.id);
    } catch (_) {}
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sent = _appts.where((a) => a.reminderSentAt != null).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Lembretes')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                IconButton(
                    onPressed: () => _move(-1),
                    icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: Text(dayTitle(_day),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium),
                ),
                IconButton(
                    onPressed: () => _move(1),
                    icon: const Icon(Icons.chevron_right)),
              ],
            ),
          ),
          if (!_loading && _error == null && _appts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '$sent de ${_appts.length} lembretes enviados',
                style: theme.textTheme.bodySmall,
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
    if (_appts.isEmpty) {
      return const Center(child: Text('Nenhuma cliente agendada neste dia.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      itemCount: _appts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final a = _appts[i];
        final done = a.reminderSentAt != null;
        final hasPhone = waNumber(a.clientPhone) != null;
        return Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest,
          child: ListTile(
            leading: ClientAvatar(
              name: a.clientName,
              photoUrl: a.clientPhotoPath == null
                  ? null
                  : _photos[a.clientPhotoPath],
            ),
            title: Text(a.clientName,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text([
              timeLabel(a.startsAt),
              if (a.items.isNotEmpty) a.servicesLabel,
              if (!hasPhone) 'sem telefone cadastrado',
              if (done) 'lembrete enviado ✓',
            ].join(' · ')),
            trailing: done
                ? TextButton(
                    onPressed: () => _send(a),
                    child: const Text('Reenviar'),
                  )
                : FilledButton.icon(
                    onPressed: () => _send(a),
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('Enviar'),
                  ),
          ),
        );
      },
    );
  }
}
