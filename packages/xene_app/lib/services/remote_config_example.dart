// Example: How to wire RemoteConfig into your existing API/Supabase client
//
// Usage in your main.dart or app initialization:
//
// import 'services/remote_config.dart';
//
// Future<void> initializeApp() async {
//   // Fetch backend URL on app startup
//   final backendUrl = await RemoteConfig.getBackendUrl();
//
//   // Use it to configure your API client
//   // Example with Supabase:
//   // await Supabase.initialize(
//   //   url: 'https://your-supabase-url.supabase.co',
//   //   anonKey: 'your-anon-key',
//   //   authCallbackUrlScheme: 'com.xene.app', // deep link scheme
//   // );
//
//   // Or with custom API client:
//   // final apiClient = ApiClient(baseUrl: backendUrl);
//
//   print('[App] Backend URL: $backendUrl');
// }
//
// Then, when making API calls:
// Use the URL from RemoteConfig.getBackendUrl()
//
// If you store it as a provider (Riverpod recommended):
// final backendUrlProvider = FutureProvider<String>((ref) async {
//   return RemoteConfig.getBackendUrl();
// });
//
// Use in your API client:
// final apiClient = ref.watch(backendUrlProvider);
