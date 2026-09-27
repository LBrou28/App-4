import 'package:flutter/widgets.dart';

import '../core/contracts.dart';

/// B1-v1 Flutter boundary. Core contracts remain independent of Flutter.
///
/// A owns the host, notifier and stable world view/game lifetime. [changes]
/// notifies after state AND movement-gate commits. B subscribes on attachment,
/// removes listeners on disposal and clears held input on gate/focus loss.
/// Ordinary notifications must not recreate the world/game instance.
/// Listeners read the host; they must not synchronously mutate it.
typedef WorldViewBuilder = Widget Function(
  BuildContext context,
  WorldHost host,
  Listenable changes,
);
