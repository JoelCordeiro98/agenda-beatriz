import 'package:flutter/material.dart';

/// Foto redonda da cliente. Sem foto (ou se a foto falhar), mostra as iniciais.
class ClientAvatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final ImageProvider? image; // foto recém-escolhida, ainda não enviada
  final double radius;

  const ClientAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.image,
    this.radius = 20,
  });

  static String initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider =
        image ?? (photoUrl != null ? NetworkImage(photoUrl!) : null);
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundImage: provider,
      onForegroundImageError: provider == null ? null : (_, __) {},
      child: Text(
        initials(name),
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
          fontSize: radius * 0.7,
        ),
      ),
    );
  }
}
