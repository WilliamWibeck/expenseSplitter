import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:velocity_x/velocity_x.dart';
import 'auth/auth_repository.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'firebase_options.dart';
import 'data/firestore_repository.dart';
import 'models/group.dart';
import 'models/expense.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'notifications/notifications_service.dart';
import 'package:cloud_functions/cloud_functions.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on UnsupportedError {
    // For platforms without generated options (e.g., linux), fall back.
  await Firebase.initializeApp();
  }
  runApp(const ProviderScope(child: MyApp()));
}

class ThemeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void setThemeMode(ThemeMode mode) {
    state = mode;
  }
}

final themeNotifierProvider = NotifierProvider<ThemeNotifier, ThemeMode>(ThemeNotifier.new);

// Simple auth state provider
final authStateProvider = StreamProvider<User?>((ref) {
  return fb.FirebaseAuth.instance.authStateChanges();
});

// Developer mode notifier
class DeveloperModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  
  void setDeveloperMode(bool value) {
    state = value;
  }
}

final developerModeProvider = NotifierProvider<DeveloperModeNotifier, bool>(DeveloperModeNotifier.new);

// Cached expenses provider to avoid multiple Firestore queries
final expensesProvider = StreamProvider.family<List<Expense>, String>((ref, groupId) {
  final repo = ref.watch(firestoreRepositoryProvider);
  final devMode = ref.watch(developerModeProvider);
  
  // For developer mode, use developer expenses provider
  if (devMode) {
    final devExpenses = ref.watch(developerExpensesProvider(groupId));
    return Stream.value(devExpenses);
  }
  
  return repo.watchExpenses(groupId);
});

// Developer groups provider - returns sample groups without Firebase
final developerGroupsProvider = Provider<List<Group>>((ref) {
  final devMode = ref.watch(developerModeProvider);
  if (!devMode) return [];
  
  return [
    Group(
      id: 'dev_group_1',
      name: 'Trip to Tokyo',
      memberUserIds: ['dev_user_123', 'user_alice', 'user_bob', 'user_charlie'],
      createdAtMs: DateTime.now().subtract(const Duration(days: 2)).millisecondsSinceEpoch,
      shareCode: '123456',
    ),
    Group(
      id: 'dev_group_2', 
      name: 'Dinner with Friends',
      memberUserIds: ['dev_user_123', 'user_david', 'user_eve'],
      createdAtMs: DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch,
      shareCode: '234567',
    ),
    Group(
      id: 'dev_group_3',
      name: 'Office Lunch', 
      memberUserIds: ['dev_user_123', 'user_frank', 'user_grace'],
      createdAtMs: DateTime.now().subtract(const Duration(hours: 6)).millisecondsSinceEpoch,
      shareCode: '345678',
    ),
  ];
});

// Developer expenses provider - returns sample expenses without Firebase
final developerExpensesProvider = Provider.family<List<Expense>, String>((ref, groupId) {
  final devMode = ref.watch(developerModeProvider);
  if (!devMode) return [];
  
  switch (groupId) {
    case 'dev_group_1':
      return [
        Expense(
          id: 'exp1',
          groupId: groupId,
          description: 'Hotel room (3 nights)',
          amountCents: 45000,
          paidByUserId: 'dev_user_123',
          splitUserIds: ['dev_user_123', 'user_alice', 'user_bob'],
          createdAtMs: DateTime.now().subtract(const Duration(days: 2)).millisecondsSinceEpoch,
          splitMode: SplitMode.equal,
        ),
        Expense(
          id: 'exp2',
          groupId: groupId,
          description: 'Sushi dinner',
          amountCents: 12000,
          paidByUserId: 'user_alice',
          splitUserIds: ['dev_user_123', 'user_alice', 'user_bob', 'user_charlie'],
          createdAtMs: DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch,
          splitMode: SplitMode.equal,
        ),
        Expense(
          id: 'exp3',
          groupId: groupId,
          description: 'Train tickets',
          amountCents: 8500,
          paidByUserId: 'user_bob',
          splitUserIds: ['dev_user_123', 'user_alice', 'user_bob'],
          createdAtMs: DateTime.now().subtract(const Duration(hours: 6)).millisecondsSinceEpoch,
          splitMode: SplitMode.custom,
          customAmounts: {
            'dev_user_123': 3000,
            'user_alice': 2500,
            'user_bob': 3000,
          },
        ),
      ];
    case 'dev_group_2':
      return [
        Expense(
          id: 'exp4',
          groupId: groupId,
          description: 'Pizza and drinks',
          amountCents: 6500,
          paidByUserId: 'dev_user_123',
          splitUserIds: ['dev_user_123', 'user_david', 'user_eve'],
          createdAtMs: DateTime.now().subtract(const Duration(hours: 3)).millisecondsSinceEpoch,
          splitMode: SplitMode.percent,
          percentages: {
            'dev_user_123': 0.4,
            'user_david': 0.3,
            'user_eve': 0.3,
          },
        ),
      ];
    case 'dev_group_3':
      return [
        Expense(
          id: 'exp5',
          groupId: groupId,
          description: 'Sandwiches and coffee',
          amountCents: 3200,
          paidByUserId: 'user_frank',
          splitUserIds: ['dev_user_123', 'user_frank', 'user_grace'],
          createdAtMs: DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
          splitMode: SplitMode.equal,
        ),
      ];
    default:
      return [];
  }
});

// Helper functions for expense details
String _getUserDisplayName(String userId) {
  // Map user IDs to display names for demo
  switch (userId) {
    case 'dev_user_123':
      return 'You';
    case 'user_alice':
      return 'Alice';
    case 'user_bob':
      return 'Bob';
    case 'user_charlie':
      return 'Charlie';
    case 'user_david':
      return 'David';
    case 'user_eve':
      return 'Eve';
    case 'user_frank':
      return 'Frank';
    case 'user_grace':
      return 'Grace';
    default:
      return userId;
  }
}

String _formatDate(int timestampMs) {
  final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
  final now = DateTime.now();
  final difference = now.difference(date);
  
  if (difference.inDays > 0) {
    return '${difference.inDays}d ago';
  } else if (difference.inHours > 0) {
    return '${difference.inHours}h ago';
  } else if (difference.inMinutes > 0) {
    return '${difference.inMinutes}m ago';
  } else {
    return 'Just now';
  }
}

String _formatCents(int cents) {
  final double amount = cents / 100.0;
  return '\$' + amount.toStringAsFixed(2);
}

int _getOwedAmount(Expense expense, String userId) {
  switch (expense.splitMode) {
    case SplitMode.equal:
      return (expense.amountCents / expense.splitUserIds.length).floor();
    case SplitMode.custom:
      return expense.customAmounts[userId] ?? 0;
    case SplitMode.percent:
      final percentage = expense.percentages[userId] ?? 0.0;
      return (expense.amountCents * percentage).round();
  }
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final devMode = ref.watch(developerModeProvider);
    ref.listen<AsyncValue<User?>>(authStateProvider, (_, next) async {
      final user = next.value;
      if (user != null) {
        try {
          await ref.read(notificationsServiceProvider).initAndRegisterToken();
        } catch (_) {}
      }
    });
    final GoRouter router = GoRouter(
      initialLocation: '/auth',
      redirect: (context, state) {
        final bool isLoggedIn = fb.FirebaseAuth.instance.currentUser != null;
        final bool onAuth = state.matchedLocation == '/auth';
        
        // Check for developer mode
        if (devMode && onAuth) return '/groups';
        if (!isLoggedIn && !devMode && !onAuth) return '/auth';
        if (isLoggedIn && onAuth) return '/groups';
        return null;
      },
      routes: <GoRoute>[
        GoRoute(
          path: '/auth',
          name: 'auth',
          builder: (context, state) => const AuthScreen(),
        ),
        GoRoute(
          path: '/groups',
          name: 'groups',
          builder: (context, state) => const GroupsScreen(),
          routes: <GoRoute>[
            GoRoute(
              path: ':groupId',
              name: 'group_detail',
              builder: (context, state) => GroupDetailScreen(
                groupId: state.pathParameters['groupId']!,
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/scan',
          name: 'scan',
          builder: (context, state) => const ReceiptScanScreen(),
        ),
        GoRoute(
          path: '/join',
          name: 'join',
          builder: (context, state) => const JoinGroupScreen(),
        ),
      ],
    );

    final ThemeData lightTheme = ThemeData(
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF2D3748), // Deep charcoal
        secondary: Color(0xFF4A5568), // Medium gray
        surface: Color(0xFFF7FAFC), // Very light gray
        background: Color(0xFFFFFFFF), // Pure white
        error: Color(0xFFE53E3E), // Subtle red accent
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Color(0xFF1A202C), // Dark text
        onBackground: Color(0xFF1A202C), // Dark text
        onError: Colors.white,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: const Color(0xFFF7FAFC),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        color: Colors.white,
        shadowColor: Colors.black.withOpacity(0.06),
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            letterSpacing: 0.8,
          ),
          backgroundColor: const Color(0xFF2D3748),
          foregroundColor: Colors.white,
        ),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 24,
          letterSpacing: 0.5,
          color: Color(0xFF1A202C),
        ),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: Color(0xFF4A5568)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFF2D3748), width: 2),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        hintStyle: const TextStyle(color: Color(0xFFA0AEC0)),
        labelStyle: const TextStyle(color: Color(0xFF4A5568), fontWeight: FontWeight.w500),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        titleTextStyle: const TextStyle(
          color: Color(0xFF1A202C),
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
        subtitleTextStyle: const TextStyle(
          color: Color(0xFF718096),
          fontSize: 14,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE2E8F0),
        thickness: 1,
        space: 1,
      ),
    );

    final ThemeData darkTheme = ThemeData(
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFE2E8F0), // Light gray
        secondary: Color(0xFFA0AEC0), // Medium light gray
        surface: Color(0xFF1A202C), // Dark surface
        background: Color(0xFF0F1419), // Very dark background
        error: Color(0xFFFC8181), // Light red accent
        onPrimary: Color(0xFF1A202C), // Dark text on light
        onSecondary: Color(0xFF1A202C), // Dark text on light
        onSurface: Color(0xFFE2E8F0), // Light text
        onBackground: Color(0xFFE2E8F0), // Light text
        onError: Color(0xFF1A202C), // Dark text on error
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: const Color(0xFF0F1419),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        color: const Color(0xFF1A202C),
        shadowColor: Colors.black.withOpacity(0.4),
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            letterSpacing: 0.8,
          ),
          backgroundColor: const Color(0xFF2D3748),
          foregroundColor: const Color(0xFFE2E8F0),
        ),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 24,
          letterSpacing: 0.5,
          color: Color(0xFFE2E8F0),
        ),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: Color(0xFFA0AEC0)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFF2D3748), width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFF2D3748), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 2),
        ),
        filled: true,
        fillColor: const Color(0xFF1A202C),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        hintStyle: const TextStyle(color: Color(0xFF718096)),
        labelStyle: const TextStyle(color: Color(0xFFA0AEC0), fontWeight: FontWeight.w500),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        titleTextStyle: const TextStyle(
          color: Color(0xFFE2E8F0),
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
        subtitleTextStyle: const TextStyle(
          color: Color(0xFFA0AEC0),
          fontSize: 14,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF2D3748),
        thickness: 1,
        space: 1,
      ),
    );

    final themeMode = ref.watch(themeNotifierProvider);

    return MaterialApp.router(
      title: 'Expense Splitter',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _AuthScreenContent();
  }
}

class _AuthScreenContent extends ConsumerStatefulWidget {
  const _AuthScreenContent({super.key});

  @override
  ConsumerState<_AuthScreenContent> createState() => _AuthScreenContentState();
}

class _AuthScreenContentState extends ConsumerState<_AuthScreenContent> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _smsCodeController = TextEditingController();
  bool _isLoading = false;

  Future<void> _handle<T>(Future<T> Function() op) async {
    setState(() => _isLoading = true);
    try {
      await op();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AuthRepository repo = ref.read(authRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFF8FAFC),
              const Color(0xFFF1F5F9),
              const Color(0xFFE2E8F0),
              const Color(0xFFCBD5E0),
            ],
            stops: const [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Noise texture overlay
            Positioned.fill(
              child: CustomPaint(
                painter: NoisePainter(),
              ),
            ),
            // Main content
            VStack([
          60.heightBox,
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: VStack([
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D3748).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 48,
                  color: const Color(0xFF2D3748),
                ),
              ),
              32.heightBox,
              'Expense Splitter'.text.xl5.bold.center.make(),
        16.heightBox,
              'Split expenses effortlessly with friends and family'
            .text
                  .lg
                  .color(const Color(0xFF718096))
                  .center
            .make(),
              48.heightBox,
        // Google
              Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    colors: [Colors.white, Colors.grey.shade50],
                  ),
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
          onPressed: _isLoading
              ? null
              : () => _handle(() async {
                    final user = await repo.signInWithGoogle();
                    ref.read(currentUserProvider.notifier).set(user);
                    if (context.mounted) context.go('/groups');
                  }),
                  icon: const Icon(Icons.g_mobiledata, size: 22, color: Color(0xFF4285F4)),
                  label: const Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Color(0xFF1A202C),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: const Color(0xFF1A202C),
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                ),
              ),
              20.heightBox,
        // Apple (will work on iOS/macOS targets)
              Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1A202C), Color(0xFF2D3748)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
          onPressed: _isLoading
              ? null
              : () => _handle(() async {
                    final user = await repo.signInWithApple();
                    ref.read(currentUserProvider.notifier).set(user);
                    if (context.mounted) context.go('/groups');
                  }),
                  icon: const Icon(Icons.apple, size: 22, color: Colors.white),
                  label: const Text(
                    'Continue with Apple',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                ),
              ),
              32.heightBox,
              // Divider
              Row(
                children: [
                  Expanded(child: Container(height: 1, color: const Color(0xFFE2E8F0))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'or',
                      style: TextStyle(
                        color: const Color(0xFF718096),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(child: Container(height: 1, color: const Color(0xFFE2E8F0))),
                ],
              ),
              32.heightBox,
        // Email + password
        VxTextField(
          controller: _emailController,
          labelText: 'Email',
          keyboardType: TextInputType.emailAddress,
        ),
              20.heightBox,
        VxTextField(
          controller: _passwordController,
          labelText: 'Password',
          isPassword: true,
        ),
              32.heightBox,
              Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2D3748), Color(0xFF4A5568)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2D3748).withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ElevatedButton(
          onPressed: _isLoading
              ? null
              : () => _handle(() async {
                    final user = await repo.signInWithEmailPassword(
                      email: _emailController.text.trim(),
                      password: _passwordController.text,
                    );
                    ref.read(currentUserProvider.notifier).set(user);
                    if (context.mounted) context.go('/groups');
                  }),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                  child: const Text(
                    'Sign in with Email',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
        24.heightBox,
        // Phone number
        VxTextField(
          controller: _phoneController,
          labelText: 'Phone number',
          keyboardType: TextInputType.phone,
        ),
        12.heightBox,
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
          onPressed: _isLoading
              ? null
              : () => _handle(() async {
                    final user = await repo.signInWithPhoneNumber(
                      phoneNumber: _phoneController.text.trim(),
                    );
                      if (user != null) {
                    ref.read(currentUserProvider.notifier).set(user);
                    if (context.mounted) context.go('/groups');
                      } else {
                        if (!mounted) return;
                        showDialog(
                          context: context,
                          builder: (ctx) {
                            final verification = ref.read(phoneAuthStateProvider);
                            return AlertDialog(
                              title: const Text('Enter SMS Code'),
                              content: VxTextField(
                                controller: _smsCodeController,
                                labelText: '6-digit code',
                                keyboardType: TextInputType.number,
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () async {
                                    final vId = verification.verificationId;
                                    if (vId == null) return;
                                    final confirmed = await repo.confirmPhoneCode(
                                      verificationId: vId,
                                      smsCode: _smsCodeController.text.trim(),
                                    );
                                    if (!mounted) return;
                                    if (confirmed != null) {
                                      ref.read(currentUserProvider.notifier).set(confirmed);
                                      Navigator.of(ctx).pop();
                                      if (context.mounted) context.go('/groups');
                                    }
                                  },
                                  child: const Text('Confirm'),
                                ),
                              ],
                            );
                          },
                        );
                      }
                  }),
          child: const Text('Sign in with Phone'),
          ),
        ),
        if (_isLoading) 16.heightBox,
        if (_isLoading) const CircularProgressIndicator(),
        24.heightBox,
              // Developer login
              Container(
                margin: const EdgeInsets.only(top: 32),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                ),
                child: VStack([
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFED8936).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.developer_mode,
                      color: const Color(0xFFED8936),
                      size: 24,
                    ),
                  ),
                  16.heightBox,
                  'Developer Mode'.text.lg.bold.center.make(),
                  8.heightBox,
                  'Access demo data instantly'.text.sm.color(const Color(0xFF718096)).center.make(),
                  20.heightBox,
                  Container(
                    width: double.infinity,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: const LinearGradient(
                        colors: [Color(0xFFED8936), Color(0xFFDD6B20)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFED8936).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => _handle(() async {
                                await _createDeveloperData(ref);
                                if (context.mounted) context.go('/groups');
                              }),
                      icon: const Icon(Icons.developer_mode, size: 18),
                      label: const Text('Login as Developer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                    ),
                  ),
                ]),
              ),
              24.heightBox,
            ]),
          ),
          40.heightBox,
      ]).p16().scrollVertical(),
          ],
        ),
      ),
    );
  }

  Future<void> _createDeveloperData(WidgetRef ref) async {
    // Create a fake user for development
    final devUser = AppUser(
      uid: 'dev_user_123',
      email: 'dev@expense-splitter.com',
      displayName: 'Developer User',
    );
    ref.read(currentUserProvider.notifier).set(devUser);

    // Set developer mode flag
    ref.read(developerModeProvider.notifier).setDeveloperMode(true);

    // Show success message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Developer mode activated! Sample data loaded instantly.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      
      // Navigate immediately
      context.go('/groups');
    }
  }

}

class GroupsScreen extends ConsumerStatefulWidget {
  const GroupsScreen({super.key});

  @override
  ConsumerState<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends ConsumerState<GroupsScreen> {
  final Map<String, bool> _expandedGroups = {};

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final devMode = ref.watch(developerModeProvider);
    final isDevUser = currentUser?.uid == 'dev_user_123' || devMode;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Groups'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Consumer(
            builder: (context, ref, _) {
              final themeMode = ref.watch(themeNotifierProvider);
              return IconButton(
                onPressed: () {
                  final newMode = themeMode == ThemeMode.dark 
                    ? ThemeMode.light 
                    : ThemeMode.dark;
                  ref.read(themeNotifierProvider.notifier).setThemeMode(newMode);
                },
                icon: Icon(themeMode == ThemeMode.dark 
                  ? Icons.light_mode 
                  : Icons.dark_mode),
                tooltip: 'Toggle theme',
              );
            },
          ),
          IconButton(
            onPressed: () async {
              await fb.FirebaseAuth.instance.signOut();
              context.go('/auth');
            },
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFF8FAFC),
              const Color(0xFFF1F5F9),
              const Color(0xFFE2E8F0),
              const Color(0xFFCBD5E0),
            ],
            stops: const [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Noise texture overlay
            Positioned.fill(
              child: CustomPaint(
                painter: NoisePainter(),
              ),
            ),
            // Main content
            Positioned.fill(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    // Balance indicator
                    _buildBalanceIndicator(context, ref, isDevUser),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2D3748).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.groups, color: Color(0xFF2D3748), size: 24),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Your Groups',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF2D3748),
                                      ),
                                    ),
                                    Text(
                                      'Manage your expense groups',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: const Color(0xFF718096),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => _showNewGroupDialog(context, ref),
                                icon: const Icon(Icons.add_circle_outline, color: Color(0xFF2D3748)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          // Groups list
                          isDevUser 
                            ? Consumer(
                                builder: (context, ref, child) {
                                  final groups = ref.watch(developerGroupsProvider);
                                  if (groups.isEmpty) {
                                    return Container(
                                      padding: const EdgeInsets.all(32),
                                      child: Column(
                                        children: [
                                          const Icon(Icons.inbox, size: 48, color: Color(0xFFCBD5E0)),
                                          const SizedBox(height: 16),
                                          Text(
                                            'No groups yet',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFF718096),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Create your first group to get started',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: const Color(0xFFA0AEC0),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  return Column(
                                    children: groups.map((g) => _buildGroupCard(context, ref, g)).toList(),
                                  );
                                },
                              )
                            : StreamBuilder<List<Group>>(
                                stream: ref.watch(firestoreRepositoryProvider).watchGroups(fb.FirebaseAuth.instance.currentUser!.uid),
                                builder: (context, snap) {
                                  if (snap.connectionState == ConnectionState.waiting) {
                                    return const Center(child: CircularProgressIndicator());
                                  }
                                  if (snap.hasError) {
                                    return Center(
                                      child: Column(
                                        children: [
                                          const Icon(Icons.error, size: 48, color: Color(0xFFE53E3E)),
                                          const SizedBox(height: 16),
                                          Text(
                                            'Error loading groups',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFFE53E3E),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            snap.error.toString(),
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: const Color(0xFFA0AEC0),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  final groups = snap.data ?? [];
                                  if (groups.isEmpty) {
                                    return Container(
                                      padding: const EdgeInsets.all(32),
                                      child: Column(
                                        children: [
                                          const Icon(Icons.inbox, size: 48, color: Color(0xFFCBD5E0)),
                                          const SizedBox(height: 16),
                                          Text(
                                            'No groups yet',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFF718096),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Create your first group to get started',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: const Color(0xFFA0AEC0),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  return Column(
                                    children: groups.map((g) => _buildGroupCard(context, ref, g)).toList(),
                                  );
                                },
                              ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 100), // Space for FAB
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            colors: [Color(0xFF2D3748), Color(0xFF1A202C)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2D3748).withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: () => _showNewGroupDialog(context, ref),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: const Icon(Icons.add, color: Colors.white, size: 28),
        ),
      ),
    );
  }

  Widget _buildBalanceIndicator(BuildContext context, WidgetRef ref, bool isDevUser) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          // Left side - What I Owe
          Expanded(
            child: Column(
              children: [
                Text(
                  'You Owe',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF718096),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '\$0.00',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFE53E3E),
                  ),
                ),
              ],
            ),
          ),
          // Vertical divider line
          Container(
            height: 40,
            width: 1,
            color: const Color(0xFFE2E8F0),
            margin: const EdgeInsets.symmetric(horizontal: 16),
          ),
          // Right side - What I'm Owed
          Expanded(
            child: Column(
              children: [
                Text(
                  'Owed to You',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF718096),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '\$0.00',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF48BB78),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(BuildContext context, WidgetRef ref, Group group) {
    final isExpanded = _expandedGroups[group.id] ?? false;
    final devMode = ref.watch(developerModeProvider);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            // Main card content
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                setState(() {
                  _expandedGroups[group.id] = !isExpanded;
                });
              },
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: Group name, user avatars, expand arrow
                    Row(
                      children: [
                        // Group name
                        Expanded(
                          child: Text(
                            group.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2D3748),
                            ),
                          ),
                        ),
                        // User avatars
                        Row(
                          children: group.memberUserIds.take(4).map((userId) {
                            return Container(
                              margin: const EdgeInsets.only(left: 4),
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: _getUserColor(userId),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  _getUserInitials(userId),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        if (group.memberUserIds.length > 4)
                          Container(
                            margin: const EdgeInsets.only(left: 4),
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: const Color(0xFF718096),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white,
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '+${group.memberUserIds.length - 4}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(width: 12),
                        // Expand arrow
                        AnimatedRotation(
                          turns: isExpanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: const Icon(
                            Icons.keyboard_arrow_down,
                            color: Color(0xFF718096),
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Bottom row: Balance info and add expense button
                    Row(
                      children: [
                        // Balance info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Group Balance',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: const Color(0xFF718096),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '\$0.00',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF2D3748),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Add expense button
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D3748).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: IconButton(
                            onPressed: () {
                              // TODO: Add expense functionality
                            },
                            icon: const Icon(
                              Icons.add,
                              color: Color(0xFF2D3748),
                              size: 20,
                            ),
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Expanded content - expenses list
            if (isExpanded)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FAFC),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recent Expenses',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF2D3748),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildExpensesList(context, ref, group, devMode),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpensesList(BuildContext context, WidgetRef ref, Group group, bool devMode) {
    if (devMode) {
      // Show developer expenses
      final groupExpenses = ref.watch(developerExpensesProvider(group.id));
      
      if (groupExpenses.isEmpty) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.receipt_long, size: 32, color: const Color(0xFFCBD5E0)),
              const SizedBox(height: 8),
              Text(
                'No expenses yet',
                style: TextStyle(
                  fontSize: 14,
                  color: const Color(0xFF718096),
                ),
              ),
            ],
          ),
        );
      }
      
      return Column(
        children: groupExpenses.take(3).map((expense) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _getUserColor(expense.paidByUserId),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        expense.description,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF2D3748),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Paid by ${_getUserInitials(expense.paidByUserId)} • ${_formatDate(expense.createdAtMs)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: const Color(0xFF718096),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  _formatCents(expense.amountCents),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2D3748),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      );
    } else {
      // Show real expenses from Firestore
      return StreamBuilder<List<Expense>>(
        stream: ref.watch(firestoreRepositoryProvider).watchExpenses(group.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError) {
            return Text('Error: ${snapshot.error}');
          }
          
          final expenses = snapshot.data ?? [];
          
          if (expenses.isEmpty) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.receipt_long, size: 32, color: const Color(0xFFCBD5E0)),
                  const SizedBox(height: 8),
                  Text(
                    'No expenses yet',
                    style: TextStyle(
                      fontSize: 14,
                      color: const Color(0xFF718096),
                    ),
                  ),
                ],
              ),
            );
          }
          
          return Column(
            children: expenses.take(3).map((expense) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _getUserColor(expense.paidByUserId),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            expense.description,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF2D3748),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Paid by ${_getUserInitials(expense.paidByUserId)} • ${_formatDate(expense.createdAtMs)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: const Color(0xFF718096),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _formatCents(expense.amountCents),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2D3748),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      );
    }
  }

  Color _getUserColor(String userId) {
    // Generate a consistent color based on user ID
    final colors = [
      const Color(0xFFE53E3E),
      const Color(0xFF38A169),
      const Color(0xFF3182CE),
      const Color(0xFF805AD5),
      const Color(0xFFD69E2E),
      const Color(0xFFDD6B20),
    ];
    final hash = userId.hashCode;
    return colors[hash.abs() % colors.length];
  }

  String _getUserInitials(String userId) {
    // Generate initials from user ID (for demo purposes)
    if (userId == 'dev_user_123') return 'DU';
    if (userId.startsWith('user_')) {
      final number = userId.split('_')[1];
      return 'U$number';
    }
    return userId.substring(0, 2).toUpperCase();
  }

  void _showNewGroupDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Group'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Group Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // Create group logic here
              Navigator.pop(context);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class GroupDetailScreen extends StatelessWidget {
  const GroupDetailScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final repo = ref.watch(firestoreRepositoryProvider);
      return StreamBuilder(
        stream: repo.watchGroup(groupId),
        builder: (context, groupSnap) {
          final groupTitle = groupSnap.hasData ? (groupSnap.data as Group).name : 'Group';
    return Scaffold(
            appBar: AppBar(
              title: Text(groupTitle),
              actions: [
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'rename') {
                      _showRenameDialog(context, ref, groupSnap.data as Group?);
                    } else if (value == 'members') {
                      _showMembersDialog(context, ref, groupSnap.data as Group?);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem<String>(value: 'rename', child: Text('Rename Group')),
                    const PopupMenuItem<String>(value: 'members', child: Text('Manage Members')),
                  ],
                ),
              ],
            ),
      body: VStack([
        'Balances'.text.semiBold.make(),
        8.heightBox,
              _GroupBalances(groupId: groupId),
        16.heightBox,
              HStack([
                'Expenses'.text.semiBold.make().expand(),
                ElevatedButton.icon(
                  onPressed: () => _showShareDialog(context, ref, groupSnap.data as Group?),
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                ),
                8.widthBox,
                ElevatedButton.icon(
                  onPressed: () => _sendReminder(context, ref),
                  icon: const Icon(Icons.notifications_outlined),
                  label: const Text('Remind'),
                ),
              ]),
        8.heightBox,
              _GroupExpensesList(groupId: groupId),
      ]).p16().scrollVertical(),
      floatingActionButton: FloatingActionButton(
              onPressed: () => _showAddExpenseDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
        },
      );
    });
  }

  void _showAddExpenseDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => _AddExpenseDialog(groupId: groupId),
    );
  }

  Future<void> _sendReminder(BuildContext context, WidgetRef ref) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('sendGroupReminder');
      final result = await callable.call({'groupId': groupId});
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.data['success'] 
              ? 'Reminder sent to ${result.data['tokensSent']} devices'
              : 'Failed to send reminder'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send reminder')),
        );
      }
    }
  }

  void _showShareDialog(BuildContext context, WidgetRef ref, Group? group) {
    if (group?.shareCode == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Share Group'),
        content: VStack([
          'Share code: ${group!.shareCode}'.text.bold.make(),
          8.heightBox,
          'Send this code to friends to let them join the group.'.text.gray600.make(),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              // Copy to clipboard (simplified - in real app use clipboard package)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Code copied to clipboard')),
              );
              Navigator.of(ctx).pop();
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref, Group? group) {
    if (group == null) return;
    final TextEditingController nameCtrl = TextEditingController(text: group.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Group'),
        content: VxTextField(
          controller: nameCtrl,
          labelText: 'Group name',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await ref.read(firestoreRepositoryProvider).updateGroup(
                groupId: groupId,
                name: nameCtrl.text.trim(),
              );
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showMembersDialog(BuildContext context, WidgetRef ref, Group? group) {
    if (group == null) return;
    showDialog(
      context: context,
      builder: (ctx) => _MembersDialog(group: group),
    );
  }
}

class _MembersDialog extends ConsumerStatefulWidget {
  const _MembersDialog({required this.group});
  final Group group;

  @override
  ConsumerState<_MembersDialog> createState() => _MembersDialogState();
}

class _MembersDialogState extends ConsumerState<_MembersDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manage Members'),
      content: SizedBox(
        width: 400,
        child: VStack([
          'Current members:'.text.semiBold.make(),
          8.heightBox,
          ...widget.group.memberUserIds.map((uid) => ListTile(
            title: Text(_abbr(uid)),
            subtitle: Text('Member'),
            trailing: widget.group.memberUserIds.length > 1
              ? IconButton(
                  onPressed: () => _removeMember(uid),
                  icon: const Icon(Icons.remove_circle_outline),
                )
              : null,
          )),
          16.heightBox,
          ElevatedButton.icon(
            onPressed: () => _showAddMemberDialog(),
            icon: const Icon(Icons.person_add),
            label: const Text('Add Member'),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  void _showAddMemberDialog() {
    final TextEditingController codeCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Member'),
        content: VStack([
          'Enter the 6-digit share code to add a member:'.text.make(),
          8.heightBox,
          VxTextField(
            controller: codeCtrl,
            labelText: 'Share code',
            keyboardType: TextInputType.number,
            maxLength: 6,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final user = fb.FirebaseAuth.instance.currentUser;
              if (user == null) return;
              final repo = ref.read(firestoreRepositoryProvider);
              final groupId = await repo.joinGroupByCode(
                shareCode: codeCtrl.text.trim(),
                userId: user.uid,
              );
              if (groupId != null && mounted) {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Member added successfully')),
                );
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid share code')),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _removeMember(String userId) async {
    final currentMembers = List<String>.from(widget.group.memberUserIds);
    currentMembers.remove(userId);
    await ref.read(firestoreRepositoryProvider).updateGroup(
      groupId: widget.group.id,
      memberUserIds: currentMembers,
    );
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member removed')),
      );
    }
  }

  String _abbr(String uid) {
    if (uid.length <= 6) return uid;
    return uid.substring(0, 3) + '…' + uid.substring(uid.length - 3);
  }
}

class _AddExpenseDialog extends ConsumerStatefulWidget {
  const _AddExpenseDialog({required this.groupId});
  final String groupId;

  @override
  ConsumerState<_AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends ConsumerState<_AddExpenseDialog> {
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _amountCtrl = TextEditingController();
  SplitMode _splitMode = SplitMode.equal;
  final Map<String, TextEditingController> _customAmountCtrls = {};
  final Map<String, TextEditingController> _percentCtrls = {};
  List<String> _selectedUsers = [];

  @override
  void initState() {
    super.initState();
    _selectedUsers = [fb.FirebaseAuth.instance.currentUser?.uid ?? ''];
  }

  @override
  Widget build(BuildContext context) {
    final user = fb.FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();
    
    return AlertDialog(
      title: const Text('Add Expense'),
      content: SizedBox(
        width: 400,
        child: VStack([
          VxTextField(labelText: 'Description', controller: _descCtrl),
          8.heightBox,
          VxTextField(labelText: 'Amount (e.g. 12.34)', controller: _amountCtrl, keyboardType: TextInputType.number),
          16.heightBox,
          'Split Mode'.text.semiBold.make(),
          8.heightBox,
          VStack([
            RadioListTile<SplitMode>(
              title: const Text('Equal'),
              value: SplitMode.equal,
              groupValue: _splitMode,
              onChanged: (v) => setState(() => _splitMode = v!),
            ),
            RadioListTile<SplitMode>(
              title: const Text('Custom Amounts'),
              value: SplitMode.custom,
              groupValue: _splitMode,
              onChanged: (v) => setState(() => _splitMode = v!),
            ),
            RadioListTile<SplitMode>(
              title: const Text('Percentages'),
              value: SplitMode.percent,
              groupValue: _splitMode,
              onChanged: (v) => setState(() => _splitMode = v!),
            ),
          ]),
          16.heightBox,
          _buildSplitDetails(),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _addExpense,
          child: const Text('Add'),
        ),
      ],
    );
  }

  Widget _buildSplitDetails() {
    if (_splitMode == SplitMode.equal) {
      return 'Will be split equally among selected users.'.text.gray600.make();
    }
    
    return VStack([
      'Select users to split with:'.text.semiBold.make(),
      8.heightBox,
      _buildUserSelection(),
      if (_splitMode == SplitMode.custom) ...[
        8.heightBox,
        'Custom amounts:'.text.semiBold.make(),
        8.heightBox,
        ..._selectedUsers.map((uid) => _buildCustomAmountField(uid)),
      ],
      if (_splitMode == SplitMode.percent) ...[
        8.heightBox,
        'Percentages (must total 100%):'.text.semiBold.make(),
        8.heightBox,
        ..._selectedUsers.map((uid) => _buildPercentField(uid)),
      ],
    ]);
  }

  Widget _buildUserSelection() {
    return StreamBuilder<List<Group>>(
      stream: ref.watch(firestoreRepositoryProvider).watchGroups(fb.FirebaseAuth.instance.currentUser!.uid),
      builder: (context, snap) {
        final groups = snap.data ?? [];
        final currentGroup = groups.firstWhere((g) => g.id == widget.groupId, orElse: () => const Group(id: '', name: '', memberUserIds: [], createdAtMs: 0));
        final members = currentGroup.memberUserIds;
        
        return Wrap(
          children: members.map((uid) => FilterChip(
            label: Text(_abbr(uid)),
            selected: _selectedUsers.contains(uid),
            onSelected: (selected) {
              setState(() {
                if (selected) {
                  _selectedUsers.add(uid);
                } else {
                  _selectedUsers.remove(uid);
                }
              });
            },
          )).toList(),
        );
      },
    );
  }

  Widget _buildCustomAmountField(String uid) {
    _customAmountCtrls[uid] ??= TextEditingController();
    return VxTextField(
      labelText: '${_abbr(uid)} amount',
      controller: _customAmountCtrls[uid]!,
      keyboardType: TextInputType.number,
    );
  }

  Widget _buildPercentField(String uid) {
    _percentCtrls[uid] ??= TextEditingController();
    return VxTextField(
      labelText: '${_abbr(uid)} %',
      controller: _percentCtrls[uid]!,
      keyboardType: TextInputType.number,
    );
  }

  Future<void> _addExpense() async {
    final user = fb.FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final double parsed = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    final int cents = (parsed * 100).round();
    
    Map<String, int> customAmounts = {};
    Map<String, double> percentages = {};
    
    if (_splitMode == SplitMode.custom) {
      for (final uid in _selectedUsers) {
        final amount = double.tryParse(_customAmountCtrls[uid]?.text ?? '0') ?? 0;
        customAmounts[uid] = (amount * 100).round();
      }
    } else if (_splitMode == SplitMode.percent) {
      for (final uid in _selectedUsers) {
        final percent = double.tryParse(_percentCtrls[uid]?.text ?? '0') ?? 0;
        percentages[uid] = percent / 100.0;
      }
    }
    
    final expense = Expense(
      id: 'new',
      groupId: widget.groupId,
      description: _descCtrl.text.trim(),
      amountCents: cents,
      paidByUserId: user.uid,
      splitUserIds: _selectedUsers,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      splitMode: _splitMode,
      customAmounts: customAmounts,
      percentages: percentages,
    );
    
    await ref.read(firestoreRepositoryProvider).addExpense(expense);
    Navigator.of(context).pop();
  }

  String _abbr(String uid) {
    if (uid.length <= 6) return uid;
    return uid.substring(0, 3) + '…' + uid.substring(uid.length - 3);
  }
}

class _GroupExpensesList extends ConsumerWidget {
  const _GroupExpensesList({required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expensesProvider(groupId));
    return expensesAsync.when(
      loading: () => VStack([
        const CircularProgressIndicator(),
        8.heightBox,
        'Loading expenses...'.text.center.gray600.make(),
      ]).centered(),
      error: (error, stack) => VStack([
        'Error loading expenses:'.text.color(Colors.red).make(),
        8.heightBox,
        Text('$error'),
        8.heightBox,
        ElevatedButton(
          onPressed: () => ref.refresh(expensesProvider(groupId)),
          child: const Text('Retry'),
        ),
      ]).centered(),
      data: (items) {
        if (items.isEmpty) return VStack([
          'No expenses yet'.text.semiBold.make(),
          8.heightBox,
          'Tap the + button to add an expense.'.text.gray600.make(),
        ]).centered();
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, __) => 8.heightBox,
          itemBuilder: (context, index) {
            final e = items[index];
            return _ExpenseCard(expense: e, groupId: groupId);
          },
        );
      },
    );
  }

  String _formatCents(int cents) {
    final double amount = cents / 100.0;
    return '\$' + amount.toStringAsFixed(2);
  }
}

void _showEditExpenseDialog(BuildContext context, WidgetRef ref, Expense expense) {
  final TextEditingController descCtrl = TextEditingController(text: expense.description);
  final TextEditingController amountCtrl = TextEditingController(text: (expense.amountCents / 100.0).toStringAsFixed(2));
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Edit Expense'),
      content: VStack([
        VxTextField(labelText: 'Description', controller: descCtrl),
        8.heightBox,
        VxTextField(labelText: 'Amount (e.g. 12.34)', controller: amountCtrl, keyboardType: TextInputType.number),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () async {
            final double parsed = double.tryParse(amountCtrl.text.trim()) ?? 0;
            final int cents = (parsed * 100).round();
            final updated = Expense(
              id: expense.id,
              groupId: expense.groupId,
              description: descCtrl.text.trim(),
              amountCents: cents,
              paidByUserId: expense.paidByUserId,
              splitUserIds: expense.splitUserIds,
              createdAtMs: expense.createdAtMs,
            );
            await ref.read(firestoreRepositoryProvider).updateExpense(updated);
            Navigator.of(ctx).pop();
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

class _ExpenseCard extends ConsumerStatefulWidget {
  const _ExpenseCard({required this.expense, required this.groupId});
  final Expense expense;
  final String groupId;

  @override
  ConsumerState<_ExpenseCard> createState() => _ExpenseCardState();
}

class _ExpenseCardState extends ConsumerState<_ExpenseCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.expense;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            title: Text(
              e.description,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: Color(0xFF1A202C),
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Paid by ${_getUserDisplayName(e.paidByUserId)} • ${_formatDate(e.createdAtMs)}',
                style: const TextStyle(
                  color: Color(0xFF718096),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            trailing: HStack([
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2D3748), Color(0xFF4A5568)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2D3748).withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  _formatCents(e.amountCents),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
              12.widthBox,
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2D3748).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  onPressed: () => setState(() => _isExpanded = !_isExpanded),
                  icon: Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xFF2D3748),
                    size: 20,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: const Color(0xFF2D3748),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  final repo = ref.read(firestoreRepositoryProvider);
                  if (value == 'edit') {
                    _showEditExpenseDialog(context, ref, e);
                  } else if (value == 'delete') {
                    await repo.removeExpense(groupId: widget.groupId, expenseId: e.id);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
                ],
              ),
            ]),
            onTap: () => setState(() => _isExpanded = !_isExpanded),
          ),
          if (_isExpanded) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    const Color(0xFFE2E8F0),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFE2E8F0),
                  width: 1,
                ),
              ),
              child: _ExpenseDetails(expense: e),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExpenseDetails extends StatelessWidget {
  const _ExpenseDetails({required this.expense});
  final Expense expense;

  @override
  Widget build(BuildContext context) {
    final e = expense;
    return VStack([
      // Split mode info
      HStack([
        'Split Mode:'.text.semiBold.make(),
        8.widthBox,
        Text(_getSplitModeText(e.splitMode)),
      ]),
      12.heightBox,
      
      // Amount breakdown
      'Amount Breakdown:'.text.semiBold.make(),
      8.heightBox,
      ..._getAmountBreakdown(e).map((item) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.0),
        child: HStack([
          Text(item['name']!),
          const Spacer(),
          Text(item['amount']!),
          if (item['status'] != null) ...[
            8.widthBox,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: item['status'] == 'Settled' ? Colors.green.shade100 : Colors.orange.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                item['status']!,
                style: TextStyle(
                  color: item['status'] == 'Settled' ? Colors.green.shade800 : Colors.orange.shade800,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ]),
      )),
      
      12.heightBox,
      
      // Settlement suggestions
      if (_getSettlementSuggestions(e).isNotEmpty) ...[
        'Settlement Suggestions:'.text.semiBold.make(),
        8.heightBox,
        ..._getSettlementSuggestions(e).map((suggestion) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.0),
          child: Text('• $suggestion', style: const TextStyle(fontSize: 12)),
        )),
      ],
      
      12.heightBox,
      
      // Manage participants
      'Manage Participants:'.text.semiBold.make(),
      8.heightBox,
      HStack([
        ElevatedButton.icon(
          onPressed: () => _showAddParticipantDialog(context, e),
          icon: const Icon(Icons.person_add, size: 16),
          label: const Text('Add Person'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade100,
            foregroundColor: Colors.green.shade800,
            elevation: 0,
          ),
        ),
        8.widthBox,
        ElevatedButton.icon(
          onPressed: () => _showRemoveParticipantDialog(context, e),
          icon: const Icon(Icons.person_remove, size: 16),
          label: const Text('Remove Person'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade100,
            foregroundColor: Colors.red.shade800,
            elevation: 0,
          ),
        ),
      ]),
    ]);
  }

  String _getSplitModeText(SplitMode mode) {
    switch (mode) {
      case SplitMode.equal:
        return 'Equal Split';
      case SplitMode.custom:
        return 'Custom Amounts';
      case SplitMode.percent:
        return 'Percentage Split';
    }
  }

  List<Map<String, String>> _getAmountBreakdown(Expense expense) {
    final breakdown = <Map<String, String>>[];
    
    // Add the person who paid
    breakdown.add({
      'name': '${_getUserDisplayName(expense.paidByUserId)} (paid)',
      'amount': '+${_formatCents(expense.amountCents)}',
      'status': 'Settled',
    });
    
    // Add people who owe
    for (final userId in expense.splitUserIds) {
      final amount = _getOwedAmount(expense, userId);
      final isPaidBy = userId == expense.paidByUserId;
      
      if (!isPaidBy) {
        breakdown.add({
          'name': _getUserDisplayName(userId),
          'amount': '-${_formatCents(amount)}',
          'status': 'Owes',
        });
      }
    }
    
    return breakdown;
  }

  int _getOwedAmount(Expense expense, String userId) {
    switch (expense.splitMode) {
      case SplitMode.equal:
        return (expense.amountCents / expense.splitUserIds.length).floor();
      case SplitMode.custom:
        return expense.customAmounts[userId] ?? 0;
      case SplitMode.percent:
        final percentage = expense.percentages[userId] ?? 0.0;
        return (expense.amountCents * percentage).round();
    }
  }

  List<String> _getSettlementSuggestions(Expense expense) {
    final suggestions = <String>[];
    final paidBy = expense.paidByUserId;
    final totalOwed = expense.splitUserIds
        .where((id) => id != paidBy)
        .map((id) => _getOwedAmount(expense, id))
        .fold(0, (a, b) => a + b);
    
    if (totalOwed > 0) {
      suggestions.add('${_getUserDisplayName(paidBy)} should collect ${_formatCents(totalOwed)} total');
    }
    
    return suggestions;
  }

}

// Dialog functions for managing participants
void _showAddParticipantDialog(BuildContext context, Expense expense) {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController amountController = TextEditingController();
  
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Add Person to Expense'),
      content: VStack([
        VxTextField(
          controller: nameController,
          labelText: 'Person Name',
        ),
        16.heightBox,
        VxTextField(
          controller: amountController,
          labelText: 'Amount (optional)',
          keyboardType: TextInputType.number,
        ),
        8.heightBox,
        Text(
          'If no amount is specified, it will be calculated based on split mode.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final name = nameController.text.trim();
            if (name.isNotEmpty) {
              _addParticipantToExpense(context, expense, name, amountController.text);
              Navigator.of(ctx).pop();
            }
          },
          child: const Text('Add'),
        ),
      ],
    ),
  );
}

void _showRemoveParticipantDialog(BuildContext context, Expense expense) {
  // Filter out the person who paid (they can't be removed)
  final removableParticipants = expense.splitUserIds
      .where((id) => id != expense.paidByUserId)
      .toList();
  
  if (removableParticipants.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No participants can be removed (only the person who paid remains)')),
    );
    return;
  }
  
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Remove Person from Expense'),
      content: VStack([
        'Select a person to remove:'.text.make(),
        16.heightBox,
        ...removableParticipants.map((userId) => ListTile(
          title: Text(_getUserDisplayName(userId)),
          subtitle: Text('Owes ${_formatCents(_getOwedAmount(expense, userId))}'),
          onTap: () {
            _removeParticipantFromExpense(context, expense, userId);
            Navigator.of(ctx).pop();
          },
        )),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

void _addParticipantToExpense(BuildContext context, Expense expense, String name, String amountText) {
  // For demo purposes, we'll just show a message
  // In a real app, this would update the expense in the database
  final amount = amountText.isNotEmpty ? (double.tryParse(amountText) ?? 0.0) * 100 : null;
  
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Added $name to expense${amount != null ? ' (${_formatCents(amount.round())})' : ''}'),
      backgroundColor: Colors.green,
    ),
  );
}

void _removeParticipantFromExpense(BuildContext context, Expense expense, String userId) {
  // For demo purposes, we'll just show a message
  // In a real app, this would update the expense in the database
  final userName = _getUserDisplayName(userId);
  
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Removed $userName from expense'),
      backgroundColor: Colors.orange,
    ),
  );
}

class _GroupBalances extends ConsumerWidget {
  const _GroupBalances({required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expensesProvider(groupId));
    return expensesAsync.when(
      loading: () => VStack([
        const CircularProgressIndicator(),
        8.heightBox,
        'Loading balances...'.text.center.gray600.make(),
      ]).centered(),
      error: (error, stack) => VStack([
        'Error loading balances:'.text.color(Colors.red).make(),
        8.heightBox,
        Text('$error'),
        8.heightBox,
        ElevatedButton(
          onPressed: () => ref.refresh(expensesProvider(groupId)),
          child: const Text('Retry'),
        ),
      ]).centered(),
      data: (items) {
        final settlement = _computeBalances(items);
        final int total = settlement.totalCents;
        final balances = settlement.perUser;
        final user = fb.FirebaseAuth.instance.currentUser;
        final myBalance = user == null ? 0 : (balances[user.uid] ?? 0);
        final suggestions = _suggestSettlements(balances);
        return VStack([
          Text('Total: ${_formatCents(total)}  |  You: ${_formatSigned(myBalance)}'),
          8.heightBox,
          if (suggestions.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                'Suggestions:'.text.semiBold.make(),
                ...suggestions.map((s) => Text(s)),
              ],
            ),
        ]);
      },
    );
  }

  ({int totalCents, Map<String, int> perUser}) _computeBalances(List<Expense> items) {
    int total = 0;
    final Map<String, int> balances = <String, int>{};
    for (final e in items) {
      total += e.amountCents;
      
      // credit payer
      balances[e.paidByUserId] = (balances[e.paidByUserId] ?? 0) + e.amountCents;
      
      // debit split users based on split mode
      if (e.splitMode == SplitMode.equal) {
        final int perHead = (e.amountCents / e.splitUserIds.length).floor();
        for (final uid in e.splitUserIds) {
          balances[uid] = (balances[uid] ?? 0) - perHead;
        }
      } else if (e.splitMode == SplitMode.custom) {
        for (final uid in e.splitUserIds) {
          final amount = e.customAmounts[uid] ?? 0;
          balances[uid] = (balances[uid] ?? 0) - amount;
        }
      } else if (e.splitMode == SplitMode.percent) {
        for (final uid in e.splitUserIds) {
          final percent = e.percentages[uid] ?? 0.0;
          final amount = (e.amountCents * percent).round();
          balances[uid] = (balances[uid] ?? 0) - amount;
        }
      }
    }
    return (totalCents: total, perUser: balances);
  }

  String _formatCents(int cents) {
    final double amount = cents / 100.0;
    return '\$' + amount.toStringAsFixed(2);
  }

  String _formatSigned(int cents) {
    final sign = cents >= 0 ? '+' : '-';
    final abs = cents.abs();
    final double amount = abs / 100.0;
    return sign + '\$' + amount.toStringAsFixed(2);
  }

  List<String> _suggestSettlements(Map<String, int> balances) {
    final creditors = <String, int>{};
    final debtors = <String, int>{};
    balances.forEach((uid, bal) {
      if (bal > 0) creditors[uid] = bal;
      if (bal < 0) debtors[uid] = -bal; // positive owed amount
    });
    final List<String> suggestions = [];
    final credList = creditors.entries.toList();
    final debtList = debtors.entries.toList();
    int i = 0, j = 0;
    while (i < debtList.length && j < credList.length) {
      final d = debtList[i];
      final c = credList[j];
      final int pay = d.value < c.value ? d.value : c.value;
      suggestions.add('${_abbr(d.key)} pays ${_abbr(c.key)} ${_formatCents(pay)}');
      debtList[i] = MapEntry(d.key, d.value - pay);
      credList[j] = MapEntry(c.key, c.value - pay);
      if (debtList[i].value == 0) i++;
      if (credList[j].value == 0) j++;
    }
    return suggestions;
  }

  String _abbr(String uid) {
    if (uid.length <= 6) return uid;
    return uid.substring(0, 3) + '…' + uid.substring(uid.length - 3);
  }
}

class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _isJoining = false;

  Future<void> _joinGroup() async {
    if (_codeController.text.trim().isEmpty) return;
    setState(() => _isJoining = true);
    try {
      final user = fb.FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final repo = ref.read(firestoreRepositoryProvider);
      final groupId = await repo.joinGroupByCode(
        shareCode: _codeController.text.trim(),
        userId: user.uid,
      );
      if (groupId != null && mounted) {
        context.go('/groups/$groupId');
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid share code')),
        );
      }
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join Group')),
      body: VStack([
        'Enter the 6-digit share code to join a group.'.text.make(),
        16.heightBox,
        VxTextField(
          controller: _codeController,
          labelText: 'Share code',
          keyboardType: TextInputType.number,
          maxLength: 6,
        ),
        16.heightBox,
        ElevatedButton(
          onPressed: _isJoining ? null : _joinGroup,
          child: _isJoining 
            ? const CircularProgressIndicator() 
            : const Text('Join Group'),
        ),
      ]).p16(),
    );
  }
}

class ReceiptScanScreen extends ConsumerStatefulWidget {
  const ReceiptScanScreen({super.key});

  @override
  ConsumerState<ReceiptScanScreen> createState() => _ReceiptScanScreenState();
}

class _ReceiptScanScreenState extends ConsumerState<ReceiptScanScreen> {
  bool _isProcessing = false;
  String? _recognizedText;
  int? _parsedTotalCents;
  String? _selectedGroupId;

  Future<void> _pick(ImageSource source) async {
    setState(() => _isProcessing = true);
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? file = await picker.pickImage(source: source, imageQuality: 85);
      if (file == null) return;
      final InputImage input = InputImage.fromFilePath(file.path);
      final textRecognizer = TextRecognizer();
      final RecognizedText result = await textRecognizer.processImage(input);
      await textRecognizer.close();
      final String text = result.text;
      final int? cents = _parseTotalToCents(text);
      setState(() {
        _recognizedText = text;
        _parsedTotalCents = cents;
      });
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  int? _parseTotalToCents(String text) {
    final lines = text.split('\n');
    final RegExp money = RegExp(r"(total|amount)\s*[:\-]?\s*\$?\s*([0-9]+[\.,][0-9]{2})",
        caseSensitive: false);
    for (final line in lines.reversed) {
      final m = money.firstMatch(line);
      if (m != null) {
        final String amt = m.group(2)!.replaceAll(',', '.');
        final double parsed = double.tryParse(amt) ?? 0;
        return (parsed * 100).round();
      }
    }
    // Fallback: find any monetary number
    final RegExp anyMoney = RegExp(r"\$?\s*([0-9]+[\.,][0-9]{2})");
    for (final line in lines.reversed) {
      final m = anyMoney.firstMatch(line);
      if (m != null) {
        final String amt = m.group(1)!.replaceAll(',', '.');
        final double parsed = double.tryParse(amt) ?? 0;
        return (parsed * 100).round();
      }
    }
    return null;
  }

  Future<void> _createExpenseFromScan() async {
    final repo = ref.read(firestoreRepositoryProvider);
    final user = fb.FirebaseAuth.instance.currentUser;
    if (user == null || _selectedGroupId == null || _parsedTotalCents == null) return;
    final Expense exp = Expense(
      id: 'new',
      groupId: _selectedGroupId!,
      description: 'Receipt total',
      amountCents: _parsedTotalCents!,
      paidByUserId: user.uid,
      splitUserIds: [user.uid],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await repo.addExpense(exp);
    if (!mounted) return;
    context.go('/groups/${_selectedGroupId!}');
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(firestoreRepositoryProvider);
    final user = fb.FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Receipt')),
      body: VStack([
        'Scan a receipt to auto-extract the total.'.text.make(),
        16.heightBox,
        Wrap(spacing: 8, children: [
        ElevatedButton.icon(
            onPressed: _isProcessing ? null : () => _pick(ImageSource.camera),
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('Open Camera'),
        ),
        ElevatedButton.icon(
            onPressed: _isProcessing ? null : () => _pick(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Pick from Gallery'),
        ),
        ]),
        if (_isProcessing) ...[
          16.heightBox,
          const LinearProgressIndicator(),
        ],
        if (_recognizedText != null) 16.heightBox,
        if (_parsedTotalCents != null)
          ('Detected total: ' + _formatCents(_parsedTotalCents!)).text.bold.make(),
        if (user != null && _parsedTotalCents != null) ...[
          16.heightBox,
          'Choose group'.text.bold.make(),
          StreamBuilder<List<Group>>(
            stream: repo.watchGroups(user.uid),
            builder: (context, snap) {
              final groups = snap.data ?? const <Group>[];
              if (groups.isEmpty) return const Text('No groups available.');
              _selectedGroupId ??= groups.first.id;
              return DropdownButton<String>(
                value: _selectedGroupId,
                items: [
                  for (final g in groups)
                    DropdownMenuItem<String>(value: g.id, child: Text(g.name))
                ],
                onChanged: (v) => setState(() => _selectedGroupId = v),
              );
            },
          ),
          8.heightBox,
          ElevatedButton.icon(
            onPressed: _createExpenseFromScan,
            icon: const Icon(Icons.add),
            label: const Text('Create expense'),
          ),
        ],
      ]).p16(),
    );
  }
}

// Custom painter for noise texture
class NoisePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.03)
      ..style = PaintingStyle.fill;

    final random = Random(42); // Fixed seed for consistent noise
    
    for (int i = 0; i < 2000; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final radius = random.nextDouble() * 1.5 + 0.5;
      
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

