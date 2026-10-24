import 'package:flutter/material.dart';

import '../models.dart';
import '../repository.dart';
import '../util/format.dart';

/// Abre o formulário de agendamento. Retorna a data/hora salva, ou null.
Future<DateTime?> showNewAppointmentSheet(
  BuildContext context, {
  required DateTime initialDateTime,
  required List<Client> clients,
  required List<Service> services,
  String? clientName,
  String? clientId,
  List<String> serviceIds = const [],
  String title = 'Novo agendamento',
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _NewAppointmentSheet(
      initialDateTime: initialDateTime,
      clients: clients,
      services: services,
      clientName: clientName,
      clientId: clientId,
      serviceIds: serviceIds,
      title: title,
    ),
  );
}

class _NewAppointmentSheet extends StatefulWidget {
  final DateTime initialDateTime;
  final List<Client> clients;
  final List<Service> services;
  final String? clientName;
  final String? clientId;
  final List<String> serviceIds;
  final String title;

  const _NewAppointmentSheet({
    required this.initialDateTime,
    required this.clients,
    required this.services,
    this.clientName,
    this.clientId,
    required this.serviceIds,
    required this.title,
  });

  @override
  State<_NewAppointmentSheet> createState() => _NewAppointmentSheetState();
}

class _NewAppointmentSheetState extends State<_NewAppointmentSheet> {
  late DateTime _when = widget.initialDateTime;
  late final Set<String> _selected = {...widget.serviceIds};
  final _notes = TextEditingController();
  TextEditingController? _name; // vem do Autocomplete
  Client? _selectedClient;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in widget.clients) {
      if (c.id == widget.clientId) _selectedClient = c;
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickWhen() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (t == null || !mounted) return;
    setState(() => _when = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Client? _findByName(String name) {
    final n = name.toLowerCase();
    for (final c in widget.clients) {
      if (c.name.toLowerCase() == n) return c;
    }
    return null;
  }

  Future<void> _save() async {
    final name = _name?.text.trim() ?? '';
    if (name.isEmpty) {
      setState(() => _error = 'Digite o nome da cliente.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final picked = _selectedClient;
      final client =
          (picked != null && picked.name == name) ? picked : _findByName(name);
      await repo.createAppointment(
        clientId: client?.id,
        clientName: client?.name ?? name,
        startsAt: _when,
        services:
            widget.services.where((s) => _selected.contains(s.id)).toList(),
        notes: _notes.text.trim(),
      );
      if (mounted) Navigator.pop(context, _when);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Não foi possível salvar. Verifique a internet.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = widget.services
        .where((s) => _selected.contains(s.id))
        .fold(0.0, (sum, s) => sum + s.defaultPrice);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),

            // Data e hora
            OutlinedButton.icon(
              onPressed: _pickWhen,
              icon: const Icon(Icons.event),
              label: Text(shortDateTime(_when)),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 12),

            // Cliente (sugere as já cadastradas)
            Autocomplete<Client>(
              initialValue: TextEditingValue(text: widget.clientName ?? ''),
              displayStringForOption: (c) => c.name,
              optionsBuilder: (value) {
                final q = value.text.trim().toLowerCase();
                if (q.isEmpty) return const Iterable<Client>.empty();
                return widget.clients
                    .where((c) => c.name.toLowerCase().contains(q));
              },
              onSelected: (c) => setState(() => _selectedClient = c),
              fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                _name = controller;
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Cliente',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // Serviços
            Text('O que vai fazer', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (widget.services.isEmpty)
              Text(
                'Nenhum serviço cadastrado ainda. Dá pra agendar assim mesmo e lançar o valor no fim do dia.',
                style: theme.textTheme.bodySmall,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in widget.services)
                    FilterChip(
                      label: Text('${s.name} · ${money.format(s.defaultPrice)}'),
                      selected: _selected.contains(s.id),
                      onSelected: (on) => setState(() {
                        on ? _selected.add(s.id) : _selected.remove(s.id);
                      }),
                    ),
                ],
              ),
            if (_selected.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Previsto: ${money.format(total)}',
                  style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 16),

            TextField(
              controller: _notes,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Observação (opcional)',
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
                child: Text(_saving ? 'Salvando…' : 'Agendar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
