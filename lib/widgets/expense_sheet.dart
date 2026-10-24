import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../repository.dart';
import '../util/format.dart';

/// Lança uma despesa (aluguel, material ou outro). Retorna true se salvou.
Future<bool?> showExpenseSheet(
  BuildContext context, {
  required DateTime month,
  String category = ExpenseCategory.material,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ExpenseSheet(month: month, initialCategory: category),
  );
}

class _ExpenseSheet extends StatefulWidget {
  final DateTime month;
  final String initialCategory;
  const _ExpenseSheet({required this.month, required this.initialCategory});

  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  late String _category = widget.initialCategory;
  late DateTime _date;
  final _amount = TextEditingController();
  final _description = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final sameMonth =
        now.year == widget.month.year && now.month == widget.month.month;
    _date = sameMonth
        ? dateOnly(now)
        : DateTime(widget.month.year, widget.month.month, 1);
    _suggestAmount();
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  /// No aluguel, já sugere o último valor pago.
  Future<void> _suggestAmount() async {
    if (_category != ExpenseCategory.aluguel || _amount.text.isNotEmpty) return;
    try {
      final last = await repo.lastExpenseAmount(ExpenseCategory.aluguel);
      if (last != null && mounted && _amount.text.isEmpty) {
        setState(() => _amount.text = priceText(last));
      }
    } catch (_) {}
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null && mounted) setState(() => _date = d);
  }

  Future<void> _save() async {
    final amount = parsePrice(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Digite o valor.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await repo.addExpense(
        category: _category,
        amount: amount,
        spentOn: _date,
        description: _description.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nova despesa', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: ExpenseCategory.aluguel,
                    label: Text('Aluguel'),
                    icon: Icon(Icons.chair_outlined)),
                ButtonSegment(
                    value: ExpenseCategory.material,
                    label: Text('Material'),
                    icon: Icon(Icons.brush_outlined)),
                ButtonSegment(
                    value: ExpenseCategory.outro,
                    label: Text('Outro'),
                    icon: Icon(Icons.more_horiz)),
              ],
              selected: {_category},
              onSelectionChanged: (s) {
                setState(() => _category = s.first);
                _suggestAmount();
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Valor',
                prefixText: r'R$ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Descrição (opcional)',
                hintText: _category == ExpenseCategory.material
                    ? 'Ex.: esmaltes, gel, lixas'
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event),
              label: Text(DateFormat('dd/MM/yyyy').format(_date)),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.all(16),
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
                child: Text(_saving ? 'Salvando…' : 'Lançar despesa'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
