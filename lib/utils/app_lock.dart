import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/auth_service.dart';

/// Turns App lock on or off, proving it works before turning it on: on a
/// phone with no screen lock or fingerprint set up (or where the prompt can't
/// open) the switch would otherwise turn on anyway, promising a protection
/// the app couldn't give. Returns whether the lock is on afterwards.
Future<bool> setAppLockChecked(BuildContext context, bool on,
    {AuthService? authService}) async {
  final settings = context.read<SettingsProvider>();
  if (!on) {
    await settings.setAppLockEnabled(false);
    return false;
  }
  final messenger = ScaffoldMessenger.of(context);
  final outcome = await (authService ?? AuthService()).authenticate();
  switch (outcome) {
    case AuthOutcome.success:
      await settings.setAppLockEnabled(true);
      return true;
    case AuthOutcome.failed:
      messenger.showSnackBar(const SnackBar(
          content: Text('App lock is still off: it could not confirm it '
              'was you.')));
      return false;
    case AuthOutcome.unavailable:
      messenger.showSnackBar(const SnackBar(
          content: Text('Set up a screen lock or fingerprint on this phone '
              'first, then turn on App lock.')));
      return false;
  }
}
