import 'package:flutter/material.dart';

import '../../chat_providers.dart';

/// Meldungs-Sheet (Abschnitt 22): Gründe gespiegelt vom Schema-Constraint,
/// Backend speichert die Meldung serverseitig.
Future<void> showReportSheet(
  BuildContext context, {
  required String title,
  required Future<void> Function(String reason, String? details) onSubmit,
}) {
  String? reason;
  final detailsController = TextEditingController();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF151A1F),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: const TextStyle(
                    color: Color(0xFFF5F6F4),
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            ...reportReasons.entries.map((e) => RadioListTile<String>(
                  value: e.key,
                  groupValue: reason,
                  activeColor: const Color(0xFFFF5A1F),
                  title: Text(e.value,
                      style: const TextStyle(color: Color(0xFFF5F6F4))),
                  onChanged: (v) => setSheetState(() => reason = v),
                )),
            const SizedBox(height: 8),
            TextField(
              controller: detailsController,
              maxLines: 2,
              style: const TextStyle(color: Color(0xFFF5F6F4)),
              decoration: const InputDecoration(
                hintText: 'Details (optional)',
                hintStyle: TextStyle(color: Color(0xFF5B6470)),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0x14FFFFFF)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF5A1F),
                foregroundColor: const Color(0xFFF5F6F4),
              ),
              onPressed: reason == null
                  ? null
                  : () async {
                      Navigator.pop(sheetContext);
                      await onSubmit(reason!, detailsController.text.trim().isEmpty
                          ? null
                          : detailsController.text.trim());
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Meldung gesendet. Danke!')),
                        );
                      }
                    },
              child: const Text('Melden'),
            ),
          ],
        ),
      ),
    ),
  );
}
