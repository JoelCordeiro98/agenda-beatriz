import 'package:flutter/material.dart';

import 'agenda_screen.dart';
import 'ajustes_screen.dart';
import 'caixa_screen.dart';

/// Abas do app: Agenda, Caixa e Ajustes.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _caixaVersion = 0; // muda ao abrir o Caixa, para recarregar os números
  int _agendaVersion = 0; // muda quando serviços/horários foram alterados
  bool _agendaDirty = false;

  void _select(int i) {
    setState(() {
      if (i == 0 && _agendaDirty) {
        _agendaVersion++;
        _agendaDirty = false;
      }
      if (i == 1 && _index != 1) _caixaVersion++;
      _index = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          AgendaScreen(key: ValueKey('agenda$_agendaVersion')),
          CaixaScreen(key: ValueKey('caixa$_caixaVersion')),
          AjustesScreen(onChanged: () => _agendaDirty = true),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Agenda',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Caixa',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }
}
