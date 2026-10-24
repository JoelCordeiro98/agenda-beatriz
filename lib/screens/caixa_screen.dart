import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../repository.dart';
import '../util/format.dart';
import '../widgets/expense_sheet.dart';

class CaixaScreen extends StatefulWidget {
  const CaixaScreen({super.key});

  @override
  State<CaixaScreen> createState() => _CaixaScreenState();
}

class _CaixaScreenState extends State<CaixaScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  MonthSummary _summary = const MonthSummary();
  List<WeekRevenue> _weeks = [];
  List<Expense> _expenses = [];
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
      final summary = await repo.monthSummary(_month);
      final weeks = await repo.weeksOfMonth(_month);
      final expenses = await repo.expensesOfMonth(_month);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _weeks = weeks;
        _expenses = expenses;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar o caixa. Verifique a internet.';
      });
    }
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
    _load();
  }

  Future<void> _addExpense([String category = ExpenseCategory.material]) async {
    final ok = await showExpenseSheet(context, month: _month, category: category);
    if (ok == true) _load();
  }

  Future<bool> _confirmDelete(Expense e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar despesa?'),
        content: Text('${e.title} — ${money.format(e.amount)}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true) return false;
    try {
      await repo.deleteExpense(e.id);
      _load();
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Não foi possível apagar. Verifique a internet.')));
      }
      return false;
    }
  }

  /// Todas as semanas (segunda a sábado) que tocam o mês, com ou sem atendimento.
  List<WeekRevenue> _allWeeks() {
    final first = _month;
    final last = DateTime(_month.year, _month.month + 1, 0);
    var monday = DateTime(first.year, first.month, first.day - (first.weekday - 1));
    final list = <WeekRevenue>[];
    while (!monday.isAfter(last)) {
      WeekRevenue? found;
      for (final w in _weeks) {
        if (sameDay(w.weekStart, monday)) found = w;
      }
      list.add(found ?? WeekRevenue(monday, 0, 0));
      monday = DateTime(monday.year, monday.month, monday.day + 7);
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final monthTitle =
        capitalize(DateFormat("MMMM 'de' y", 'pt_BR').format(_month));
    return Scaffold(
      appBar: AppBar(title: const Text('Caixa')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addExpense(),
        icon: const Icon(Icons.remove_circle_outline),
        label: const Text('Despesa'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                IconButton(
                    onPressed: () => _changeMonth(-1),
                    icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: Text(monthTitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                    onPressed: () => _changeMonth(1),
                    icon: const Icon(Icons.chevron_right)),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
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

    final theme = Theme.of(context);
    final hasRent = _expenses.any((e) => e.category == ExpenseCategory.aluguel);
    final today = dateOnly(DateTime.now());

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
        children: [
          _ProfitCard(summary: _summary),
          const SizedBox(height: 20),

          // ------------------------------------------------ semanas
          _SectionTitle('Fechamento por semana'),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                for (final w in _allWeeks())
                  _WeekTile(
                    week: w,
                    current: !today.isBefore(w.weekStart) &&
                        today.isBefore(DateTime(w.weekStart.year,
                            w.weekStart.month, w.weekStart.day + 7)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ------------------------------------------------ despesas
          _SectionTitle('Despesas do mês'),
          if (!hasRent)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton.icon(
                onPressed: () => _addExpense(ExpenseCategory.aluguel),
                icon: const Icon(Icons.chair_outlined),
                label: const Text('Lançar o aluguel da mesa deste mês'),
              ),
            ),
          if (_expenses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Nenhuma despesa lançada neste mês.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            )
          else
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest,
              child: Column(
                children: [
                  for (final e in _expenses)
                    Dismissible(
                      key: ValueKey(e.id),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) => _confirmDelete(e),
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: theme.colorScheme.errorContainer,
                        child: Icon(Icons.delete_outline,
                            color: theme.colorScheme.onErrorContainer),
                      ),
                      child: ListTile(
                        leading: Icon(_expenseIcon(e.category)),
                        title: Text(e.title),
                        subtitle: Text(DateFormat('dd/MM').format(e.spentOn)),
                        trailing: Text(money.format(e.amount),
                            style: theme.textTheme.titleSmall),
                        onLongPress: () => _confirmDelete(e),
                      ),
                    ),
                ],
              ),
            ),
          if (_expenses.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text('Arraste para a esquerda para apagar.',
                  style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }

  IconData _expenseIcon(String c) => switch (c) {
        ExpenseCategory.aluguel => Icons.chair_outlined,
        ExpenseCategory.material => Icons.brush_outlined,
        _ => Icons.receipt_long_outlined,
      };
}

// ------------------------------------------------------------------ widgets

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _ProfitCard extends StatelessWidget {
  final MonthSummary summary;
  const _ProfitCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = summary;
    final negative = s.lucro < 0;

    Widget line(String label, double value) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              const Spacer(),
              Text(money.format(value), style: theme.textTheme.bodyMedium),
            ],
          ),
        );

    return Card(
      elevation: 0,
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Lucro do mês', style: theme.textTheme.labelLarge),
            Text(
              money.format(s.lucro),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: negative ? scheme.error : scheme.onPrimaryContainer,
              ),
            ),
            Text('${s.atendimentos} atendimentos concluídos',
                style: theme.textTheme.bodySmall),
            const Divider(height: 24),
            Row(
              children: [
                Text('Faturamento', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(money.format(s.faturamento),
                    style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Despesas', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text('− ${money.format(s.despesas)}',
                    style: theme.textTheme.titleSmall),
              ],
            ),
            if (s.aluguel > 0) line('   Aluguel da mesa', s.aluguel),
            if (s.material > 0) line('   Material', s.material),
            if (s.outros > 0) line('   Outros', s.outros),
          ],
        ),
      ),
    );
  }
}

class _WeekTile extends StatelessWidget {
  final WeekRevenue week;
  final bool current;
  const _WeekTile({required this.week, required this.current});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saturday = DateTime(
        week.weekStart.year, week.weekStart.month, week.weekStart.day + 5);
    final f = DateFormat('dd/MM');
    return ListTile(
      title: Text('${f.format(week.weekStart)} a ${f.format(saturday)}',
          style: current ? const TextStyle(fontWeight: FontWeight.bold) : null),
      subtitle: Text(current
          ? 'Esta semana · ${week.atendimentos} atendimentos'
          : '${week.atendimentos} atendimentos'),
      trailing: Text(money.format(week.faturamento),
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: current ? FontWeight.bold : null)),
    );
  }
}
