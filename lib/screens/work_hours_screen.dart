import 'package:flutter/material.dart';

import '../models.dart';
import '../repository.dart';
import '../util/format.dart';

const _weekdayNames = [
  'Segunda',
  'Terça',
  'Quarta',
  'Quinta',
  'Sexta',
  'Sábado',
  'Domingo',
];

class WorkHoursScreen extends StatefulWidget {
  final VoidCallback onChanged;
  const WorkHoursScreen({super.key, required this.onChanged});

  @override
  State<WorkHoursScreen> createState() => _WorkHoursScreenState();
}

class _WorkHoursScreenState extends State<WorkHoursScreen> {
  List<WorkSlot> _slots = [];
  bool _loading = true;
  bool _busy = false;
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
      final list = await repo.workSlots();
      if (!mounted) return;
      setState(() {
        _slots = list;
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

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      widget.onChanged();
      await _load();
    } catch (_) {
      _snack('Não foi possível salvar. Verifique a internet.');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _add(int weekday) async {
    final t = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: 'Novo horário de ${_weekdayNames[weekday - 1].toLowerCase()}',
    );
    if (t == null || !mounted) return;
    final exists = _slots.any(
        (s) => s.weekday == weekday && s.hour == t.hour && s.minute == t.minute);
    if (exists) {
      _snack('Esse horário já existe.');
      return;
    }
    await _run(() => repo.addWorkSlot(weekday, t.hour, t.minute));
  }

  Future<void> _remove(WorkSlot s) async {
    if (s.id == null) return;
    await _run(() => repo.deleteWorkSlot(s.id!));
  }

  Future<void> _copyFrom(int weekday) async {
    final targets = <int>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Copiar horários de ${_weekdayNames[weekday - 1].toLowerCase()}'),
          content: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Os horários dos dias marcados serão substituídos.'),
              const SizedBox(height: 8),
              for (var d = 1; d <= 7; d++)
                if (d != weekday)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(_weekdayNames[d - 1]),
                    value: targets.contains(d),
                    onChanged: (v) => setLocal(() {
                      v == true ? targets.add(d) : targets.remove(d);
                    }),
                  ),
            ],
          ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Copiar')),
          ],
        ),
      ),
    );
    if (ok == true && targets.isNotEmpty) {
      await _run(() => repo.copyWorkSlots(weekday, _slots, targets.toList()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Horários de trabalho'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: TextButton(onPressed: _load, child: Text(_error!)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                      child: Text(
                        'Estes são os espaços que aparecem como "Livre" na agenda. '
                        'Dia sem horário vira folga. Agendamentos já marcados não mudam.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    for (var d = 1; d <= 7; d++) _dayCard(d, theme),
                  ],
                ),
    );
  }

  Widget _dayCard(int weekday, ThemeData theme) {
    final slots = _slots.where((s) => s.weekday == weekday).toList()
      ..sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(_weekdayNames[weekday - 1],
                    style: theme.textTheme.titleMedium),
                if (slots.isEmpty) ...[
                  const SizedBox(width: 8),
                  Text('folga', style: theme.textTheme.bodySmall),
                ],
                const Spacer(),
                if (slots.isNotEmpty)
                  TextButton.icon(
                    onPressed: _busy ? null : () => _copyFrom(weekday),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copiar'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in slots)
                  InputChip(
                    label: Text(hourLabel(s.hour, s.minute)),
                    onDeleted: _busy ? null : () => _remove(s),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Horário'),
                  onPressed: _busy ? null : () => _add(weekday),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
