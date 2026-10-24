import 'package:intl/intl.dart';

import '../models.dart';

final money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

const weekdayShort = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 08:00 -> "8h", 10:30 -> "10h30"
String hourLabel(int hour, int minute) =>
    minute == 0 ? '${hour}h' : '${hour}h${minute.toString().padLeft(2, '0')}';

String timeLabel(DateTime d) => DateFormat('HH:mm').format(d);

String capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// "Sexta-feira, 23 de outubro"
String dayTitle(DateTime d) =>
    capitalize(DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(d));

/// "Seg 27/10 às 10:00"
String shortDateTime(DateTime d) =>
    '${weekdayShort[d.weekday - 1]} ${DateFormat('dd/MM').format(d)} às ${timeLabel(d)}';

/// Aceita "45", "45,50", "1.200,50" e "45.5".
double? parsePrice(String raw) {
  var s = raw.replaceAll(r'R$', '').replaceAll(' ', '').trim();
  if (s.isEmpty) return null;
  if (s.contains(',')) s = s.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(s);
}

String priceText(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

/// Texto com os horários livres da semana de [monday], pronto para o WhatsApp.
String freeSlotsText(
  DateTime monday,
  List<WorkSlot> slots,
  List<Appointment> appts,
  DateTime now,
) {
  final lines = <String>[];
  for (var i = 0; i < 7; i++) {
    final day = DateTime(monday.year, monday.month, monday.day + i);
    final free = <String>[];
    for (final s in slots.where((s) => s.weekday == day.weekday)) {
      final t = DateTime(day.year, day.month, day.day, s.hour, s.minute);
      if (!t.isAfter(now)) continue;
      final taken = appts.any((a) =>
          sameDay(a.startsAt, t) &&
          a.startsAt.hour == s.hour &&
          a.startsAt.minute == s.minute);
      if (!taken) free.add(hourLabel(s.hour, s.minute));
    }
    if (free.isNotEmpty) {
      lines.add(
          '${weekdayShort[day.weekday - 1]} ${DateFormat('dd/MM').format(day)}: ${free.join(', ')}');
    }
  }

  if (lines.isEmpty) {
    return 'Agenda cheia nesta semana! 💅 Me chama que eu vejo um horário na próxima.';
  }
  return '💅 Horários disponíveis nesta semana:\n\n'
      '${lines.join('\n')}\n\n'
      'Me chama pra agendar! 😊';
}
