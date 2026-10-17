import 'package:flutter/material.dart';

import '../badges_repository.dart';

/// Badge-Symbol: zeigt icon_url (nur https), sonst das Kategorie-Emoji.
/// Auch bei Ladefehler oder während des Ladens bleibt das Emoji sichtbar -
/// der Trophäenschrank hat also nie ein kaputtes Bild.
class BadgeIcon extends StatelessWidget {
  final String? iconUrl;
  final BadgeCategory category;
  final double size;

  const BadgeIcon({
    super.key,
    required this.iconUrl,
    required this.category,
    this.size = 34,
  });

  @override
  Widget build(BuildContext context) {
    final emoji = Text(category.emoji, style: TextStyle(fontSize: size));
    final url = iconUrl;
    if (url == null || !url.startsWith('https://')) return emoji;
    return SizedBox(
      width: size + 6,
      height: size + 6,
      child: Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Center(child: emoji),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : Center(child: emoji),
      ),
    );
  }
}
