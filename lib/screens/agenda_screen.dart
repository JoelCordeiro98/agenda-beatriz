import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../repository.dart';
import '../util/format.dart';
import '../util/photo_picker.dart';
import '../util/whatsapp.dart';
import '../widgets/finish_sheet.dart';
import '../widgets/client_avatar.dart';
import '../widgets/new_appointment_sheet.dart';
import 'broadcast_screen.dart';
import 'client_detail_screen.dart';
import 'overdue_screen.dart';
import 'reminders_screen.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

/// Uma linha da agenda: um horário livre, ocupado ou bloqueado.
class _Entry {
  final DateTime time;
  final Appointment? appt;
  final Block? block;
  const _Entry(this.time, this.appt, [this.block]);
}

class _AgendaScreenState extends State<AgendaScreen> {
  DateTime _day = dateOnly(DateTime.now());
  List<WorkSlot> _slots = [];
  List<Service> _services = [];
  List<Appointment> _appts = [];
  Map<String, String> _photos = {};
  List<Block> _blocks = [];
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
      final blocks = await repo.blocksBetween(
          _day, DateTime(_day.year, _day.month, _day.day + 1));
      if (!mounted) return;
      setState(() {
        _appts = appts;
        _photos = photos;
        _blocks = blocks;
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

  Block? get _dayBlock {
    for (final b in _blocks) {
      if (b.wholeDay) return b;
    }
    return null;
  }

  Block? _slotBlock(int hour, int minute) {
    for (final b in _blocks) {
      if (!b.wholeDay && b.hour == hour && b.minute == minute) return b;
    }
    return null;
  }

  List<_Entry> _entries() {
    final used = <String>{};
    final list = <_Entry>[];
    final dayBlocked = _dayBlock != null;

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
      if (match == null && dayBlocked) continue; // dia bloqueado: some com os livres
      list.add(_Entry(t, match, match == null ? _slotBlock(s.hour, s.minute) : null));
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

  // ---------------------------------------------------------------- bloqueios

  Future<String?> _askReason(String title) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Motivo (opcional)',
            hintText: 'Ex.: feriado, médico, viagem',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Bloquear')),
        ],
      ),
    );
    final text = c.text.trim();
    c.dispose();
    return ok == true ? text : null;
  }

  Future<void> _blockDay() async {
    final reason = await _askReason('Bloquear ${dayTitle(_day).toLowerCase()}?');
    if (reason == null) return;
    try {
      await repo.addBlock(_day, reason: reason);
      _load();
    } catch (_) {
      _snack('Não foi possível bloquear. Rode o features.sql no Supabase.');
    }
  }

  Future<void> _blockSlot(DateTime t) async {
    final reason = await _askReason('Bloquear ${timeLabel(t)}?');
    if (reason == null) return;
    try {
      await repo.addBlock(_day, hour: t.hour, minute: t.minute, reason: reason);
      _load();
    } catch (_) {
      _snack('Não foi possível bloquear. Rode o features.sql no Supabase.');
    }
  }

  Future<void> _unblock(Block b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(b.wholeDay ? 'Desbloquear o dia?' : 'Desbloquear o horário?'),
        content: b.reason == null ? null : Text('Motivo: ${b.reason}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Desbloquear')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await repo.deleteBlock(b.id);
      _load();
    } catch (_) {
      _snack('Não foi possível salvar. Verifique a internet.');
    }
  }

  Future<void> _blockMenu() async {
    if (_dayBlock != null) {
      await _unblock(_dayBlock!);
      return;
    }
    final free = _entries().where((e) => e.appt == null && e.block == null).toList();
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(dayTitle(_day), style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.pop(ctx, 'day'),
                icon: const Icon(Icons.block),
                label: const Text('Bloquear o dia inteiro'),
              ),
              if (free.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Ou só um horário:'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in free)
                      ActionChip(
                        label: Text(hourLabel(e.time.hour, e.time.minute)),
                        onPressed: () => Navigator.pop(ctx, e.time),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'day') await _blockDay();
    if (choice is DateTime) await _blockSlot(choice);
  }

  // ---------------------------------------------------------------- atalhos

  Future<void> _openPage(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) _load();
  }

  Future<void> _remind(Appointment a) async {
    final ok = await openWhatsApp(
        phone: a.clientPhone, text: reminderMessage(a, today: DateTime.now()));
    if (!ok) {
      _snack('Não consegui abrir o WhatsApp.');
      return;
    }
    try {
      await repo.markReminderSent(a.id);
    } catch (_) {}
    _load();
  }

  Future<void> _nailPhoto(Appointment a) async {
    try {
      final p = await pickPhoto(context);
      if (p == null) return;
      await repo.setNailPhoto(a.id, p.bytes,
          mimeType: p.mimeType, oldPath: a.nailPhotoPath);
      _snack('Foto salva na ficha da cliente');
      _load();
    } catch (_) {
      _snack('Não foi possível salvar a foto.');
    }
  }

  Future<void> _received(Appointment a) async {
    final method = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('${a.clientName} pagou como?'),
        children: [
          for (final m in [
            PaymentMethod.pix,
            PaymentMethod.dinheiro,
            PaymentMethod.cartao,
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m),
              child: Text(PaymentMethod.label(m)),
            ),
        ],
      ),
    );
    if (method == null) return;
    try {
      await repo.setPayment(a.id, method);
      _load();
    } catch (_) {
      _snack('Não foi possível salvar. Verifique a internet.');
    }
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
            if (a.status == ApptStatus.agendado)
              ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: Text(a.reminderSentAt == null
                    ? 'Enviar lembrete no WhatsApp'
                    : 'Reenviar lembrete (já enviado)'),
                onTap: () => Navigator.pop(ctx, 'remind'),
              ),
            if (a.status == ApptStatus.concluido && a.isPending)
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('Recebi o pagamento'),
                onTap: () => Navigator.pop(ctx, 'paid'),
              ),
            if (a.status == ApptStatus.concluido)
              ListTile(
                leading: const Icon(Icons.add_a_photo_outlined),
                title: Text(a.nailPhotoPath == null
                    ? 'Foto das unhas'
                    : 'Trocar foto das unhas'),
                onTap: () => Navigator.pop(ctx, 'nails'),
              ),
            if (a.clientId != null)
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Ver ficha da cliente'),
                onTap: () => Navigator.pop(ctx, 'client'),
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
      case 'remind':
        await _remind(a);
      case 'paid':
        await _received(a);
      case 'nails':
        await _nailPhoto(a);
      case 'client':
        await _openPage(ClientDetailScreen(clientId: a.clientId!));
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
      final weekEnd = DateTime(monday.year, monday.month, monday.day + 7);
      final blocks = await repo.blocksBetween(monday, weekEnd);
      text = freeSlotsText(monday, _slots, appts, DateTime.now(), blocks: blocks);
    } catch (_) {
      _snack('Sem conexão. Tente de novo.');
      return;
    }
    if (!mounted) return;

    final controller = TextEditingController(text: text);
    final choice = await showDialog<String>(
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
          TextButton.icon(
            icon: const Icon(Icons.chat_outlined),
            label: const Text('Outro contato'),
            onPressed: () async {
              final uri = Uri.parse(
                  'https://wa.me/?text=${Uri.encodeComponent(controller.text)}');
              final ok =
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (!ok) _snack('Não consegui abrir o WhatsApp. Use "Copiar".');
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.people_outline),
            label: const Text('Escolher clientes'),
            onPressed: () => Navigator.pop(ctx, 'clients'),
          ),
        ],
      ),
    );
    final message = controller.text;
    controller.dispose();
    if (choice == 'clients' && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BroadcastScreen(
          message: message,
          title: 'Enviar horários livres',
        ),
      ));
    }
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
            tooltip: 'Lembretes de amanhã',
            icon: const Icon(Icons.notifications_active_outlined),
            onPressed: () => _openPage(const RemindersScreen()),
          ),
          IconButton(
            tooltip: 'Enviar horários livres da semana',
            icon: const Icon(Icons.share_outlined),
            onPressed: _setupDone ? _shareFreeSlots : null,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'overdue':
                  _openPage(const OverdueScreen());
                case 'block':
                  _blockMenu();
                case 'logout':
                  Supabase.instance.client.auth.signOut();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'overdue',
                child: ListTile(
                  leading: Icon(Icons.person_search_outlined),
                  title: Text('Clientes sumidas'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'block',
                enabled: _setupDone,
                child: ListTile(
                  leading: const Icon(Icons.block),
                  title: Text(_dayBlock == null
                      ? 'Bloquear dia ou horário'
                      : 'Desbloquear este dia'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Sair'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
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
    final dayBlock = _dayBlock;
    if (entries.isEmpty && dayBlock == null) {
      return const Center(child: Text('Dia de folga 🌿'));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        children: [
          if (dayBlock != null)
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.block),
                title: const Text('Dia bloqueado'),
                subtitle: dayBlock.reason == null ? null : Text(dayBlock.reason!),
                trailing: TextButton(
                  onPressed: () => _unblock(dayBlock),
                  child: const Text('Desbloquear'),
                ),
              ),
            ),
          for (final e in entries) ...[
            const SizedBox(height: 8),
            if (e.appt != null)
              _AppointmentTile(
                appt: e.appt!,
                photoUrl: _photoOf(e.appt!),
                onTap: () => _openActions(e.appt!),
              )
            else if (e.block != null)
              _BlockedTile(
                time: e.time,
                reason: e.block!.reason,
                onTap: () => _unblock(e.block!),
              )
            else
              _FreeSlotTile(
                time: e.time,
                onTap: () => _newAppointment(at: e.time),
                onLongPress: () => _blockSlot(e.time),
              ),
          ],
        ],
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
  final VoidCallback? onLongPress;
  const _FreeSlotTile({
    required this.time,
    required this.onTap,
    this.onLongPress,
  });

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
        onLongPress: onLongPress,
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
      ApptStatus.concluido when appt.isPending =>
        ('A receber', Colors.orange.shade100, Colors.orange.shade900),
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

class _BlockedTile extends StatelessWidget {
  final DateTime time;
  final String? reason;
  final VoidCallback onTap;
  const _BlockedTile({required this.time, required this.onTap, this.reason});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TimeText(time, color: scheme.onSurfaceVariant),
            SizedBox(
              width: 40,
              child: Icon(Icons.block, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        title: Text('Bloqueado',
            style: TextStyle(color: scheme.onSurfaceVariant)),
        subtitle: Text(reason ?? 'Toque para desbloquear'),
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
