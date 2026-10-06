import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fahrbetrieb: reduziert spätere Karten- und POI-Refreshes zentral.
final NotifierProvider<SaverModeController, bool> saverModeProvider =
    NotifierProvider<SaverModeController, bool>(SaverModeController.new);

class SaverModeController extends Notifier<bool> {
  @override
  bool build() => false;

  void setEnabled(bool value) => state = value;
}
