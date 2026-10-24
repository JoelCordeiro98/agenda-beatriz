class Client {
  final String id;
  final String name;
  final String? phone;
  final int intervalDays;
  final bool isRegular;
  final String? notes;
  final String? photoPath;

  const Client({
    required this.id,
    required this.name,
    this.phone,
    this.intervalDays = 30,
    this.isRegular = false,
    this.notes,
    this.photoPath,
  });

  factory Client.fromMap(Map<String, dynamic> m) => Client(
        id: m['id'] as String,
        name: m['name'] as String,
        phone: m['phone'] as String?,
        intervalDays: (m['maintenance_interval_days'] as int?) ?? 30,
        isRegular: (m['is_regular'] as bool?) ?? false,
        notes: m['notes'] as String?,
        photoPath: m['photo_path'] as String?,
      );
}

class Service {
  final String id;
  final String name;
  final double defaultPrice;
  final bool active;

  const Service({
    required this.id,
    required this.name,
    required this.defaultPrice,
    this.active = true,
  });

  factory Service.fromMap(Map<String, dynamic> m) => Service(
        id: m['id'] as String,
        name: m['name'] as String,
        defaultPrice: (m['default_price'] as num).toDouble(),
        active: (m['active'] as bool?) ?? true,
      );
}

/// Um horário fixo de trabalho (ex.: segunda às 08:00).
class WorkSlot {
  final int weekday; // 1 = segunda ... 7 = domingo (igual ao DateTime.weekday)
  final int hour;
  final int minute;
  final String? id;

  const WorkSlot(this.weekday, this.hour, this.minute, {this.id});

  factory WorkSlot.fromMap(Map<String, dynamic> m) {
    final parts = (m['start_time'] as String).split(':');
    return WorkSlot(
      m['weekday'] as int,
      int.parse(parts[0]),
      int.parse(parts[1]),
      id: m['id'] as String?,
    );
  }
}

class ApptItem {
  final String id;
  final String? serviceId;
  final String serviceName;
  final double price;

  const ApptItem({
    required this.id,
    this.serviceId,
    required this.serviceName,
    required this.price,
  });

  factory ApptItem.fromMap(Map<String, dynamic> m) => ApptItem(
        id: m['id'] as String,
        serviceId: m['service_id'] as String?,
        serviceName: m['service_name'] as String,
        price: (m['price'] as num).toDouble(),
      );
}

class ApptStatus {
  static const agendado = 'agendado';
  static const concluido = 'concluido';
  static const faltou = 'faltou';
  static const cancelado = 'cancelado';
}

class Appointment {
  final String id;
  final String? clientId;
  final String clientName;
  final DateTime startsAt; // horário local
  final String status;
  final String? notes;
  final List<ApptItem> items;
  final String? clientPhotoPath;

  const Appointment({
    required this.id,
    this.clientId,
    required this.clientName,
    required this.startsAt,
    required this.status,
    this.notes,
    this.items = const [],
    this.clientPhotoPath,
  });

  double get total => items.fold(0.0, (sum, i) => sum + i.price);

  String get servicesLabel => items.map((i) => i.serviceName).join(' + ');

  factory Appointment.fromMap(Map<String, dynamic> m) {
    final rawItems = (m['appointment_services'] as List?) ?? const [];
    final client = m['clients'];
    return Appointment(
      id: m['id'] as String,
      clientId: m['client_id'] as String?,
      clientName: m['client_name'] as String,
      startsAt: DateTime.parse(m['starts_at'] as String).toLocal(),
      status: m['status'] as String,
      notes: m['notes'] as String?,
      items: rawItems
          .map((e) => ApptItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      clientPhotoPath:
          client is Map ? client['photo_path'] as String? : null,
    );
  }
}

// ------------------------------------------------------------------ caixa

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

int _toInt(dynamic v) => _toDouble(v).round();

class MonthSummary {
  final int atendimentos;
  final double faturamento;
  final double aluguel;
  final double material;
  final double outros;
  final double despesas;
  final double lucro;

  const MonthSummary({
    this.atendimentos = 0,
    this.faturamento = 0,
    this.aluguel = 0,
    this.material = 0,
    this.outros = 0,
    this.despesas = 0,
    this.lucro = 0,
  });

  factory MonthSummary.fromMap(Map<String, dynamic> m) => MonthSummary(
        atendimentos: _toInt(m['atendimentos']),
        faturamento: _toDouble(m['faturamento']),
        aluguel: _toDouble(m['aluguel']),
        material: _toDouble(m['material']),
        outros: _toDouble(m['outros']),
        despesas: _toDouble(m['despesas']),
        lucro: _toDouble(m['lucro']),
      );
}

class WeekRevenue {
  final DateTime weekStart; // segunda-feira
  final int atendimentos;
  final double faturamento;

  const WeekRevenue(this.weekStart, this.atendimentos, this.faturamento);

  factory WeekRevenue.fromMap(Map<String, dynamic> m) => WeekRevenue(
        DateTime.parse(m['week_start'] as String),
        _toInt(m['atendimentos']),
        _toDouble(m['faturamento']),
      );
}

class ExpenseCategory {
  static const aluguel = 'aluguel';
  static const material = 'material';
  static const outro = 'outro';

  static String label(String c) => switch (c) {
        aluguel => 'Aluguel da mesa',
        material => 'Material',
        _ => 'Outro',
      };
}

class Expense {
  final String id;
  final String category;
  final String? description;
  final double amount;
  final DateTime spentOn;

  const Expense({
    required this.id,
    required this.category,
    this.description,
    required this.amount,
    required this.spentOn,
  });

  String get title => (description != null && description!.trim().isNotEmpty)
      ? description!
      : ExpenseCategory.label(category);

  factory Expense.fromMap(Map<String, dynamic> m) => Expense(
        id: m['id'] as String,
        category: m['category'] as String,
        description: m['description'] as String?,
        amount: _toDouble(m['amount']),
        spentOn: DateTime.parse(m['spent_on'] as String),
      );
}
