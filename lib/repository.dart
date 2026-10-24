import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// Todo o acesso ao Supabase fica aqui.
class Repo {
  SupabaseClient get db => Supabase.instance.client;

  // Horários padrão: 2 pela manhã e 3 à tarde, de segunda a sábado.
  static const _defaultTimes = ['08:00', '10:00', '13:00', '15:00', '17:00'];

  Future<List<WorkSlot>> workSlots() async {
    var rows = await db.from('work_slots').select().order('start_time');
    if (rows.isEmpty) {
      // Primeiro uso: cria os horários padrão (depois ela ajusta em Ajustes).
      await db.from('work_slots').insert([
        for (var day = 1; day <= 6; day++)
          for (final t in _defaultTimes) {'weekday': day, 'start_time': t},
      ]);
      rows = await db.from('work_slots').select().order('start_time');
    }
    return rows.map(WorkSlot.fromMap).toList();
  }

  // Tabela de preços da Beatriz: usada para preencher uma conta nova.
  static const _defaultServices = [
    ('Aplicação em gel', 110.0, 150),
    ('Manutenção', 90.0, 120),
    ('Banho de gel', 90.0, 90),
    ('Esmaltação em gel', 50.0, 60),
    ('Pé e mão normal', 45.0, 90),
    ('Só mão', 25.0, 45),
    ('Só pé', 25.0, 45),
    ('Aplicação de postiça', 30.0, 60),
    ('Remoção do gel', 30.0, 30),
    ('Reposição de unha', 10.0, 15),
    ('Mudança de formato', 10.0, 15),
    ('Decoração mais elaborada', 10.0, 20),
  ];

  /// Conta nova (sem nenhum serviço, nem escondido): cadastra a tabela padrão.
  Future<void> ensureDefaultServices() async {
    final any = await db.from('services').select('id').limit(1);
    if (any.isNotEmpty) return;
    await db.from('services').insert([
      for (final (name, price, minutes) in _defaultServices)
        {'name': name, 'default_price': price, 'duration_min': minutes},
    ]);
  }

  Future<List<Service>> services() async {
    final rows =
        await db.from('services').select().eq('active', true).order('name');
    return rows.map(Service.fromMap).toList();
  }

  Future<List<Client>> clients() async {
    final rows = await db.from('clients').select().order('name');
    return rows.map(Client.fromMap).toList();
  }

  Future<Client?> client(String id) async {
    final row = await db.from('clients').select().eq('id', id).maybeSingle();
    return row == null ? null : Client.fromMap(row);
  }

  /// Atendimentos (menos os desmarcados) entre [start] e [end], em horário local.
  Future<List<Appointment>> appointmentsBetween(
      DateTime start, DateTime end) async {
    final rows = await db
        .from('appointments')
        .select('*, appointment_services(*), clients(photo_path, phone)')
        .gte('starts_at', start.toUtc().toIso8601String())
        .lt('starts_at', end.toUtc().toIso8601String())
        .neq('status', ApptStatus.cancelado)
        .order('starts_at');
    return rows.map(Appointment.fromMap).toList();
  }

  /// Cria o agendamento. Se a cliente ainda não existe, cadastra na hora.
  Future<void> createAppointment({
    String? clientId,
    required String clientName,
    required DateTime startsAt,
    required List<Service> services,
    String? notes,
  }) async {
    var id = clientId;
    if (id == null) {
      final c = await db
          .from('clients')
          .insert({'name': clientName})
          .select()
          .single();
      id = c['id'] as String;
    }

    final appt = await db
        .from('appointments')
        .insert({
          'client_id': id,
          'client_name': clientName,
          'starts_at': startsAt.toUtc().toIso8601String(),
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        })
        .select()
        .single();

    if (services.isNotEmpty) {
      await db.from('appointment_services').insert([
        for (final s in services)
          {
            'appointment_id': appt['id'],
            'service_id': s.id,
            'service_name': s.name,
            'price': s.defaultPrice,
          },
      ]);
    }
  }

  Future<void> setStatus(String appointmentId, String status) async {
    await db
        .from('appointments')
        .update({'status': status}).eq('id', appointmentId);
  }

  /// Lança os valores finais e marca como concluído.
  /// [prices]: id do procedimento -> valor cobrado.
  /// [extraPrice]: usado quando o atendimento não tinha serviço escolhido.
  Future<void> finishAppointment(
    String appointmentId,
    Map<String, double> prices, {
    double? extraPrice,
    String? paymentMethod,
  }) async {
    for (final e in prices.entries) {
      await db
          .from('appointment_services')
          .update({'price': e.value}).eq('id', e.key);
    }
    if (extraPrice != null) {
      await db.from('appointment_services').insert({
        'appointment_id': appointmentId,
        'service_name': 'Atendimento',
        'price': extraPrice,
      });
    }
    await db.from('appointments').update({
      'status': ApptStatus.concluido,
      if (paymentMethod != null) 'payment_method': paymentMethod,
    }).eq('id', appointmentId);
  }
  // ---------------------------------------------------------------- caixa

  static final _ymd = DateFormat('yyyy-MM-dd');

  /// Resumo do mês (faturamento, despesas e lucro), pela view monthly_summary.
  Future<MonthSummary> monthSummary(DateTime month) async {
    final first = DateTime(month.year, month.month, 1);
    final row = await db
        .from('monthly_summary')
        .select()
        .eq('month', _ymd.format(first))
        .maybeSingle();
    return row == null ? const MonthSummary() : MonthSummary.fromMap(row);
  }

  /// Fechamentos semanais (semana inteira, seg–dom) que tocam o mês.
  Future<List<WeekRevenue>> weeksOfMonth(DateTime month) async {
    final from = DateTime(month.year, month.month, 1 - 6);
    final to = DateTime(month.year, month.month + 1, 0);
    final rows = await db
        .from('revenue_by_week')
        .select()
        .gte('week_start', _ymd.format(from))
        .lte('week_start', _ymd.format(to))
        .order('week_start');
    return rows.map(WeekRevenue.fromMap).toList();
  }

  Future<List<Expense>> expensesOfMonth(DateTime month) async {
    final rows = await db
        .from('expenses')
        .select()
        .gte('spent_on', _ymd.format(DateTime(month.year, month.month, 1)))
        .lt('spent_on', _ymd.format(DateTime(month.year, month.month + 1, 1)))
        .order('spent_on', ascending: false);
    return rows.map(Expense.fromMap).toList();
  }

  /// Último valor lançado numa categoria (para sugerir o aluguel).
  Future<double?> lastExpenseAmount(String category) async {
    final row = await db
        .from('expenses')
        .select('amount')
        .eq('category', category)
        .order('spent_on', ascending: false)
        .limit(1)
        .maybeSingle();
    final v = row?['amount'];
    return v is num ? v.toDouble() : null;
  }

  Future<void> addExpense({
    required String category,
    required double amount,
    required DateTime spentOn,
    String? description,
  }) async {
    await db.from('expenses').insert({
      'category': category,
      'amount': amount,
      'spent_on': _ymd.format(spentOn),
      if (description != null && description.isNotEmpty)
        'description': description,
    });
  }

  Future<void> deleteExpense(String id) async {
    await db.from('expenses').delete().eq('id', id);
  }
  // ---------------------------------------------------------------- ajustes

  Future<List<Service>> allServices() async {
    final rows = await db.from('services').select().order('name');
    return rows.map(Service.fromMap).toList();
  }

  Future<void> saveService({String? id, required String name, required double price}) async {
    final data = {'name': name, 'default_price': price};
    if (id == null) {
      await db.from('services').insert(data);
    } else {
      await db.from('services').update(data).eq('id', id);
    }
  }

  Future<void> setServiceActive(String id, bool active) async {
    await db.from('services').update({'active': active}).eq('id', id);
  }

  static String _time(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  Future<void> addWorkSlot(int weekday, int hour, int minute) async {
    await db
        .from('work_slots')
        .insert({'weekday': weekday, 'start_time': _time(hour, minute)});
  }

  Future<void> deleteWorkSlot(String id) async {
    await db.from('work_slots').delete().eq('id', id);
  }

  /// Copia os horários de [fromWeekday] para os dias [to], substituindo os deles.
  Future<void> copyWorkSlots(int fromWeekday, List<WorkSlot> source, List<int> to) async {
    if (to.isEmpty) return;
    await db.from('work_slots').delete().inFilter('weekday', to);
    final rows = [
      for (final day in to)
        for (final s in source.where((s) => s.weekday == fromWeekday))
          {'weekday': day, 'start_time': _time(s.hour, s.minute)},
    ];
    if (rows.isNotEmpty) await db.from('work_slots').insert(rows);
  }

  /// Salva a cliente e devolve o id dela.
  Future<String> saveClient({
    String? id,
    required String name,
    String? phone,
    required int intervalDays,
    required bool isRegular,
    String? notes,
  }) async {
    final data = {
      'name': name,
      'phone': (phone == null || phone.isEmpty) ? null : phone,
      'maintenance_interval_days': intervalDays,
      'is_regular': isRegular,
      'notes': (notes == null || notes.isEmpty) ? null : notes,
    };
    if (id == null) {
      final row = await db.from('clients').insert(data).select('id').single();
      return row['id'] as String;
    }
    await db.from('clients').update(data).eq('id', id);
    // mantém o nome igual nos agendamentos dela
    await db.from('appointments').update({'client_name': name}).eq('client_id', id);
    return id;
  }

  // ---------------------------------------------------------------- fotos

  static const _photoBucket = 'client-photos';
  final Map<String, (String, DateTime)> _photoUrlCache = {};

  /// Envia a foto, grava na cliente e apaga a anterior. Devolve o novo caminho.
  Future<String> setClientPhoto(
    String clientId,
    Uint8List bytes, {
    String mimeType = 'image/jpeg',
    String? oldPath,
  }) async {
    final uid = db.auth.currentUser!.id;
    final ext = switch (mimeType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final path = '$uid/${clientId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await db.storage.from(_photoBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: true),
        );
    await db.from('clients').update({'photo_path': path}).eq('id', clientId);
    if (oldPath != null && oldPath != path) {
      _photoUrlCache.remove(oldPath);
      try {
        await db.storage.from(_photoBucket).remove([oldPath]);
      } catch (_) {}
    }
    return path;
  }

  Future<void> removeClientPhoto(String clientId, String oldPath) async {
    await db.from('clients').update({'photo_path': null}).eq('id', clientId);
    _photoUrlCache.remove(oldPath);
    try {
      await db.storage.from(_photoBucket).remove([oldPath]);
    } catch (_) {}
  }

  /// Links temporários (o bucket é privado) para mostrar as fotos.
  Future<Map<String, String>> photoUrls(Iterable<String?> paths) async {
    final now = DateTime.now();
    final wanted = paths.whereType<String>().toSet();
    final result = <String, String>{};
    final missing = <String>[];
    for (final p in wanted) {
      final cached = _photoUrlCache[p];
      if (cached != null && cached.$2.isAfter(now)) {
        result[p] = cached.$1;
      } else {
        missing.add(p);
      }
    }
    if (missing.isNotEmpty) {
      try {
        final signed =
            await db.storage.from(_photoBucket).createSignedUrls(missing, 3600);
        for (final s in signed) {
          if (s.signedUrl.isEmpty) continue;
          result[s.path] = s.signedUrl;
          _photoUrlCache[s.path] =
              (s.signedUrl, now.add(const Duration(minutes: 50)));
        }
      } catch (_) {
        // sem foto não impede a agenda de abrir
      }
    }
    return result;
  }
  // ---------------------------------------------------------------- recuperação

  Future<void> setRecoveryWord(String word) async {
    await db.rpc('set_recovery_word', params: {'word': word});
  }

  Future<bool> hasRecoveryWord() async {
    final r = await db.rpc('has_recovery_word');
    return r == true;
  }

  /// true = senha trocada; false = e-mail ou palavra não conferem.
  Future<bool> resetPasswordWithWord({
    required String email,
    required String word,
    required String newPassword,
  }) async {
    final r = await db.rpc('reset_password_with_word', params: {
      'p_email': email,
      'p_word': word,
      'p_new_password': newPassword,
    });
    return r == true;
  }
  // ---------------------------------------------------------------- lembretes

  Future<void> markReminderSent(String appointmentId) async {
    await db.from('appointments').update(
        {'reminder_sent_at': DateTime.now().toUtc().toIso8601String()}).eq('id', appointmentId);
  }

  // ---------------------------------------------------------------- pagamento

  Future<void> setPayment(String appointmentId, String method) async {
    await db
        .from('appointments')
        .update({'payment_method': method}).eq('id', appointmentId);
  }

  /// Atendimentos concluídos do mês (com valores e forma de pagamento).
  Future<List<Appointment>> doneInMonth(DateTime month) async {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final rows = await db
        .from('appointments')
        .select('*, appointment_services(*), clients(photo_path, phone)')
        .eq('status', ApptStatus.concluido)
        .gte('starts_at', start.toUtc().toIso8601String())
        .lt('starts_at', end.toUtc().toIso8601String())
        .order('starts_at');
    return rows.map(Appointment.fromMap).toList();
  }

  /// Tudo o que ficou para pagar depois (de qualquer mês).
  Future<List<Appointment>> pendingPayments() async {
    final rows = await db
        .from('appointments')
        .select('*, appointment_services(*), clients(photo_path, phone)')
        .eq('status', ApptStatus.concluido)
        .eq('payment_method', PaymentMethod.pendente)
        .order('starts_at');
    return rows.map(Appointment.fromMap).toList();
  }

  // ---------------------------------------------------------------- ficha da cliente

  Future<ClientStats> clientStats(String clientId) async {
    final row = await db
        .from('client_stats')
        .select()
        .eq('client_id', clientId)
        .maybeSingle();
    return row == null ? const ClientStats() : ClientStats.fromMap(row);
  }

  Future<List<Appointment>> clientHistory(String clientId) async {
    final rows = await db
        .from('appointments')
        .select('*, appointment_services(*), clients(photo_path, phone)')
        .eq('client_id', clientId)
        .neq('status', ApptStatus.cancelado)
        .order('starts_at', ascending: false)
        .limit(50);
    return rows.map(Appointment.fromMap).toList();
  }

  /// Clientes com retorno vencido e sem nenhum horário futuro marcado.
  Future<List<OverdueClient>> overdueClients({bool onlyRegular = true}) async {
    var query = db.from('clients').select();
    if (onlyRegular) query = query.eq('is_regular', true);
    final clientRows = await query;
    final stats = await db.from('client_stats').select();
    final byId = {
      for (final r in stats) r['client_id'] as String: ClientStats.fromMap(r),
    };
    final today = DateTime.now();
    final list = <OverdueClient>[];
    for (final r in clientRows) {
      final c = Client.fromMap(r);
      final st = byId[c.id];
      if (st == null || st.lastVisit == null || st.nextVisit != null) continue;
      final due = st.lastVisit!.add(Duration(days: c.intervalDays));
      final late = today.difference(due).inDays;
      if (late >= 0) list.add(OverdueClient(c, st.lastVisit!, late));
    }
    list.sort((a, b) => b.daysLate.compareTo(a.daysLate));
    return list;
  }

  /// Foto do resultado (unhas feitas) de um atendimento.
  Future<String> setNailPhoto(
    String appointmentId,
    Uint8List bytes, {
    String mimeType = 'image/jpeg',
    String? oldPath,
  }) async {
    final uid = db.auth.currentUser!.id;
    final ext = mimeType == 'image/png'
        ? 'png'
        : mimeType == 'image/webp'
            ? 'webp'
            : 'jpg';
    final path =
        '$uid/nails/${appointmentId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await db.storage.from(_photoBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: true),
        );
    await db
        .from('appointments')
        .update({'nail_photo_path': path}).eq('id', appointmentId);
    if (oldPath != null && oldPath != path) {
      _photoUrlCache.remove(oldPath);
      try {
        await db.storage.from(_photoBucket).remove([oldPath]);
      } catch (_) {}
    }
    return path;
  }

  // ---------------------------------------------------------------- bloqueios

  Future<List<Block>> blocksBetween(DateTime start, DateTime end) async {
    try {
      final rows = await db
          .from('blocks')
          .select()
          .gte('day', _ymd.format(start))
          .lt('day', _ymd.format(end))
          .order('day');
      return rows.map(Block.fromMap).toList();
    } catch (_) {
      return const []; // tabela ainda não criada: segue sem bloqueios
    }
  }

  Future<void> addBlock(DateTime day, {int? hour, int? minute, String? reason}) async {
    await db.from('blocks').insert({
      'day': _ymd.format(day),
      if (hour != null) 'start_time': _time(hour, minute ?? 0),
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
  }

  Future<void> deleteBlock(String id) async {
    await db.from('blocks').delete().eq('id', id);
  }
}

final repo = Repo();
