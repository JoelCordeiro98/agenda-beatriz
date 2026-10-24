import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import 'format.dart';

/// "(83) 98888-7777" -> "5583988887777". Devolve null se não der para usar.
String? waNumber(String? phone) {
  if (phone == null) return null;
  var digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('0')) digits = digits.substring(1);
  if (digits.length == 10 || digits.length == 11) digits = '55$digits';
  return digits.length >= 12 ? digits : null;
}

/// Abre o WhatsApp com a mensagem pronta. Sem telefone, abre a lista de
/// conversas para ela escolher. Devolve false se não conseguiu abrir.
Future<bool> openWhatsApp({String? phone, required String text}) {
  final n = waNumber(phone);
  final base = n == null ? 'https://wa.me/' : 'https://wa.me/$n';
  final uri = Uri.parse('$base?text=${Uri.encodeComponent(text)}');
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

String firstName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts.isEmpty ? name : parts.first;
}

/// "Oi, Ana! Passando para lembrar do seu horário amanhã (sex 24/10) às 10h..."
String reminderMessage(Appointment a, {required DateTime today}) {
  final d = a.startsAt;
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  final when = sameDay(d, tomorrow)
      ? 'amanhã (${weekdayShort[d.weekday - 1].toLowerCase()} ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')})'
      : sameDay(d, today)
          ? 'hoje'
          : 'dia ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  final servico = a.items.isEmpty ? '' : ' para ${a.servicesLabel.toLowerCase()}';
  return 'Oi, ${firstName(a.clientName)}! 💅 Passando para lembrar do seu '
      'horário $when às ${hourLabel(d.hour, d.minute)}$servico. '
      'Posso confirmar? Se precisar remarcar, é só me avisar. 😊';
}

String comeBackMessage(Client c, int daysSince) {
  final semanas = (daysSince / 7).round();
  final tempo = semanas >= 2 ? 'umas $semanas semanas' : 'um tempinho';
  return 'Oi, ${firstName(c.name)}! 💅 Já faz $tempo desde a sua última visita. '
      'Bora deixar as unhas em dia? Me diz o melhor dia e horário para você '
      'que eu vejo aqui na agenda. 😊';
}
