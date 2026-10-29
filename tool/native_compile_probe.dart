import 'package:flutter/widgets.dart';

/// Build-only entry point for checking the iOS host's Swift/C integration.
/// It starts no game, presents no game UI, and is never exported as an IPA.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
}
