import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/app_user.dart';

/// Current authenticated profile for this application session.
/// Persistent session restoration is added together with offline master cache.
final currentUserProvider = StateProvider<AppUser?>((ref) => null);
