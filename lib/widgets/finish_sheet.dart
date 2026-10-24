import 'package:flutter/material.dart';

import '../models.dart';
import '../repository.dart';
import '../util/format.dart';
import '../util/photo_picker.dart';

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
  late String _payment = widget.appt.paymentMethod ?? PaymentMethod.pix;
  PickedPhoto? _nailPhoto;
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
      await repo.finishAppointment(widget.appt.id, values,
          extraPrice: extra, paymentMethod: _payment);
      if (_nailPhoto != null) {
        try {
          await repo.setNailPhoto(widget.appt.id, _nailPhoto!.bytes,
              mimeType: _nailPhoto!.mimeType,
              oldPath: widget.appt.nailPhotoPath);
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Atendimento salvo, mas a foto não foi enviada.')));
          }
        }
      }
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
            const SizedBox(height: 16),
            Text('Como pagou', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in PaymentMethod.all)
                  ChoiceChip(
                    label: Text(PaymentMethod.label(m)),
                    selected: _payment == m,
                    onSelected: (_) => setState(() => _payment = m),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _saving
                  ? null
                  : () async {
                      try {
                        final p = await pickPhoto(context);
                        if (p != null && mounted) setState(() => _nailPhoto = p);
                      } catch (_) {
                        if (mounted) {
                          setState(() => _error =
                              'Não foi possível abrir a câmera ou a galeria.');
                        }
                      }
                    },
              icon: Icon(_nailPhoto != null
                  ? Icons.check_circle
                  : Icons.add_a_photo_outlined),
              label: Text(_nailPhoto != null
                  ? 'Foto das unhas adicionada'
                  : (a.nailPhotoPath != null
                      ? 'Trocar foto das unhas'
                      : 'Foto das unhas (opcional)')),
            ),
            if (_nailPhoto != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(_nailPhoto!.bytes,
                    height: 140, fit: BoxFit.cover),
              ),
            ],
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
