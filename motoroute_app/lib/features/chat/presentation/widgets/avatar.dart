import 'package:flutter/material.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';

/// Profilbild mit Initialen-Fallback (Abschnitt 3). Kein Netz-Image im
/// MVP - der Avatar-URL-Typ ist im Modell vorbereitet (avatar_url), die
/// Anzeige greift, sobald Bild-Uploads folgen.
class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String name;
  final double size; // Radius in px

  const UserAvatar({super.key, this.avatarUrl, required this.name, this.size = 20});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    return CircleAvatar(
      radius: size,
      backgroundColor: AppColors.bgSurfaceRaisedDark,
      foregroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty)
          ? NetworkImage(avatarUrl!)
          : null,
      child: Text(
        initial,
        style: const TextStyle(color: AppColors.accentPrimaryDark, fontWeight: FontWeight.w700),
      ),
    );
  }
}
