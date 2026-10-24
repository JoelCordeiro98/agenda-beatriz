import 'package:flutter/material.dart';

import '../models.dart';
import '../repository.dart';
import '../util/whatsapp.dart';
import '../widgets/client_avatar.dart';

/// Envia uma mensagem (ex.: horários livres) só para clientes cadastradas.
/// Passo 1: escolher as clientes. Passo 2: fila de envio, uma conversa por vez.
class BroadcastScreen extends StatefulWidget {
  final String message;
  final String title;
  const BroadcastScreen({
    super.key,
    required this.message,
    this.title = 'Enviar para clientes',
  });

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  List<Client> _clients = [];
  Map<String, String> _photos = {};
  final Set<String> _selected = {};
  final Set<String> _sent = {};
  bool _onlyRegular = false;
  String _query = '';
  bool _sending = false; // passo 2
  bool _loading = true;
  String? _error;
  late final _text = TextEditingController(text: widget.message);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await repo.clients();
      final withPhone = all.where((c) => waNumber(c.phone) != null).toList();
      final photos = await repo.photoUrls(withPhone.map((c) => c.photoPath));
      if (!mounted) return;
      setState(() {
        _clients = withPhone;
        _photos = photos;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar as clientes. Verifique a internet.';
      });
    }
  }

  List<Client> get _visible {
    final q = _query.trim().toLowerCase();
    return _clients
        .where((c) => !_onlyRegular || c.isRegular)
        .where((c) => q.isEmpty || c.name.toLowerCase().contains(q))
        .toList();
  }

  List<Client> get _queue =>
      _clients.where((c) => _selected.contains(c.id)).toList();

  String _messageFor(Client c) =>
      'Oi, ${firstName(c.name)}! ${_text.text.trim()}';

  Future<void> _send(Client c) async {
    final ok = await openWhatsApp(phone: c.phone, text: _messageFor(c));
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não consegui abrir o WhatsApp.')));
      return;
    }
    setState(() => _sent.add(c.id));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_sending,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _sending = false); // volta para a seleção
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_sending ? 'Enviar mensagens' : widget.title)),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: TextButton(onPressed: _load, child: Text(_error!)))
                : (_sending ? _sendStep() : _selectStep()),
      ),
    );
  }

  // ---------------------------------------------------------------- passo 1

  Widget _selectStep() {
    final theme = Theme.of(context);
    final visible = _visible;
    final allVisibleSelected =
        visible.isNotEmpty && visible.every((c) => _selected.contains(c.id));

    if (_clients.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nenhuma cliente com WhatsApp cadastrado ainda.\n'
            'Cadastre o telefone em Ajustes → Clientes.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'Buscar cliente',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
          child: Row(
            children: [
              Checkbox(
                value: allVisibleSelected,
                onChanged: (v) => setState(() {
                  for (final c in visible) {
                    v == true ? _selected.add(c.id) : _selected.remove(c.id);
                  }
                }),
              ),
              const Text('Selecionar todas'),
              const Spacer(),
              FilterChip(
                label: const Text('Só fixas'),
                selected: _onlyRegular,
                onSelected: (v) => setState(() => _onlyRegular = v),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: visible.length,
            itemBuilder: (_, i) {
              final c = visible[i];
              return CheckboxListTile(
                value: _selected.contains(c.id),
                onChanged: (v) => setState(() {
                  v == true ? _selected.add(c.id) : _selected.remove(c.id);
                }),
                secondary: ClientAvatar(
                  name: c.name,
                  photoUrl: c.photoPath == null ? null : _photos[c.photoPath],
                ),
                title: Row(
                  children: [
                    Flexible(
                        child: Text(c.name, overflow: TextOverflow.ellipsis)),
                    if (c.isRegular) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.star, size: 16, color: Colors.amber),
                    ],
                  ],
                ),
                subtitle: Text(c.phone ?? ''),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('Ver / editar a mensagem',
                      style: theme.textTheme.bodyMedium),
                  children: [
                    TextField(
                      controller: _text,
                      maxLines: 6,
                      minLines: 3,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        helperText: 'Cada cliente recebe "Oi, Nome!" antes do texto.',
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
                FilledButton.icon(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => setState(() => _sending = true),
                  icon: const Icon(Icons.arrow_forward),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_selected.isEmpty
                        ? 'Selecione as clientes'
                        : 'Continuar com ${_selected.length} '
                            '${_selected.length == 1 ? 'cliente' : 'clientes'}'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- passo 2

  Widget _sendStep() {
    final theme = Theme.of(context);
    final queue = _queue;
    final done = queue.where((c) => _sent.contains(c.id)).length;
    final next = queue.where((c) => !_sent.contains(c.id)).firstOrNull;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('$done de ${queue.length} enviadas',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                  value: queue.isEmpty ? 0 : done / queue.length),
              const SizedBox(height: 8),
              Text(
                'Toque em Enviar: o WhatsApp abre com a mensagem pronta. '
                'Envie e volte aqui para a próxima.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: queue.length,
            itemBuilder: (_, i) {
              final c = queue[i];
              final sent = _sent.contains(c.id);
              final isNext = next?.id == c.id;
              return ListTile(
                leading: ClientAvatar(
                  name: c.name,
                  photoUrl: c.photoPath == null ? null : _photos[c.photoPath],
                ),
                title: Text(c.name),
                subtitle: Text(sent ? 'enviada ✓' : c.phone ?? ''),
                trailing: sent
                    ? TextButton(
                        onPressed: () => _send(c),
                        child: const Text('Reenviar'),
                      )
                    : (isNext
                        ? FilledButton.icon(
                            onPressed: () => _send(c),
                            icon: const Icon(Icons.send, size: 18),
                            label: const Text('Enviar'),
                          )
                        : OutlinedButton(
                            onPressed: () => _send(c),
                            child: const Text('Enviar'),
                          )),
              );
            },
          ),
        ),
        if (next == null && queue.isNotEmpty)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Pronto! Voltar para a agenda'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
