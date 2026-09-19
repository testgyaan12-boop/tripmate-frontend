class ApiConstants {
  // Emulator: 10.0.2.2, device on LAN: use host IP, web: localhost.
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  static const register = '/api/auth/register';
  static const login = '/api/auth/login';
  static const google = '/api/auth/google';
  static const refresh = '/api/auth/refresh';
  static const logout = '/api/auth/logout';
  static const publicConfig = '/api/config/public';
  static const myTrips = '/api/trips/mine';
  static const wsUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'http://localhost:8080/ws',
  );
}
