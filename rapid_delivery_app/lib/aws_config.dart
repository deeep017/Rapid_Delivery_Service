class AwsConfig {
  // REMOTE DEPLOYMENT ENDPOINTS (override with --dart-define at build time)
  //
  // Example:
  // flutter build web \
  //   --dart-define=USE_AWS_BACKEND=true \
  //   --dart-define=AVAILABILITY_BASE_URL=https://api.yourdomain.com \
  //   --dart-define=ORDER_BASE_URL=https://api.yourdomain.com/order

  /// Availability base URL used by buyer + manager APIs
  static const String availabilityUrl = String.fromEnvironment(
    'AVAILABILITY_BASE_URL',
    defaultValue: 'https://api.yourdomain.com',
  );

  /// Order service base URL (keeps /order prefix for reverse-proxy routing)
  static const String orderUrl = String.fromEnvironment(
    'ORDER_BASE_URL',
    defaultValue: 'https://api.yourdomain.com/order',
  );

  /// Environment indicator
  static const String environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'production',
  );

  /// Is production flag
  static const bool isProduction = bool.fromEnvironment(
    'APP_IS_PRODUCTION',
    defaultValue: true,
  );
}
