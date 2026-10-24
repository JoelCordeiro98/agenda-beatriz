import 'package:flutter/material.dart';

import '../models.dart';
import '../repository.dart';
import '../util/format.dart';

/// Lança os valores cobrados e marca o atendimento como concluído.
/// Retorna true se salvou.
Future<bool?> showFinishSheet(BuildContext context, Appointment appt) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _FinishSheet(appt: appt),
  );
}

class _FinishSheet extends StatefulWidget {
  final Appointment appt;
  const _FinishSheet({required this.appt});

  @override
  State<_FinishSheet> createState() => _FinishSheetState();
}

class _FinishSheetState extends State<_FinishSheet> {
  late final Map<String, TextEditingController> _prices = {
    for (final i in widget.appt.items)
      i.id: TextEditingController(text: priceText(i.price)),
  };
  final _extra = TextEditingController(); // quando não tem serviço escolhido
  bool _saving = false;
  String? _error;

  bool get _noItems => widget.appt.items.isEmpty;

  @override
  void dispose() {
    for (final c in _prices.values) {
      c.dispose();
    }
    _extra.dispose();
    super.dispose();
  }

  double get _total {
    if (_noItems) return parsePrice(_extra.text) ?? 0;
    return _prices.values.fold(0.0, (s, c) => s + (parsePrice(c.text) ?? 0));
  }

  Future<void> _save() async {
    final values = <String, double>{};
    for (final e in _prices.entries) {
      final v = parsePrice(e.value.text);
      if (v == null) {
        setState(() => _error = 'Confira os valores digitados.');
        return;
      }
      values[e.key] = v;
    }
    double? extra;
    if (_noItems) {
      extra = parsePrice(_extra.text);
      if (extra == null) {
        setState(() => _error = 'Digite o valor do atendimento.');
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await repo.finishAppointment(widget.appt.id, values, extraPrice: extra);
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

  Widget _priceField(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          prefixText: r'R$ ',
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = widget.appt;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(a.clientName, style: theme.textTheme.titleLarge),
            Text(shortDateTime(a.startsAt), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            if (_noItems)
              _priceField(_extra, 'Valor do atendimento')
            else
              for (final i in a.items) _priceField(_prices[i.id]!, i.serviceName),
            Row(
              children: [
                Text('Total', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(money.format(_total), style: theme.textTheme.titleLarge),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_saving ? 'Salvando…' : 'Concluir atendimento'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
