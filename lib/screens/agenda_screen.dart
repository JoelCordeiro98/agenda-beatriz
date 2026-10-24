import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../repository.dart';
import '../util/format.dart';
import '../widgets/finish_sheet.dart';
import '../widgets/client_avatar.dart';
import '../widgets/new_appointment_sheet.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

/// Uma linha da agenda: um horário, livre ou ocupado.
class _Entry {
  final DateTime time;
  final Appointment? appt;
  const _Entry(this.time, this.appt);
}

class _AgendaScreenState extends State<AgendaScreen> {
  DateTime _day = dateOnly(DateTime.now());
  List<WorkSlot> _slots = [];
  List<Service> _services = [];
  List<Appointment> _appts = [];
  Map<String, String> _photos = {};
  bool _loading = true;
  bool _setupDone = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ---------------------------------------------------------------- dados

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!_setupDone) {
        _slots = await repo.workSlots();
        await repo.ensureDefaultServices();
        _services = await repo.services();
        _setupDone = true;
      }
      final appts = await repo.appointmentsBetween(
        _day,
        DateTime(_day.year, _day.month, _day.day + 1),
      );
      final photos = await repo.photoUrls(appts.map((a) => a.clientPhotoPath));
      if (!mounted) return;
      setState(() {
        _appts = appts;
        _photos = photos;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar a agenda. Verifique a internet.';
      });
    }
  }

  void _goTo(DateTime day) {
    setState(() => _day = dateOnly(day));
    _load();
  }

  List<_Entry> _entries() {
    final used = <String>{};
    final list = <_Entry>[];

    for (final s in _slots.where((s) => s.weekday == _day.weekday)) {
      final t = DateTime(_day.year, _day.month, _day.day, s.hour, s.minute);
      Appointment? match;
      for (final a in _appts) {
        if (!used.contains(a.id) &&
            a.startsAt.hour == s.hour &&
            a.startsAt.minute == s.minute) {
          match = a;
          break;
        }
      }
      if (match != null) used.add(match.id);
      list.add(_Entry(t, match));
    }

    // Encaixes fora dos horários fixos
    for (final a in _appts) {
      if (!used.contains(a.id)) list.add(_Entry(a.startsAt, a));
    }

    list.sort((a, b) => a.time.compareTo(b.time));
    return list;
  }

  // ---------------------------------------------------------------- ações

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _newAppointment({
    required DateTime at,
    String? clientName,
    String? clientId,
    List<String> serviceIds = const [],
    String title = 'Novo agendamento',
  }) async {
    List<Client> clients;
    try {
      clients = await repo.clients();
    } catch (_) {
      _snack('Sem conexão. Tente de novo.');
      return;
    }
    if (!mounted) return;

    final saved = await showNewAppointmentSheet(
      context,
      initialDateTime: at,
      clients: clients,
      services: _services,
      clientName: clientName,
      clientId: clientId,
      serviceIds: serviceIds,
      title: title,
    );
    if (saved == null || !mounted) return;

    if (!sameDay(saved, _day)) {
      _snack('Agendado para ${shortDateTime(saved)}');
    }
    _load();
  }

  Future<void> _addEncaixe() async {
    final t = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: 'Horário do encaixe',
    );
    if (t == null || !mounted) return;
    await _newAppointment(
      at: DateTime(_day.year, _day.month, _day.day, t.hour, t.minute),
      title: 'Encaixe',
    );
  }

  Future<void> _finish(Appointment a) async {
    final wasOpen = a.status == ApptStatus.agendado;
    final ok = await showFinishSheet(context, a);
    if (ok != true || !mounted) return;
    await _load();
    if (!wasOpen || !mounted) return;

    final again = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deixar o retorno agendado?'),
        content: Text('Agendar a próxima manutenção de ${a.clientName}.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Agora não')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Agendar')),
        ],
      ),
    );
    if (again == true && mounted) await _scheduleReturn(a);
  }

  /// Sugere o retorno no mesmo dia da semana e horário, arredondando o
  /// intervalo da cliente para semanas (30 dias -> 4 semanas).
  Future<void> _scheduleReturn(Appointment a) async {
    var interval = 30;
    if (a.clientId != null) {
      try {
        final c = await repo.client(a.clientId!);
        if (c != null) interval = c.intervalDays;
      } catch (_) {}
    }
    final weeks = max(1, (interval / 7).round());
    final s = a.startsAt;
    final next = DateTime(s.year, s.month, s.day + weeks * 7, s.hour, s.minute);
    if (!mounted) return;
    await _newAppointment(
      at: next,
      clientName: a.clientName,
      clientId: a.clientId,
      serviceIds: a.items.map((i) => i.serviceId).whereType<String>().toList(),
      title: 'Retorno de ${a.clientName}',
    );
  }

  Future<void> _setStatus(Appointment a, String status) async {
    try {
      await repo.setStatus(a.id, status);
      await _load();
    } catch (_) {
      _snack('Não foi possível salvar. Verifique a internet.');
    }
  }

  Future<void> _cancel(Appointment a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desmarcar horário?'),
        content: Text(
            '${a.clientName} — ${shortDateTime(a.startsAt)}.\nO horário volta a ficar livre.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Desmarcar')),
        ],
      ),
    );
    if (ok == true) await _setStatus(a, ApptStatus.cancelado);
  }

  String? _photoOf(Appointment a) =>
      a.clientPhotoPath == null ? null : _photos[a.clientPhotoPath];

  Future<void> _openActions(Appointment a) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: ClientAvatar(
                name: a.clientName,
                photoUrl: _photoOf(a),
                radius: 28,
              ),
              title: Text(a.clientName,
                  style: Theme.of(ctx).textTheme.titleMedium),
              subtitle: Text([
                shortDateTime(a.startsAt),
                if (a.items.isNotEmpty) a.servicesLabel,
                if (a.notes != null && a.notes!.isNotEmpty) a.notes!,
              ].join('\n')),
            ),
            const Divider(),
            if (a.status == ApptStatus.agendado)
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('Concluir e lançar valor'),
                onTap: () => Navigator.pop(ctx, 'finish'),
              ),
            if (a.status == ApptStatus.concluido)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Corrigir valores'),
                onTap: () => Navigator.pop(ctx, 'finish'),
              ),
            ListTile(
              leading: const Icon(Icons.event_repeat),
              title: const Text('Agendar retorno'),
              onTap: () => Navigator.pop(ctx, 'return'),
            ),
            if (a.status == ApptStatus.agendado)
              ListTile(
                leading: const Icon(Icons.person_off_outlined),
                title: const Text('Cliente faltou'),
                onTap: () => Navigator.pop(ctx, 'noshow'),
              ),
            if (a.status != ApptStatus.agendado)
              ListTile(
                leading: const Icon(Icons.undo),
                title: const Text('Voltar para agendado'),
                onTap: () => Navigator.pop(ctx, 'reopen'),
              ),
            ListTile(
              leading: const Icon(Icons.event_busy),
              title: const Text('Desmarcar'),
              onTap: () => Navigator.pop(ctx, 'cancel'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;

    switch (action) {
      case 'finish':
        await _finish(a);
      case 'return':
        await _scheduleReturn(a);
      case 'noshow':
        await _setStatus(a, ApptStatus.faltou);
      case 'reopen':
        await _setStatus(a, ApptStatus.agendado);
      case 'cancel':
        await _cancel(a);
    }
  }

  Future<void> _shareFreeSlots() async {
    final monday = DateTime(_day.year, _day.month, _day.day - (_day.weekday - 1));
    String text;
    try {
      final appts = await repo.appointmentsBetween(
        monday,
        DateTime(monday.year, monday.month, monday.day + 7),
      );
      text = freeSlotsText(monday, _slots, appts, DateTime.now());
    } catch (_) {
      _snack('Sem conexão. Tente de novo.');
      return;
    }
    if (!mounted) return;

    final controller = TextEditingController(text: text);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Horários livres'),
        content: TextField(
          controller: controller,
          maxLines: null,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copiar'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: controller.text));
              if (ctx.mounted) Navigator.pop(ctx);
              _snack('Texto copiado');
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.send),
            label: const Text('WhatsApp'),
            onPressed: () async {
              final uri = Uri.parse(
                  'https://wa.me/?text=${Uri.encodeComponent(controller.text)}');
              final ok =
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (!ok) _snack('Não consegui abrir o WhatsApp. Use "Copiar".');
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
    controller.dispose();
  }

  // ---------------------------------------------------------------- tela

  @override
  Widget build(BuildContext context) {
    final isToday = sameDay(_day, DateTime.now());
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda'),
        actions: [
          if (!isToday)
            TextButton(
                onPressed: () => _goTo(DateTime.now()),
                child: const Text('Hoje')),
          IconButton(
            tooltip: 'Enviar horários livres da semana',
            icon: const Icon(Icons.share_outlined),
            onPressed: _setupDone ? _shareFreeSlots : null,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'logout') Supabase.instance.client.auth.signOut();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'logout', child: Text('Sair')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _setupDone ? _addEncaixe : null,
        icon: const Icon(Icons.add),
        label: const Text('Encaixe'),
      ),
      body: Column(
        children: [
          _DayHeader(
            day: _day,
            onPrev: () => _goTo(DateTime(_day.year, _day.month, _day.day - 1)),
            onNext: () => _goTo(DateTime(_day.year, _day.month, _day.day + 1)),
            onPick: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _day,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 730)),
              );
              if (d != null) _goTo(d);
            },
          ),
          Expanded(child: _body()),
        ],
      ),
      bottomNavigationBar:
          (!_loading && _error == null) ? _DaySummary(appts: _appts) : null,
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Tentar de novo')),
            ],
          ),
        ),
      );
    }

    final entries = _entries();
    if (entries.isEmpty) {
      return const Center(child: Text('Dia de folga 🌿'));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final e = entries[i];
          final appt = e.appt;
          return appt == null
              ? _FreeSlotTile(
                  time: e.time,
                  onTap: () => _newAppointment(at: e.time),
                )
              : _AppointmentTile(
                  appt: appt,
                  photoUrl: _photoOf(appt),
                  onTap: () => _openActions(appt),
                );
        },
      ),
    );
  }
}

// ------------------------------------------------------------------ widgets

class _DayHeader extends StatelessWidget {
  final DateTime day;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPick;

  const _DayHeader({
    required this.day,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: TextButton(
              onPressed: onPick,
              child: Text(dayTitle(day),
                  style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
          IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
        ],
      ),
    );
  }
}

class _FreeSlotTile extends StatelessWidget {
  final DateTime time;
  final VoidCallback onTap;
  const _FreeSlotTile({required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final past = time.isBefore(DateTime.now());
    return Card(
      elevation: 0,
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TimeText(time, color: scheme.onSurfaceVariant),
            const SizedBox(width: 40),
          ],
        ),
        title: Text('Livre',
            style: TextStyle(color: scheme.onSurfaceVariant)),
        subtitle: past ? null : const Text('Toque para agendar'),
        trailing: Icon(Icons.add_circle_outline, color: scheme.primary),
      ),
    );
  }
}

class _AppointmentTile extends StatelessWidget {
  final Appointment appt;
  final String? photoUrl;
  final VoidCallback onTap;
  const _AppointmentTile({
    required this.appt,
    required this.onTap,
    this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, bg, fg) = switch (appt.status) {
      ApptStatus.concluido => ('Concluído', Colors.green.shade100, Colors.green.shade900),
      ApptStatus.faltou => ('Faltou', Colors.orange.shade100, Colors.orange.shade900),
      _ => ('Agendado', scheme.primaryContainer, scheme.onPrimaryContainer),
    };

    final details = [
      if (appt.items.isNotEmpty) appt.servicesLabel,
      if (appt.items.isNotEmpty) money.format(appt.total),
    ].join(' · ');

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TimeText(appt.startsAt, color: scheme.primary),
            ClientAvatar(name: appt.clientName, photoUrl: photoUrl),
          ],
        ),
        title: Text(appt.clientName,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: details.isEmpty ? null : Text(details),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(20)),
          child: Text(label, style: TextStyle(color: fg, fontSize: 12)),
        ),
      ),
    );
  }
}

class _TimeText extends StatelessWidget {
  final DateTime time;
  final Color color;
  const _TimeText(this.time, {required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      child: Text(
        timeLabel(time),
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _DaySummary extends StatelessWidget {
  final List<Appointment> appts;
  const _DaySummary({required this.appts});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = appts.where((a) => a.status == ApptStatus.concluido);
    final open = appts.where((a) => a.status == ApptStatus.agendado);
    final received = done.fold(0.0, (s, a) => s + a.total);
    final expected = received + open.fold(0.0, (s, a) => s + a.total);

    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Total do dia', style: theme.textTheme.labelMedium),
                    Text(money.format(received),
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${done.length} de ${appts.length} atendimentos',
                      style: theme.textTheme.labelMedium),
                  if (expected > received)
                    Text('Previsto: ${money.format(expected)}',
                        style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
