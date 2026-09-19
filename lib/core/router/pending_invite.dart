import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Invite code waiting for the user to finish login/register.
/// Consumed once: after auth success the app routes back to /join?code=.
final pendingInviteProvider = StateProvider<String?>((_) => null);
