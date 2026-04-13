import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Public DSN from the Sentry project (**Client Keys**). Safe to ship in the app.
///
/// Omit or leave empty so the SDK stays off (local dev, CI).
const kSentryDsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');

/// Set to `false` to disable Sentry even when [kSentryDsn] is set (e.g. experiments).
const kSentryEnabled = bool.fromEnvironment('WOLEH_SENTRY', defaultValue: true);

const kSentryEnvironment = String.fromEnvironment(
  'SENTRY_ENVIRONMENT',
  defaultValue: 'development',
);

const _kSentryTracesSampleRateRaw = String.fromEnvironment(
  'SENTRY_TRACES_SAMPLE_RATE',
  defaultValue: '',
);

double get kSentryTracesSampleRate {
  if (_kSentryTracesSampleRateRaw.isEmpty) return 0;
  return double.tryParse(_kSentryTracesSampleRateRaw) ?? 0;
}

bool get isSentryConfigured => kSentryEnabled && kSentryDsn.isNotEmpty;

/// Wraps [appRunner] with [SentryFlutter.init] when [isSentryConfigured].
///
/// Call after [WidgetsFlutterBinding.ensureInitialized] so [PackageInfo] works.
Future<void> runWithSentryIfConfigured(Future<void> Function() appRunner) async {
  if (!isSentryConfigured) {
    await appRunner();
    return;
  }
  final info = await PackageInfo.fromPlatform();
  final release = '${info.packageName}@${info.version}+${info.buildNumber}';
  await SentryFlutter.init(
    (options) {
      options.dsn = kSentryDsn;
      options.environment = kSentryEnvironment;
      options.tracesSampleRate = kSentryTracesSampleRate;
      options.sendDefaultPii = false;
      options.release = release;
    },
    appRunner: appRunner,
  );
}

Future<void> setSentryUserId(String id) async {
  if (!isSentryConfigured) return;
  await Sentry.configureScope((scope) {
    scope.setUser(SentryUser(id: id));
  });
}

Future<void> clearSentryUser() async {
  if (!isSentryConfigured) return;
  await Sentry.configureScope((scope) {
    scope.setUser(null);
  });
}
