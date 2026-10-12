import 'dart:async';

Future<bool> hasStableInternetConnection({
  required Future<bool> Function() probe,
  required int requiredSuccessfulProbes,
  required Duration probeTimeout,
  required Duration interval,
}) async {
  if (requiredSuccessfulProbes < 1) {
    throw ArgumentError.value(
      requiredSuccessfulProbes,
      'requiredSuccessfulProbes',
      'Must be at least 1.',
    );
  }

  for (var attempt = 0; attempt < requiredSuccessfulProbes; attempt++) {
    try {
      if (!await probe().timeout(probeTimeout)) return false;
    } on TimeoutException {
      return false;
    }

    if (attempt + 1 < requiredSuccessfulProbes) {
      await Future<void>.delayed(interval);
    }
  }
  return true;
}
