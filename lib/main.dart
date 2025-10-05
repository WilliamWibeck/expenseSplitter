import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'models/settlement.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'notifications/notifications_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/swish_return_detector.dart';

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
  static const String _themeKey = 'theme_mode';
  
  @override
  ThemeMode build() {
    _loadTheme();
    return ThemeMode.system;
  }

  void setThemeMode(ThemeMode mode) {
    state = mode;
    _saveTheme(mode);
  }
  
  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_themeKey);
    if (themeIndex != null) {
      state = ThemeMode.values[themeIndex];
    }
  }
  
  Future<void> _saveTheme(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);
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

// Developer groups notifier - mutable for adding groups
class DeveloperGroupsNotifier extends Notifier<List<Group>> {
  @override
  List<Group> build() {
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
  }
  
  void addGroup(Group group) {
    state = [...state, group];
  }
  
  void updateGroup(Group updatedGroup) {
    state = [
      for (final group in state)
        if (group.id == updatedGroup.id) updatedGroup else group
    ];
  }
}

final developerGroupsProvider = NotifierProvider<DeveloperGroupsNotifier, List<Group>>(DeveloperGroupsNotifier.new);

// Store developer expenses in a simple map
final Map<String, List<Expense>> _developerExpensesMap = {};

// Developer expenses provider - simple provider that uses the map
final developerExpensesProvider = Provider.family<List<Expense>, String>((ref, groupId) {
  final devMode = ref.watch(developerModeProvider);
  if (!devMode) return [];
  
  // Initialize with default data if not present
  if (!_developerExpensesMap.containsKey(groupId)) {
    switch (groupId) {
      case 'dev_group_1':
        _developerExpensesMap[groupId] = [
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
        break;
      case 'dev_group_2':
        _developerExpensesMap[groupId] = [
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
        break;
      case 'dev_group_3':
        _developerExpensesMap[groupId] = [
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
        break;
      default:
        _developerExpensesMap[groupId] = [];
    }
  }
  
  return _developerExpensesMap[groupId] ?? [];
});

// Helper function to add expense to developer data
void addDeveloperExpense(String groupId, Expense expense) {
  final newExpense = Expense(
    id: 'exp_${DateTime.now().millisecondsSinceEpoch}',
    groupId: expense.groupId,
    description: expense.description,
    amountCents: expense.amountCents,
    paidByUserId: expense.paidByUserId,
    splitUserIds: expense.splitUserIds,
    createdAtMs: expense.createdAtMs,
    splitMode: expense.splitMode,
    customAmounts: expense.customAmounts,
    percentages: expense.percentages,
  );
  
  _developerExpensesMap[groupId] ??= [];
  _developerExpensesMap[groupId]!.add(newExpense);
}

// Helper function to remove expense from developer data
void removeDeveloperExpense(String groupId, String expenseId) {
  _developerExpensesMap[groupId]?.removeWhere((expense) => expense.id == expenseId);
}

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
      // Handle dynamically invited users
      if (userId.startsWith('user_phone_')) {
        final phoneDigits = userId.substring(11); // Remove 'user_phone_' prefix
        return 'User $phoneDigits'; // Show as "User 1234" for phone invites
      } else if (userId.startsWith('user_email_')) {
        final emailUser = userId.substring(11); // Remove 'user_email_' prefix
        return emailUser.split('.').map((part) => 
          part.isEmpty ? '' : '${part[0].toUpperCase()}${part.substring(1)}'
        ).join(' '); // Convert "john.doe" to "John Doe"
      } else if (userId.startsWith('user_')) {
        // Legacy support for old name-based users
        final name = userId.substring(5); // Remove 'user_' prefix
        return name.split('_').map((word) => 
          word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}'
        ).join(' ');
      }
      return userId;
  }
}

String? _getUserPhoneNumber(String userId) {
  // Map user IDs to phone numbers for demo (Swedish format)
  switch (userId) {
    case 'dev_user_123':
      return '+46701234567'; // Your number
    case 'user_alice':
      return '+46702345678';
    case 'user_bob':
      return '+46703456789';
    case 'user_charlie':
      return '+46704567890';
    case 'user_david':
      return '+46705678901';
    case 'user_eve':
      return '+46706789012';
    case 'user_frank':
      return '+46707890123';
    case 'user_grace':
      return '+46708901234';
    default:
      return null;
  }
}

// Helper class for greedy debt settlement algorithm
class _PersonBalance {
  _PersonBalance(this.personId, this.amount);
  
  final String personId;
  int amount;
}

// Helper class for overall balance calculation
class _OverallBalance {
  _OverallBalance({required this.youOwe, required this.owedToYou});
  
  final int youOwe;
  final int owedToYou;
}

// Greedy algorithm for optimal debt settlement
List<SettlementInfo> _greedyDebtSettlement(Map<String, int> balances) {
  final settlements = <SettlementInfo>[];
  
  // Create lists of creditors and debtors with their amounts
  final creditors = <_PersonBalance>[];
  final debtors = <_PersonBalance>[];
  
  balances.forEach((memberId, balance) {
    if (balance > 0) {
      creditors.add(_PersonBalance(memberId, balance));
    } else if (balance < 0) {
      debtors.add(_PersonBalance(memberId, balance.abs()));
    }
  });
  
  // Sort by amount descending (greedy: settle largest amounts first)
  creditors.sort((a, b) => b.amount.compareTo(a.amount));
  debtors.sort((a, b) => b.amount.compareTo(a.amount));
  
  // Greedy algorithm: match largest creditor with largest debtor
  while (creditors.isNotEmpty && debtors.isNotEmpty) {
    final creditor = creditors.first;
    final debtor = debtors.first;
    
    // Determine settlement amount (minimum of what creditor is owed and what debtor owes)
    final settlementAmount = creditor.amount < debtor.amount ? creditor.amount : debtor.amount;
    
    // Create settlement
    settlements.add(SettlementInfo(
      debtorId: debtor.personId,
      creditorId: creditor.personId,
      amount: settlementAmount,
    ));
    
    // Update amounts
    creditor.amount -= settlementAmount;
    debtor.amount -= settlementAmount;
    
    // Remove if fully settled
    if (creditor.amount == 0) {
      creditors.removeAt(0);
    }
    if (debtor.amount == 0) {
      debtors.removeAt(0);
    }
    
    // Re-sort if amounts changed (maintain greedy property)
    if (creditors.length > 1) {
      creditors.sort((a, b) => b.amount.compareTo(a.amount));
    }
    if (debtors.length > 1) {
      debtors.sort((a, b) => b.amount.compareTo(a.amount));
    }
  }
  
  return settlements;
}

// Swish payment helper functions
String _generateSwishDeepLink({
  required String recipientPhoneNumber,
  required int amountCents,
  required String message,
}) {
  final amountKronor = (amountCents / 100).toStringAsFixed(2);
  String phoneNumber = recipientPhoneNumber;
  
  print('🔍 DEBUG: Original phone: $recipientPhoneNumber');
  
  if (phoneNumber.startsWith('+46')) {
    phoneNumber = phoneNumber.substring(3);
  }
  if (phoneNumber.startsWith('0')) {
    phoneNumber = phoneNumber.substring(1);
  }
  phoneNumber = '46$phoneNumber'.replaceAll(RegExp(r'[\s-]'), '');
  
  print('🔍 DEBUG: Formatted phone: $phoneNumber');
  print('🔍 DEBUG: Amount: $amountKronor SEK');
  print('🔍 DEBUG: Message: $message');
  
  // Use the working web-based Swish payment URL format
  final encodedMessage = Uri.encodeComponent(message);
  final webSwishUrl = 'https://app.swish.nu/1/p/sw/?sw=$phoneNumber&amt=$amountKronor&msg=$encodedMessage';
  
  print('🔍 DEBUG: Generated payment URL: $webSwishUrl');
  
  return webSwishUrl;
}

void _launchSwishPayment(String swishUrl) async {
  print('🚀 LAUNCHING SWISH with URL: $swishUrl');
  
  try {
    final uri = Uri.parse(swishUrl);
    print('🔍 Parsed URI scheme: ${uri.scheme}');
    print('🔍 Parsed URI host: ${uri.host}');
    print('🔍 Parsed URI query: ${uri.query}');
    print('🔍 Parsed URI queryParameters: ${uri.queryParameters}');
    
    // Try the primary URL first
    bool success = false;
    print('🔍 Checking if URL can be launched...');
    if (await canLaunchUrl(uri)) {
      print('✅ URL can be launched, attempting launch...');
      
      // For HTTPS URLs, try opening in external application first (to trigger Swish app)
      if (uri.scheme == 'https') {
        success = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!success) {
          // If external app launch fails, try platform default (might open in browser then redirect)
          print('🔄 External app launch failed, trying platform default...');
          success = await launchUrl(uri, mode: LaunchMode.platformDefault);
        }
      } else {
        // For swish:// scheme, use external application mode
        success = await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      
      if (success) {
        print('✅ Swish URL launched successfully');
        return;
      } else {
        print('❌ Launch returned false despite canLaunchUrl being true');
      }
    } else {
      print('❌ URL cannot be launched');
    }
    
    // If primary fails, try alternative URL formats
    print('Primary URL failed, trying alternatives...');
    
    // Extract phone and amount from the original URL for fallbacks
    final originalUri = Uri.parse(swishUrl);
    final phone = originalUri.queryParameters['phone'] ?? originalUri.queryParameters['sw'];
    final amount = originalUri.queryParameters['amount'] ?? originalUri.queryParameters['amt'];
    
    // Alternative formats to try (both web and app schemes)
    final alternatives = [
      'https://app.swish.nu/1/p/sw/?sw=$phone&amt=$amount',  // Web payment format without message
      'https://app.swish.nu/1/r/sw/?sw=$phone&amt=$amount',  // Web request format without message
      'swish://payment?phone=$phone&amount=$amount',        // Basic app scheme
      'swish://request?phone=$phone&amount=$amount',        // App request scheme
      'swish://payment?number=$phone&amount=$amount',       // Alternative parameter names
      'swish://send?phone=$phone&amount=$amount',           // Different action
      'swish://transfer?phone=$phone&amount=$amount',       // Transfer instead of payment
      'swish://pay?phone=$phone&amount=$amount',            // Pay action
      'swish://?phone=$phone&amount=$amount',               // No specific action
    ];
    
    for (final altUrl in alternatives) {
      try {
        final altUri = Uri.parse(altUrl);
        print('Trying alternative: $altUrl');
        if (await canLaunchUrl(altUri)) {
          success = await launchUrl(altUri, mode: LaunchMode.externalApplication);
          if (success) {
            print('Alternative Swish URL launched successfully: $altUrl');
            return;
          }
        }
      } catch (e) {
        print('Alternative failed: $e');
      }
    }
    
    // Final fallback: just open Swish app
    print('All alternatives failed, opening Swish app directly...');
    final fallbackUri = Uri.parse('swish://');
    if (await canLaunchUrl(fallbackUri)) {
      await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      print('Opened Swish app, but could not pre-fill payment details');
    } else {
      print('Cannot open Swish app. Make sure Swish is installed.');
    }
    
  } catch (e) {
    print('Error launching Swish: $e');
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
  return '\$${amount.toStringAsFixed(2)}';
}

Future<void> _showSwishPaymentDialog({
  required BuildContext context,
  required String targetPhone,
  required int amountCents,
  required String message,
  required bool isOutgoingPayment,
}) async {
  final amountKronor = (amountCents / 100).toStringAsFixed(2);
  final deepLinkUrl = _generateSwishDeepLink(
    recipientPhoneNumber: targetPhone,
    amountCents: amountCents,
    message: message,
  );
  
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.payment, color: Theme.of(context).primaryColor),
          SizedBox(width: 8),
          Text('Swish Payment'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Amount: $amountKronor SEK',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          Text('To: $targetPhone'),
          Text('Message: $message'),
          SizedBox(height: 16),
          Text(
            'This will open Swish to send a payment.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            _launchSwishPayment(deepLinkUrl);
            Navigator.pop(context);
          },
          child: Text('Open Swish'),
        ),
      ],
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              path: ':groupId/analysis',
              name: 'group_analysis',
              builder: (context, state) => GroupAnalysisScreen(
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
        surface: Color(0xFFF7FAFC), // Pure white
        error: Color(0xFFE53E3E), // Subtle red accent
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Color(0xFF1A202C), // Dark text
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
        surface: Color(0xFF1A202C), // Very dark background
        error: Color(0xFFFC8181), // Light red accent
        onPrimary: Color(0xFF1A202C), // Dark text on light
        onSecondary: Color(0xFF1A202C), // Dark text on light
        onSurface: Color(0xFFE2E8F0), // Light text
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
      title: 'dela',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        return SwishReturnWrapper(child: child ?? const SizedBox.shrink());
      },
    );
  }
}

class SwishReturnWrapper extends StatefulWidget {
  final Widget child;
  
  const SwishReturnWrapper({super.key, required this.child});
  
  @override
  State<SwishReturnWrapper> createState() => _SwishReturnWrapperState();
}

class _SwishReturnWrapperState extends State<SwishReturnWrapper> with WidgetsBindingObserver {
  final SwishReturnDetector _detector = SwishReturnDetector();
  
  @override
  void initState() {
    super.initState();
    _initializeDetector();
  }
  
  @override
  void dispose() {
    _detector.dispose();
    super.dispose();
  }
  
  Future<void> _initializeDetector() async {
    await _detector.loadPersistentData();
    _detector.initialize(
      onReturnFromSwish: _showSwishReturnDialog,
    );
  }
  
  void _showSwishReturnDialog(List<PendingSwishPayment> pendingPayments) {
    if (pendingPayments.isEmpty || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.payment, color: Colors.blue.shade600),
            const SizedBox(width: 8),
            const Text('Confirm Swish Payments'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Did you complete these Swish payments?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            ...pendingPayments.map((payment) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '\$${(payment.amountCents / 100).toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'To: ${_getDisplayName(payment.creditorId)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward, color: Colors.blue.shade600),
                ],
              ),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _detector.clearAllPayments();
            },
            child: const Text('No, Not Yet'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _confirmAllPayments(pendingPayments);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text(
              'Yes, All Completed',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmAllPayments(List<PendingSwishPayment> payments) {
    _detector.clearAllPayments();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${payments.length} payment(s) marked as completed! 🎉'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  String _getDisplayName(String userId) {
    if (userId == 'dev_user_123') return 'You';
    if (userId == 'developer_user') return 'Developer';
    return 'User ${userId.substring(0, min(8, userId.length))}';
  }
  
  @override
  Widget build(BuildContext context) {
    return widget.child;
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
  const _AuthScreenContent();

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
        ],
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: Theme.of(context).brightness == Brightness.dark
                ? [
                    const Color(0xFF0F1419),
                    const Color(0xFF1A202C),
                    const Color(0xFF2D3748),
                    const Color(0xFF1A202C),
                  ]
                : [
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
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF1A202C).withOpacity(0.9)
                  : Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF2D3748).withOpacity(0.3)
                    : Colors.white.withOpacity(0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.black.withOpacity(0.3)
                      : Colors.black.withOpacity(0.08),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                ),
                BoxShadow(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.black.withOpacity(0.2)
                      : Colors.black.withOpacity(0.04),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: VStack([
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                      : const Color(0xFF2D3748).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 48,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Theme.of(context).colorScheme.primary
                      : const Color(0xFF2D3748),
                ),
              ),
              32.heightBox,
              'dela'.text.xl5.bold.color(Theme.of(context).colorScheme.onSurface).center.make(),
        16.heightBox,
              'Split expenses effortlessly with friends and family'
            .text
                  .lg
                  .color(Theme.of(context).colorScheme.onSurface.withOpacity(0.7))
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
                    colors: Theme.of(context).brightness == Brightness.dark
                        ? [const Color(0xFF2D3748), const Color(0xFF1A202C)]
                        : [Colors.white, Colors.grey.shade50],
                  ),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF4A5568)
                        : const Color(0xFFE2E8F0), 
                    width: 1.5
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.black.withOpacity(0.2)
                          : Colors.black.withOpacity(0.04),
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
                  label: Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Theme.of(context).colorScheme.onSurface
                          : const Color(0xFF1A202C),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Theme.of(context).brightness == Brightness.dark
                        ? Theme.of(context).colorScheme.onSurface
                        : const Color(0xFF1A202C),
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
                  gradient: LinearGradient(
                    colors: Theme.of(context).brightness == Brightness.dark
                        ? [const Color(0xFF4A5568), const Color(0xFF2D3748)]
                        : [const Color(0xFF1A202C), const Color(0xFF2D3748)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.black.withOpacity(0.3)
                          : Colors.black.withOpacity(0.15),
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
            colors: Theme.of(context).brightness == Brightness.dark
                ? [
                    const Color(0xFF0F1419),
                    const Color(0xFF1A202C),
                    const Color(0xFF2D3748),
                    const Color(0xFF1A202C),
                  ]
                : [
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
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF1A202C).withOpacity(0.8)
                            : Colors.white.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF2D3748).withOpacity(0.3)
                              : Colors.white.withOpacity(0.2),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.black.withOpacity(0.3)
                                : Colors.black.withOpacity(0.06),
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
                                  color: Theme.of(context).brightness == Brightness.dark
                                      ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                                      : const Color(0xFF2D3748).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.groups, 
                                  color: Theme.of(context).brightness == Brightness.dark
                                      ? Theme.of(context).colorScheme.primary
                                      : const Color(0xFF2D3748), 
                                  size: 24
                                ),
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
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                    Text(
                                      'Manage your expense groups',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceIndicator(BuildContext context, WidgetRef ref, bool isDevUser) {
    // Calculate actual amounts owed and owing
    final balanceData = _calculateOverallBalance(ref, isDevUser);
    print('💰 DEBUG Balance: You owe ${_formatCents(balanceData.youOwe)}, Owed to you ${_formatCents(balanceData.owedToYou)}');
    
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
                  _formatCents(balanceData.youOwe),
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
                  _formatCents(balanceData.owedToYou),
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

  _OverallBalance _calculateOverallBalance(WidgetRef ref, bool isDevUser) {
    int totalYouOwe = 0;
    int totalOwedToYou = 0;
    
    if (isDevUser) {
      // In dev mode, calculate from developer groups
      final groups = ref.watch(developerGroupsProvider);
      final currentUserId = 'dev_user_123';
      
      for (final group in groups) {
        final expenses = ref.watch(developerExpensesProvider(group.id));
        final settlements = _greedyDebtSettlement(_calculateBalancesForGroup(group, expenses, currentUserId));
        
        // Sum up what the current user owes and is owed
        for (final settlement in settlements) {
          if (settlement.debtorId == currentUserId) {
            totalYouOwe += settlement.amount;
          } else if (settlement.creditorId == currentUserId) {
            totalOwedToYou += settlement.amount;
          }
        }
      }
    } else {
      // In real mode, this would calculate from Firestore
      // For now, return zeros as the real implementation would be more complex
      totalYouOwe = 0;
      totalOwedToYou = 0;
    }
    
    return _OverallBalance(youOwe: totalYouOwe, owedToYou: totalOwedToYou);
  }

  Map<String, int> _calculateBalancesForGroup(Group group, List<Expense> expenses, String currentUserId) {
    final balances = <String, int>{};
    
    // Calculate net balance for each member
    for (final memberId in group.memberUserIds) {
      final totalPaid = expenses.where((e) => e.paidByUserId == memberId)
          .fold<int>(0, (sum, e) => sum + e.amountCents);
      final totalOwed = expenses.fold<int>(0, (sum, expense) {
        return sum + _getOwedAmountForCard(expense, memberId);
      });
      balances[memberId] = totalPaid - totalOwed;
    }
    
    return balances;
  }

  Widget _buildGroupCard(BuildContext context, WidgetRef ref, Group group) {
    final isExpanded = _expandedGroups[group.id] ?? false;
    final devMode = ref.watch(developerModeProvider);
    
    // Get expenses for this group to calculate balance
    final expenses = devMode 
      ? ref.watch(developerExpensesProvider(group.id))
      : <Expense>[];
    
    // Calculate user's balance in this group
    final userBalance = _calculateUserBalanceInGroup(group, expenses);
    
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
                        // Group name - now clickable to navigate to group analysis
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              context.go('/groups/${group.id}/analysis');
                            },
                            child: Text(
                              group.name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2D3748),
                              ),
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
                    // Bottom row: Balance info, detailed analysis button, and add expense button
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
                                userBalance == 0 
                                  ? 'Even' 
                                  : userBalance > 0 
                                    ? '+${_formatCents(userBalance)}' 
                                    : _formatCents(userBalance),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: userBalance == 0 
                                    ? const Color(0xFF2D3748)
                                    : userBalance > 0 
                                      ? Colors.green.shade700
                                      : Colors.red.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Share Group button
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                _shareGroupLink(context, group);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                                child: const Icon(
                                  Icons.share,
                                  color: Color(0xFF10B981),
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Group Settings button
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D3748).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                _showGroupSettingsDialog(context, ref, group);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                                child: const Icon(
                                  Icons.settings,
                                  color: Color(0xFF2D3748),
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Detailed Analysis button
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3182CE).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                context.go('/groups/${group.id}/analysis');
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                                child: const Icon(
                                  Icons.analytics,
                                  color: Color(0xFF3182CE),
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Swish Settle button
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B4F72).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _handleGroupSettle(context, ref, group),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                                child: const Icon(
                                  Icons.payment,
                                  color: Color(0xFF1B4F72),
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Add expense button
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D3748).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                barrierDismissible: true,
                                builder: (ctx) => Dialog(
                                  backgroundColor: Colors.transparent,
                                  child: Container(
                                    constraints: const BoxConstraints(maxWidth: 320),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).brightness == Brightness.dark 
                                          ? const Color(0xFF2D3748) 
                                          : Theme.of(context).colorScheme.surface,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Theme.of(context).brightness == Brightness.dark
                                              ? Colors.black.withOpacity(0.3)
                                              : Colors.black.withOpacity(0.1),
                                          blurRadius: 20,
                                          offset: const Offset(0, 10),
                                        ),
                                      ],
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Header
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF4F46E5).withOpacity(0.2),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: const Icon(
                                                  Icons.add_circle_outline,
                                                  color: Color(0xFF6366F1),
                                                  size: 24,
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Add New Expense',
                                                      style: TextStyle(
                                                        fontSize: 20,
                                                        fontWeight: FontWeight.w600,
                                                        color: Theme.of(context).brightness == Brightness.dark
                                                            ? Colors.white
                                                            : const Color(0xFF1A202C),
                                                      ),
                                                    ),
                                                    SizedBox(height: 4),
                                                    Text(
                                                      'Choose how to add your expense',
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        color: Theme.of(context).brightness == Brightness.dark
                                                            ? const Color(0xFFA0AEC0)
                                                            : const Color(0xFF718096),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 24),
                                          
                                          // Manual entry option
                                          Container(
                                            width: double.infinity,
                                            margin: const EdgeInsets.only(bottom: 12),
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                onTap: () {
                                                  Navigator.of(ctx).pop();
                                                  showDialog(
                                                    context: context,
                                                    builder: (dialogCtx) => _AddExpenseDialog(groupId: group.id),
                                                  );
                                                },
                                                borderRadius: BorderRadius.circular(16),
                                                child: Container(
                                                  padding: const EdgeInsets.all(20),
                                                  decoration: BoxDecoration(
                                                    border: Border.all(
                                                      color: Theme.of(context).brightness == Brightness.dark
                                                          ? const Color(0xFF4A5568)
                                                          : const Color(0xFFE2E8F0),
                                                      width: 1.5,
                                                    ),
                                                    borderRadius: BorderRadius.circular(16),
                                                    gradient: LinearGradient(
                                                      begin: Alignment.topLeft,
                                                      end: Alignment.bottomRight,
                                                      colors: Theme.of(context).brightness == Brightness.dark
                                                          ? [
                                                              const Color(0xFF10B981).withOpacity(0.15),
                                                              const Color(0xFF059669).withOpacity(0.08),
                                                            ]
                                                          : [
                                                              const Color(0xFF10B981).withOpacity(0.05),
                                                              const Color(0xFF059669).withOpacity(0.02),
                                                            ],
                                                    ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.all(12),
                                                        decoration: BoxDecoration(
                                                          color: Theme.of(context).brightness == Brightness.dark
                                                              ? const Color(0xFF10B981).withOpacity(0.2)
                                                              : const Color(0xFF10B981).withOpacity(0.1),
                                                          borderRadius: BorderRadius.circular(12),
                                                        ),
                                                        child: Icon(
                                                          Icons.edit_outlined,
                                                          color: Theme.of(context).brightness == Brightness.dark
                                                              ? const Color(0xFF34D399)
                                                              : const Color(0xFF059669),
                                                          size: 24,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 16),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text(
                                                              'Manual Entry',
                                                              style: TextStyle(
                                                                fontSize: 16,
                                                                fontWeight: FontWeight.w600,
                                                                color: Theme.of(context).brightness == Brightness.dark
                                                                    ? Colors.white
                                                                    : const Color(0xFF1A202C),
                                                              ),
                                                            ),
                                                            SizedBox(height: 4),
                                                            Text(
                                                              'Enter expense details manually',
                                                              style: TextStyle(
                                                                fontSize: 14,
                                                                color: Theme.of(context).brightness == Brightness.dark
                                                                    ? const Color(0xFFA0AEC0)
                                                                    : const Color(0xFF718096),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      Icon(
                                                        Icons.chevron_right,
                                                        color: Theme.of(context).brightness == Brightness.dark
                                                            ? const Color(0xFFA0AEC0)
                                                            : const Color(0xFF718096),
                                                        size: 20,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          
                                          // Receipt scan option
                                          Container(
                                            width: double.infinity,
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                onTap: () {
                                                  Navigator.of(ctx).pop();
                                                  context.go('/scan');
                                                },
                                                borderRadius: BorderRadius.circular(16),
                                                child: Container(
                                                  padding: const EdgeInsets.all(20),
                                                  decoration: BoxDecoration(
                                                    border: Border.all(
                                                      color: Theme.of(context).brightness == Brightness.dark
                                                          ? const Color(0xFF4A5568)
                                                          : const Color(0xFFE2E8F0),
                                                      width: 1.5,
                                                    ),
                                                    borderRadius: BorderRadius.circular(16),
                                                    gradient: LinearGradient(
                                                      begin: Alignment.topLeft,
                                                      end: Alignment.bottomRight,
                                                      colors: Theme.of(context).brightness == Brightness.dark
                                                          ? [
                                                              const Color(0xFF8B5CF6).withOpacity(0.15),
                                                              const Color(0xFF7C3AED).withOpacity(0.08),
                                                            ]
                                                          : [
                                                              const Color(0xFF8B5CF6).withOpacity(0.05),
                                                              const Color(0xFF7C3AED).withOpacity(0.02),
                                                            ],
                                                    ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.all(12),
                                                        decoration: BoxDecoration(
                                                          color: Theme.of(context).brightness == Brightness.dark
                                                              ? const Color(0xFF8B5CF6).withOpacity(0.2)
                                                              : const Color(0xFF8B5CF6).withOpacity(0.1),
                                                          borderRadius: BorderRadius.circular(12),
                                                        ),
                                                        child: Icon(
                                                          Icons.camera_alt_outlined,
                                                          color: Theme.of(context).brightness == Brightness.dark
                                                              ? const Color(0xFFA78BFA)
                                                              : const Color(0xFF7C3AED),
                                                          size: 24,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 16),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text(
                                                              'Scan Receipt',
                                                              style: TextStyle(
                                                                fontSize: 16,
                                                                fontWeight: FontWeight.w600,
                                                                color: Theme.of(context).brightness == Brightness.dark
                                                                    ? Colors.white
                                                                    : const Color(0xFF1A202C),
                                                              ),
                                                            ),
                                                            SizedBox(height: 4),
                                                            Text(
                                                              'Use camera to capture receipt',
                                                              style: TextStyle(
                                                                fontSize: 14,
                                                                color: Theme.of(context).brightness == Brightness.dark
                                                                    ? const Color(0xFFA0AEC0)
                                                                    : const Color(0xFF718096),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      Icon(
                                                        Icons.chevron_right,
                                                        color: Theme.of(context).brightness == Brightness.dark
                                                            ? const Color(0xFFA0AEC0)
                                                            : const Color(0xFF718096),
                                                        size: 20,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                              child: const Icon(
                                Icons.add,
                                color: Color(0xFF2D3748),
                                size: 20,
                              ),
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
    final displayName = _getUserDisplayName(userId);
    
    // Split into words and take first letter of each
    final words = displayName.split(' ');
    if (words.length >= 2) {
      // For multi-word names, take first letter of first two words
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    } else if (words.isNotEmpty && words[0].length >= 2) {
      // For single word names, take first two letters
      return words[0].substring(0, 2).toUpperCase();
    } else {
      // Fallback to first letter
      return displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    }
  }

  void _copyShareCode(BuildContext context, String shareCode) {
    if (shareCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No share code available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    // Copy to clipboard
    Clipboard.setData(ClipboardData(text: shareCode)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Share code "$shareCode" copied to clipboard!'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'Close',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    });
  }

  void _shareGroupLink(BuildContext context, Group group) {
    if (group.shareCode == null || group.shareCode!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No share code available for this group'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Generate a shareable link
    final shareLink = 'https://expense-splitter.app/join/${group.shareCode}';
    final shareText = '''
Join "${group.name}" on Expense Splitter!

Use this link: $shareLink
Or enter share code: ${group.shareCode}

Expense Splitter makes it easy to split bills and track expenses with friends!
''';

    // In a real app, you would use Share.share() from the share_plus package
    // For now, we'll show a dialog with the shareable content
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.share, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Share Group'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Share this message with others:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey.shade800
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.shade600
                      : Colors.grey.shade300,
                ),
              ),
              child: Text(
                shareText,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              // Copy the share message to clipboard
              Clipboard.setData(ClipboardData(text: shareText)).then((_) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Share message copied to clipboard!'),
                    backgroundColor: Colors.green,
                  ),
                );
              });
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
          ),
        ],
      ),
    );
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
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              
              final devMode = ref.read(developerModeProvider);
              final currentUser = ref.read(currentUserProvider);
              
              if (devMode && currentUser != null) {
                // In developer mode, add to the developer groups provider
                final newGroup = Group(
                  id: 'dev_group_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  memberUserIds: [currentUser.uid],
                  createdAtMs: DateTime.now().millisecondsSinceEpoch,
                  shareCode: '${DateTime.now().millisecondsSinceEpoch % 1000000}'.padLeft(6, '0'),
                );
                ref.read(developerGroupsProvider.notifier).addGroup(newGroup);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Group "$name" created successfully')),
                );
              } else {
                // Real mode - use Firestore
                final user = fb.FirebaseAuth.instance.currentUser;
                if (user != null) {
                  try {
                    final repo = ref.read(firestoreRepositoryProvider);
                    await repo.createGroup(
                      name: name,
                      memberUserIds: [user.uid],
                    );
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Group "$name" created successfully')),
                    );
                  } catch (e) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error creating group: $e')),
                    );
                  }
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _handleGroupSettle(BuildContext context, WidgetRef ref, Group group) {
    final devMode = ref.watch(developerModeProvider);
    
    if (!devMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Swish settlement is only available in developer mode'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // Get expenses for this group
    final expenses = ref.watch(developerExpensesProvider(group.id));
    
    if (expenses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No expenses to settle'),
          backgroundColor: Colors.blue,
        ),
      );
      return;
    }
    
    // Calculate settlements
    final settlements = _calculateGroupSettlementsForCard(group, expenses);
    
    if (settlements.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All settled up! No payments needed.'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }
    
    // Show settlement options with enhanced tracking
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EnhancedSettlementBottomSheet(
        group: group,
        settlements: settlements,
      ),
    );
  }

  void _showGroupSettingsDialog(BuildContext context, WidgetRef ref, Group group) {
    const String currentUserId = 'dev_user_123'; // In real app, get from auth
    final bool isOwner = group.memberUserIds.isNotEmpty && group.memberUserIds.first == currentUserId;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.settings, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text('Group Settings'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Group Info Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.group, size: 20, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('Group Information', style: TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text('Name: ${group.name}', style: TextStyle(fontSize: 14)),
                      const SizedBox(height: 4),
                      Text('ID: ${group.id}', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text('Created: ${_formatDate(group.createdAtMs)}', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      if (isOwner) ...[
                        const SizedBox(height: 4),
                        Text('Owner: You', style: TextStyle(fontSize: 12, color: Colors.green.shade700, fontWeight: FontWeight.w500)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Share Group Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.share, size: 20, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('Share Group', style: TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Share Code
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Share Code',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).brightness == Brightness.dark
                                        ? Colors.grey.shade800
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Theme.of(context).brightness == Brightness.dark
                                          ? Colors.grey.shade600
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Text(
                                    group.shareCode ?? 'N/A',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'monospace',
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Copy Code Button
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                              ),
                            ),
                            child: IconButton(
                              onPressed: () => _copyShareCode(context, group.shareCode ?? ''),
                              icon: Icon(
                                Icons.copy,
                                color: Theme.of(context).colorScheme.primary,
                                size: 20,
                              ),
                              tooltip: 'Copy Share Code',
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Share Link
                      Container(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _shareGroupLink(context, group),
                          icon: const Icon(Icons.link, size: 18),
                          label: const Text('Share Link'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Share this link with others to invite them to join the group',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Group Members Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.people, size: 20, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('Members (${group.memberUserIds.length})', style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          // Add Member Button
                          IconButton(
                            onPressed: () => _showAddMemberDialog(context, ref, group),
                            icon: Icon(Icons.person_add, color: Theme.of(context).colorScheme.primary),
                            tooltip: 'Add Member',
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...group.memberUserIds.map((userId) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: _getUserColor(userId),
                              child: Text(
                                _getUserInitials(userId),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _getUserDisplayName(userId),
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                  ),
                                  if (userId == group.memberUserIds.first)
                                    Text(
                                      'Owner',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green.shade600,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Remove Member Button (only for owner and not for themselves)
                            if (isOwner && userId != currentUserId)
                              IconButton(
                                onPressed: () => _showRemoveMemberDialog(context, ref, group, userId),
                                icon: Icon(Icons.person_remove, color: Colors.red.shade600, size: 20),
                                tooltip: 'Remove ${_getUserDisplayName(userId)}',
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                padding: EdgeInsets.zero,
                              ),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/groups/${group.id}/analysis');
            },
            icon: const Icon(Icons.analytics, size: 18),
            label: const Text('View Analysis'),
          ),
        ],
      ),
    );
  }

  void _showAddMemberDialog(BuildContext context, WidgetRef ref, Group group) {
    final TextEditingController contactController = TextEditingController();
    String contactMethod = 'phone'; // Default to phone
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.person_add, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Text('Invite Member'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Invite someone to join this group:'),
              const SizedBox(height: 16),
              // Contact method selector
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Phone Number', style: TextStyle(fontSize: 14)),
                      value: 'phone',
                      groupValue: contactMethod,
                      onChanged: (value) {
                        setState(() {
                          contactMethod = value!;
                          contactController.clear();
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Email', style: TextStyle(fontSize: 14)),
                      value: 'email',
                      groupValue: contactMethod,
                      onChanged: (value) {
                        setState(() {
                          contactMethod = value!;
                          contactController.clear();
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: contactController,
                decoration: InputDecoration(
                  labelText: contactMethod == 'phone' ? 'Phone Number' : 'Email Address',
                  hintText: contactMethod == 'phone' ? '+46 70 123 45 67' : 'example@email.com',
                  border: const OutlineInputBorder(),
                  prefixIcon: Icon(contactMethod == 'phone' ? Icons.phone : Icons.email),
                ),
                keyboardType: contactMethod == 'phone' ? TextInputType.phone : TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue.shade600, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        contactMethod == 'phone' 
                          ? 'An invitation will be sent via SMS. They\'ll join with their registered name.'
                          : 'An invitation will be sent via email. They\'ll join with their registered name.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final contact = contactController.text.trim();
                if (contact.isNotEmpty) {
                  Navigator.of(context).pop();
                  _inviteMemberToGroup(context, ref, group, contact, contactMethod);
                }
              },
              child: const Text('Send Invitation'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRemoveMemberDialog(BuildContext context, WidgetRef ref, Group group, String userId) {
    final memberName = _getUserDisplayName(userId);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange.shade600),
            const SizedBox(width: 8),
            const Text('Remove Member'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to remove $memberName from the group?'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange.shade600, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone. The member will lose access to the group and its expenses.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _removeMemberFromGroup(context, ref, group, userId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _inviteMemberToGroup(BuildContext context, WidgetRef ref, Group group, String contact, String contactMethod) {
    // Simulate invitation process - in a real app, this would:
    // 1. Send SMS/email invitation with group join link
    // 2. When user accepts, they register with their name
    // 3. Their user profile provides the display name
    
    // For demo purposes, generate a user based on contact info
    String newUserId;
    String simulatedName;
    
    if (contactMethod == 'phone') {
      // Extract number for ID generation  
      final cleanNumber = contact.replaceAll(RegExp(r'[^0-9]'), '');
      newUserId = 'user_phone_${cleanNumber.substring(cleanNumber.length > 6 ? cleanNumber.length - 6 : 0)}';
      simulatedName = 'User ${cleanNumber.substring(cleanNumber.length > 4 ? cleanNumber.length - 4 : 0)}'; // Last 4 digits
    } else {
      // Use email for ID generation
      final emailUser = contact.split('@').first.toLowerCase();
      newUserId = 'user_email_$emailUser';
      simulatedName = emailUser.split('.').map((part) => 
        part.isEmpty ? '' : '${part[0].toUpperCase()}${part.substring(1)}'
      ).join(' ');
    }
    
    // Check if user already exists (by contact)
    if (group.memberUserIds.contains(newUserId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('This ${contactMethod} is already a member of this group'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // Add the new member to the group
    final updatedMemberIds = [...group.memberUserIds, newUserId];
    final updatedGroup = group.copyWith(memberUserIds: updatedMemberIds);
    
    // Update the developer groups provider
    ref.read(developerGroupsProvider.notifier).updateGroup(updatedGroup);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Invitation sent to $contact. They will appear as "$simulatedName" when they join.'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _removeMemberFromGroup(BuildContext context, WidgetRef ref, Group group, String userId) {
    final memberName = _getUserDisplayName(userId);
    
    // Remove the member from the group
    final updatedMemberIds = group.memberUserIds.where((id) => id != userId).toList();
    final updatedGroup = group.copyWith(memberUserIds: updatedMemberIds);
    
    // Update the developer groups provider
    ref.read(developerGroupsProvider.notifier).updateGroup(updatedGroup);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$memberName has been removed from the group'),
        backgroundColor: Colors.red,
      ),
    );
  }
  
  List<SettlementInfo> _calculateGroupSettlementsForCard(Group group, List<Expense> expenses) {
    final balances = <String, int>{};
    
    // Calculate net balance for each member
    for (final memberId in group.memberUserIds) {
      final totalPaid = expenses.where((e) => e.paidByUserId == memberId)
          .fold<int>(0, (sum, e) => sum + e.amountCents);
      final totalOwed = expenses.fold<int>(0, (sum, expense) {
        return sum + _getOwedAmountForCard(expense, memberId);
      });
      balances[memberId] = totalPaid - totalOwed;
    }
    
    // Use greedy algorithm to minimize number of transactions
    return _greedyDebtSettlement(balances);
  }
  
  int _getOwedAmountForCard(Expense expense, String userId) {
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
  
  // Helper function to calculate user's balance in a specific group
  int _calculateUserBalanceInGroup(Group group, List<Expense> expenses) {
    final settlements = _calculateGroupSettlementsForCard(group, expenses);
    final currentUserId = fb.FirebaseAuth.instance.currentUser?.uid ?? 'dev_user_123';
    
    int userBalance = 0;
    for (final settlement in settlements) {
      if (settlement.debtorId == currentUserId) {
        userBalance -= settlement.amount; // User owes money (negative)
      } else if (settlement.creditorId == currentUserId) {
        userBalance += settlement.amount; // User is owed money (positive)
      }
    }
    return userBalance;
  }
}

class _EnhancedSettlementBottomSheet extends StatelessWidget {
  const _EnhancedSettlementBottomSheet({
    required this.group,
    required this.settlements,
  });
  
  final Group group;
  final List<SettlementInfo> settlements;

  @override
  Widget build(BuildContext context) {
    final currentUserId = fb.FirebaseAuth.instance.currentUser?.uid ?? 'dev_user_123';
    final isGroupCreator = group.memberUserIds.isNotEmpty && group.memberUserIds.first == currentUserId;
    
    // Calculate settlement statistics for smart privacy display
    final totalAmount = settlements.fold<int>(0, (sum, s) => sum + s.amount);
    final myPayments = settlements.where((s) => s.debtorId == currentUserId).toList();
    final paymentsToMe = settlements.where((s) => s.creditorId == currentUserId).toList();
    
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 50,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header with smart privacy info
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(
                  'Settlement Session',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  group.name,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 16),
                
                // Smart privacy summary
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildSummaryItem(
                            'Total Outstanding',
                            _formatCents(totalAmount),
                            Icons.account_balance_wallet,
                            Colors.blue.shade700,
                          ),
                          Container(
                            height: 40,
                            width: 1,
                            color: Colors.blue.shade200,
                          ),
                          _buildSummaryItem(
                            'Transactions',
                            '${settlements.length}',
                            Icons.swap_horiz,
                            Colors.blue.shade700,
                          ),
                        ],
                      ),
                      if (myPayments.isNotEmpty || paymentsToMe.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Divider(),
                        const SizedBox(height: 8),
                        Text(
                          'Your Personal Summary',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            if (myPayments.isNotEmpty)
                              _buildSummaryItem(
                                'You Pay',
                                _formatCents(myPayments.fold<int>(0, (sum, s) => sum + s.amount)),
                                Icons.arrow_upward,
                                Colors.red.shade600,
                              ),
                            if (paymentsToMe.isNotEmpty)
                              _buildSummaryItem(
                                'You Receive',
                                _formatCents(paymentsToMe.fold<int>(0, (sum, s) => sum + s.amount)),
                                Icons.arrow_downward,
                                Colors.green.shade600,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Settlements list
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: settlements.length,
              itemBuilder: (context, index) {
                final settlement = settlements[index];
                return _buildEnhancedSettlementCard(context, settlement, currentUserId);
              },
            ),
          ),
          
          // Bottom actions for group creator
          if (isGroupCreator) ...[
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Divider(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.admin_panel_settings, 
                           color: Colors.amber.shade700, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Group Creator Options',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.amber.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _sendSettlementReminders(context, group);
                      },
                      icon: const Icon(Icons.notifications, size: 18),
                      label: const Text('Send Gentle Reminders'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.amber.shade700,
                        side: BorderSide(color: Colors.amber.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          // Bottom padding
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildEnhancedSettlementCard(BuildContext context, SettlementInfo settlement, String currentUserId) {
    final debtorPhone = _getUserPhoneNumber(settlement.debtorId);
    final creditorPhone = _getUserPhoneNumber(settlement.creditorId);
    final canUseSwish = debtorPhone != null && creditorPhone != null;
    final isMyPayment = settlement.debtorId == currentUserId;
    final isPaymentToMe = settlement.creditorId == currentUserId;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isMyPayment 
            ? Colors.orange.shade50 
            : isPaymentToMe 
                ? Colors.green.shade50 
                : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMyPayment 
              ? Colors.orange.shade200 
              : isPaymentToMe 
                  ? Colors.green.shade200 
                  : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_getUserDisplayName(settlement.debtorId)} → ${_getUserDisplayName(settlement.creditorId)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatCents(settlement.amount),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isMyPayment 
                            ? Colors.orange.shade800 
                            : isPaymentToMe 
                                ? Colors.green.shade800 
                                : const Color(0xFF1B4F72),
                      ),
                    ),
                  ],
                ),
              ),
              if (isMyPayment)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'YOU PAY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade800,
                    ),
                  ),
                )
              else if (isPaymentToMe)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'TO YOU',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Action buttons - show different options based on relationship to payment
          if (isMyPayment) ...[
            // User needs to pay
            Row(
              children: [
                if (canUseSwish) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _handleSwishPaymentFromCard(context, settlement);
                      },
                      icon: const Icon(Icons.payment, size: 18),
                      label: const Text('Pay with Swish'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1B4F72),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _showSettlementGames(context, settlement);
                    },
                    icon: const Icon(Icons.casino, size: 18),
                    label: const Text('Play Game'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else if (isPaymentToMe) ...[
            // Payment is coming to user
            Text(
              'Waiting for payment from ${_getUserDisplayName(settlement.debtorId)}',
              style: TextStyle(
                color: Colors.green.shade700,
                fontStyle: FontStyle.italic,
              ),
            ),
          ] else ...[
            // Third party payment
            Text(
              'Between other group members',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          
          // Universal mark as paid option (visible to payer or receiver)
          if (isMyPayment || isPaymentToMe) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _showMarkAsSettledDialog(context, settlement);
                },
                icon: const Icon(Icons.check, size: 18),
                label: Text(isMyPayment ? 'Mark as Sent' : 'Confirm Received'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isMyPayment ? Colors.orange.shade700 : Colors.green.shade700,
                  side: BorderSide(
                    color: isMyPayment ? Colors.orange.shade300 : Colors.green.shade300,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
          
          if (!canUseSwish && isMyPayment)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Phone numbers needed for Swish payments',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _sendSettlementReminders(BuildContext context, Group group) {
    // This would trigger push notifications to group members
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.notifications, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Gentle reminders sent to group members'),
            ),
          ],
        ),
        backgroundColor: Colors.amber.shade600,
      ),
    );
  }

  void _showMarkAsSettledDialog(BuildContext context, SettlementInfo settlement) {
    final currentUserId = fb.FirebaseAuth.instance.currentUser?.uid ?? 'dev_user_123';
    final isMyPayment = settlement.debtorId == currentUserId;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isMyPayment ? 'Confirm Payment Sent' : 'Confirm Payment Received'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isMyPayment 
                  ? 'Have you sent the payment?' 
                  : 'Have you received the payment?',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '${_getUserDisplayName(settlement.debtorId)} → ${_getUserDisplayName(settlement.creditorId)}',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            Text(
              _formatCents(settlement.amount),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isMyPayment 
                        ? 'Payment marked as sent to ${_getUserDisplayName(settlement.creditorId)}'
                        : 'Payment confirmed as received from ${_getUserDisplayName(settlement.debtorId)}',
                  ),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text(
              isMyPayment ? 'Confirm Sent' : 'Confirm Received',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCents(int cents) {
    final double amount = cents / 100.0;
    return '\$${amount.toStringAsFixed(2)}';
  }

  String _getUserDisplayName(String userId) {
    if (userId == 'dev_user_123') return 'You';
    if (userId == 'developer_user') return 'Developer';
    return 'User ${userId.substring(0, 8)}';
  }

  String? _getUserPhoneNumber(String userId) {
    if (userId == 'dev_user_123') return '+46701234567';
    if (userId == 'developer_user') return '+46709876543';
    return null;
  }

  Future<void> _handleSwishPaymentFromCard(BuildContext context, SettlementInfo settlement) async {
    final targetPhone = _getUserPhoneNumber(settlement.creditorId);
    if (targetPhone == null) return;
    
    final message = 'Expense settlement - ${_getUserDisplayName(settlement.debtorId)} to ${_getUserDisplayName(settlement.creditorId)}';
    
    // Track this payment for return detection
    final pendingPayment = PendingSwishPayment(
      id: '${settlement.debtorId}_${settlement.creditorId}_${DateTime.now().millisecondsSinceEpoch}',
      debtorId: settlement.debtorId,
      creditorId: settlement.creditorId,
      amountCents: settlement.amount,
      groupId: group.id,
      timestamp: DateTime.now(),
    );
    
    SwishReturnDetector().trackSwishLaunch(pendingPayment);
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Swish Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Opening Swish to send ${_formatCents(settlement.amount)} to $targetPhone'),
            const SizedBox(height: 16),
            Text('Message: $message'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.blue.shade600, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'We\'ll ask you to confirm when you return to the app!',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // Clear the tracked payment since user cancelled
              SwishReturnDetector().clearPayment(pendingPayment.id);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // In a real app, this would launch Swish
              _launchSwishPayment('swish://payment?phone=$targetPhone&amount=${settlement.amount / 100}&message=${Uri.encodeComponent(message)}');
            },
            child: const Text('Open Swish'),
          ),
        ],
      ),
    );
  }

  void _showSettlementGames(BuildContext context, SettlementInfo settlement) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Settlement Games'),
        content: const Text('Settlement games would open here!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
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
    return '${uid.substring(0, 3)}…${uid.substring(uid.length - 3)}';
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
    // Initialize with current user ID if available, otherwise use a default
    final currentUserId = fb.FirebaseAuth.instance.currentUser?.uid ?? 'developer_user';
    _selectedUsers = [currentUserId];
  }

  @override
  Widget build(BuildContext context) {
    final devMode = ref.watch(developerModeProvider);
    final user = fb.FirebaseAuth.instance.currentUser;
    
    // In developer mode, always show the dialog regardless of Firebase auth state
    if (!devMode && user == null) return const SizedBox.shrink();
    
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.receipt_long, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          const Text('Add New Expense'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: VStack([
            // Description field
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: TextField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'e.g., Dinner at restaurant',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                ),
              ),
            ),
            16.heightBox,
            
            // Amount field
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  hintText: 'e.g., 25.50',
                  prefixText: '\$',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                ),
              ),
            ),
            24.heightBox,
            
            // Split mode section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.group, size: 20, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'How to split this expense?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  RadioListTile<SplitMode>(
                    title: const Text('Split Equally'),
                    subtitle: const Text('Divide amount equally among all participants'),
                    value: SplitMode.equal,
                    groupValue: _splitMode,
                    onChanged: (v) => setState(() => _splitMode = v!),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<SplitMode>(
                    title: const Text('Custom Amounts'),
                    subtitle: const Text('Set specific amounts for each person'),
                    value: SplitMode.custom,
                    groupValue: _splitMode,
                    onChanged: (v) => setState(() => _splitMode = v!),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<SplitMode>(
                    title: const Text('Percentages'),
                    subtitle: const Text('Split by percentage (must total 100%)'),
                    value: SplitMode.percent,
                    groupValue: _splitMode,
                    onChanged: (v) => setState(() => _splitMode = v!),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            16.heightBox,
            _buildSplitDetails(),
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _canAddExpense() ? _addExpense : null,
          icon: const Icon(Icons.add),
          label: const Text('Add Expense'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
      ],
    );
  }
  
  bool _canAddExpense() {
    return _descCtrl.text.trim().isNotEmpty && 
           _amountCtrl.text.trim().isNotEmpty &&
           _selectedUsers.isNotEmpty;
  }

  Widget _buildSplitDetails() {
    if (_splitMode == SplitMode.equal) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade600, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Amount will be split equally among all selected participants',
                style: TextStyle(color: Colors.green.shade700),
              ),
            ),
          ],
        ),
      );
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: VStack([
        Row(
          children: [
            Icon(Icons.people, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Select participants:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        12.heightBox,
        _buildUserSelection(),
        if (_splitMode == SplitMode.custom && _selectedUsers.isNotEmpty) ...[
          16.heightBox,
          const Divider(),
          8.heightBox,
          Row(
            children: [
              Icon(Icons.attach_money, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Set custom amounts:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          8.heightBox,
          ..._selectedUsers.map((uid) => _buildCustomAmountField(uid)),
        ],
        if (_splitMode == SplitMode.percent && _selectedUsers.isNotEmpty) ...[
          16.heightBox,
          const Divider(),
          8.heightBox,
          Row(
            children: [
              Icon(Icons.percent, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Set percentages (must total 100%):',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          8.heightBox,
          ..._selectedUsers.map((uid) => _buildPercentField(uid)),
        ],
      ]),
    );
  }

  Widget _buildUserSelection() {
    final devMode = ref.watch(developerModeProvider);
    
    if (devMode) {
      // In developer mode, use developer groups
      final groups = ref.watch(developerGroupsProvider);
      final currentGroup = groups.firstWhere(
        (g) => g.id == widget.groupId, 
        orElse: () => const Group(id: '', name: '', memberUserIds: [], createdAtMs: 0)
      );
      final members = currentGroup.memberUserIds;
      
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: members.map((uid) {
            final isSelected = _selectedUsers.contains(uid);
            
            return InkWell(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _selectedUsers.remove(uid);
                  } else {
                    _selectedUsers.add(uid);
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: isSelected,
                      onChanged: (selected) {
                        setState(() {
                          if (selected == true) {
                            _selectedUsers.add(uid);
                          } else {
                            _selectedUsers.remove(uid);
                          }
                        });
                      },
                      activeColor: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Text(
                        _abbr(uid)[0].toUpperCase(),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _abbr(uid),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          color: isSelected 
                            ? Theme.of(context).colorScheme.primary 
                            : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (isSelected)
                      Icon(
                        Icons.check_circle,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      );
    } else {
      // Real mode - use Firestore
      return StreamBuilder<List<Group>>(
        stream: ref.watch(firestoreRepositoryProvider).watchGroups(fb.FirebaseAuth.instance.currentUser!.uid),
        builder: (context, snap) {
          final groups = snap.data ?? [];
          final currentGroup = groups.firstWhere((g) => g.id == widget.groupId, orElse: () => const Group(id: '', name: '', memberUserIds: [], createdAtMs: 0));
          final members = currentGroup.memberUserIds;
          
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: members.map((uid) {
                final isSelected = _selectedUsers.contains(uid);
                
                return InkWell(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedUsers.remove(uid);
                      } else {
                        _selectedUsers.add(uid);
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          value: isSelected,
                          onChanged: (selected) {
                            setState(() {
                              if (selected == true) {
                                _selectedUsers.add(uid);
                              } else {
                                _selectedUsers.remove(uid);
                              }
                            });
                          },
                          activeColor: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: Text(
                            _abbr(uid)[0].toUpperCase(),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _abbr(uid),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              color: isSelected 
                                ? Theme.of(context).colorScheme.primary 
                                : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Icon(
                            Icons.check_circle,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        },
      );
    }
  }

  Widget _buildCustomAmountField(String uid) {
    _customAmountCtrls[uid] ??= TextEditingController();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: _customAmountCtrls[uid]!,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: '${_abbr(uid)} amount',
          prefixIcon: const Icon(Icons.attach_money),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface,
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Amount required';
          }
          if (double.tryParse(value) == null) {
            return 'Invalid amount';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildPercentField(String uid) {
    _percentCtrls[uid] ??= TextEditingController();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: _percentCtrls[uid]!,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: '${_abbr(uid)} percentage',
          prefixIcon: const Icon(Icons.percent),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface,
          suffixText: '%',
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Percentage required';
          }
          final percent = double.tryParse(value);
          if (percent == null) {
            return 'Invalid percentage';
          }
          if (percent < 0 || percent > 100) {
            return 'Must be 0-100%';
          }
          return null;
        },
      ),
    );
  }

  Future<void> _addExpense() async {
    final devMode = ref.read(developerModeProvider);
    final user = fb.FirebaseAuth.instance.currentUser;
    
    // In real mode, we need a Firebase user. In dev mode, we can use a default
    if (!devMode && user == null) return;
    
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
    
    // Use Firebase user ID in real mode, or a default in developer mode
    final paidByUserId = devMode ? 'developer_user' : (user?.uid ?? 'developer_user');
    
    final expense = Expense(
      id: 'new',
      groupId: widget.groupId,
      description: _descCtrl.text.trim(),
      amountCents: cents,
      paidByUserId: paidByUserId,
      splitUserIds: _selectedUsers,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      splitMode: _splitMode,
      customAmounts: customAmounts,
      percentages: percentages,
    );
    
    if (devMode) {
      // Add to developer data
      addDeveloperExpense(widget.groupId, expense);
      // Force refresh the provider by invalidating it
      ref.invalidate(developerExpensesProvider(widget.groupId));
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense added successfully')),
      );
    } else {
      // Real mode - use Firestore
      try {
        await ref.read(firestoreRepositoryProvider).addExpense(expense);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense added successfully')),
        );
      } catch (e) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding expense: $e')),
        );
      }
    }
  }

  String _abbr(String uid) {
    if (uid.length <= 6) return uid;
    return '${uid.substring(0, 3)}…${uid.substring(uid.length - 3)}';
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
        if (items.isEmpty) {
          return VStack([
          'No expenses yet'.text.semiBold.make(),
          8.heightBox,
          'Tap the + button to add an expense.'.text.gray600.make(),
        ]).centered();
        }
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
            onTap: () => context.go('/groups/${widget.groupId}/expense/${e.id}'),
          ),
        ],
      ),
    );
  }
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
    return '\$${amount.toStringAsFixed(2)}';
  }

  String _formatSigned(int cents) {
    final sign = cents >= 0 ? '+' : '-';
    final abs = cents.abs();
    final double amount = abs / 100.0;
    return '$sign\$${amount.toStringAsFixed(2)}';
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
    return '${uid.substring(0, 3)}…${uid.substring(uid.length - 3)}';
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
        context.go('/groups/$groupId/analysis');
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
    final user = fb.FirebaseAuth.instance.currentUser;
    if (user == null || _selectedGroupId == null || _parsedTotalCents == null) return;
    
    final expense = Expense(
      id: 'new',
      groupId: _selectedGroupId!,
      description: 'Receipt total',
      amountCents: _parsedTotalCents!,
      paidByUserId: user.uid,
      splitUserIds: [user.uid],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    
    // Check if we're in developer mode
    final devMode = ref.read(developerModeProvider);
    
    if (devMode) {
      // Add to developer data
      addDeveloperExpense(_selectedGroupId!, expense);
      // Force refresh the provider by invalidating it
      ref.invalidate(developerExpensesProvider(_selectedGroupId!));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipt expense added successfully')),
      );
      context.go('/groups/${_selectedGroupId!}/analysis');
    } else {
      // Real mode - use Firestore
      try {
        final repo = ref.read(firestoreRepositoryProvider);
        await repo.addExpense(expense);
        if (!mounted) return;
        context.go('/groups/${_selectedGroupId!}/analysis');
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating expense: $e')),
        );
      }
    }
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
          ('Detected total: ${_formatCents(_parsedTotalCents!)}').text.bold.make(),
        if (user != null && _parsedTotalCents != null) ...[
          16.heightBox,
          'Choose group'.text.bold.make(),
          // Groups dropdown that works with developer mode
          Consumer(
            builder: (context, ref, _) {
              final devMode = ref.watch(developerModeProvider);
              
              if (devMode) {
                // Developer mode - use developer groups
                final groups = ref.watch(developerGroupsProvider);
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
              } else {
                // Real mode - use Firestore
                return StreamBuilder<List<Group>>(
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
                );
              }
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

class GroupAnalysisScreen extends ConsumerWidget {
  const GroupAnalysisScreen({
    super.key,
    required this.groupId,
  });
  
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devMode = ref.watch(developerModeProvider);
    
    // Get group data
    final group = devMode 
      ? ref.watch(developerGroupsProvider).firstWhere(
          (g) => g.id == groupId,
          orElse: () => const Group(id: '', name: '', memberUserIds: [], createdAtMs: 0),
        )
      : null;
    
    // Get expenses data
    final expenses = devMode 
      ? ref.watch(developerExpensesProvider(groupId))
      : <Expense>[];

    if (group == null || group.id.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Group Analysis'),
        ),
        body: const Center(
          child: Text('Group not found'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text('${group.name} - Analysis'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Overview Cards
            _buildOverviewSection(context, group, expenses),
            
            const SizedBox(height: 24),
            
            // Member Summary
            _buildMemberSummarySection(context, group, expenses),
            
            const SizedBox(height: 24),
            
            // All Expenses Detailed View
            _buildAllExpensesSection(context, expenses),
            
            const SizedBox(height: 24),
            
            // Settlement Recommendations
            _buildSettlementSection(context, group, expenses),
          ],
        ),
      ),
    );
  }
  
  Widget _buildOverviewSection(BuildContext context, Group group, List<Expense> expenses) {
    final totalAmount = expenses.fold<int>(0, (sum, expense) => sum + expense.amountCents);
    final activeMembersCount = group.memberUserIds.length;
    final avgPerPerson = activeMembersCount > 0 ? totalAmount / activeMembersCount : 0;
    
    // Calculate settlements for more useful metrics
    final settlements = _calculateGroupSettlementsDetailed(group, expenses);
    final pendingSettlements = settlements.length;
    
    // Calculate current user's balance
    final currentUserId = fb.FirebaseAuth.instance.currentUser?.uid ?? 'dev_user_123';
    int userBalance = 0;
    for (final settlement in settlements) {
      if (settlement.debtorId == currentUserId) {
        userBalance -= settlement.amount; // User owes money
      } else if (settlement.creditorId == currentUserId) {
        userBalance += settlement.amount; // User is owed money
      }
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.analytics, color: Theme.of(context).colorScheme.primary, size: 24),
            const SizedBox(width: 8),
            Text(
              'Group Overview',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildOverviewCard(
                context,
                'Total Spent',
                _formatCents(totalAmount),
                Icons.attach_money,
                Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildOverviewCard(
                context,
                'Pending Settlements',
                pendingSettlements.toString(),
                Icons.account_balance_wallet,
                Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildOverviewCard(
                context,
                'Your Balance',
                userBalance == 0 
                  ? 'Even' 
                  : userBalance > 0 
                    ? '+${_formatCents(userBalance)}' 
                    : _formatCents(userBalance),
                userBalance == 0 
                  ? Icons.check_circle 
                  : userBalance > 0 
                    ? Icons.trending_up 
                    : Icons.trending_down,
                userBalance == 0 
                  ? Colors.green 
                  : userBalance > 0 
                    ? Colors.blue 
                    : Colors.red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildOverviewCard(
                context,
                'Avg per Person',
                _formatCents(avgPerPerson.round()),
                Icons.person,
                Colors.purple,
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildOverviewCard(BuildContext context, String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: color.withOpacity(0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildMemberSummarySection(BuildContext context, Group group, List<Expense> expenses) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.people, color: Theme.of(context).colorScheme.primary, size: 24),
            const SizedBox(width: 8),
            Text(
              'Member Summary',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...group.memberUserIds.map((memberId) => _buildMemberCard(context, memberId, expenses)),
      ],
    );
  }
  
  Widget _buildMemberCard(BuildContext context, String memberId, List<Expense> expenses) {
    final memberExpenses = expenses.where((e) => e.paidByUserId == memberId).toList();
    final totalPaid = memberExpenses.fold<int>(0, (sum, e) => sum + e.amountCents);
    final totalOwed = expenses.fold<int>(0, (sum, expense) {
      return sum + _getOwedAmount(expense, memberId);
    });
    final netBalance = totalPaid - totalOwed;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  _getUserDisplayName(memberId)[0].toUpperCase(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getUserDisplayName(memberId),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${memberExpenses.length} expenses paid',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: netBalance >= 0 ? Colors.green.shade100 : Colors.red.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  netBalance >= 0 
                    ? '+${_formatCents(netBalance.abs())}'
                    : '-${_formatCents(netBalance.abs())}',
                  style: TextStyle(
                    color: netBalance >= 0 ? Colors.green.shade800 : Colors.red.shade800,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildMemberStat('Paid', _formatCents(totalPaid), Colors.green),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMemberStat('Owes', _formatCents(totalOwed), Colors.orange),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMemberStat(
                  'Balance', 
                  netBalance >= 0 
                    ? '+${_formatCents(netBalance.abs())}'
                    : '-${_formatCents(netBalance.abs())}',
                  netBalance >= 0 ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildMemberStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
  
  Widget _buildAllExpensesSection(BuildContext context, List<Expense> expenses) {
    if (expenses.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long, color: Theme.of(context).colorScheme.primary, size: 24),
              const SizedBox(width: 8),
              Text(
                'All Expenses',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.shadow.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Icon(Icons.receipt_long, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(
                  'No expenses yet',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start adding expenses to see detailed analysis',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.receipt_long, color: Theme.of(context).colorScheme.primary, size: 24),
            const SizedBox(width: 8),
            Text(
              'All Expenses (${expenses.length})',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...expenses.map((expense) => _buildDetailedExpenseCard(context, expense)),
      ],
    );
  }
  
  Widget _buildDetailedExpenseCard(BuildContext context, Expense expense) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expense.description,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Paid by ${_getUserDisplayName(expense.paidByUserId)} • ${_formatDate(expense.createdAtMs)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.primary.withOpacity(0.85),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  _formatCents(expense.amountCents),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Split Details (${_getSplitModeText(expense.splitMode)})',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                ...expense.splitUserIds.map((userId) => _buildParticipantRow(context, expense, userId)),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildParticipantRow(BuildContext context, Expense expense, String userId) {
    final owedAmount = _getOwedAmount(expense, userId);
    final isPayer = userId == expense.paidByUserId;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: isPayer 
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text(
              _getUserDisplayName(userId)[0].toUpperCase(),
              style: TextStyle(
                color: isPayer 
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _getUserDisplayName(userId),
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          Text(
            _formatCents(owedAmount),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isPayer 
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
          if (isPayer)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                'PAID',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildSettlementSection(BuildContext context, Group group, List<Expense> expenses) {
    final settlements = _calculateGroupSettlementsDetailed(group, expenses);
    
    // Debug: Print settlement info
    print('DEBUG: Group ${group.name} has ${expenses.length} expenses');
    print('DEBUG: Calculated ${settlements.length} settlements');
    for (final settlement in settlements) {
      print('DEBUG: ${_getUserDisplayName(settlement.debtorId)} owes ${_formatCents(settlement.amount)} to ${_getUserDisplayName(settlement.creditorId)}');
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.handshake, color: Theme.of(context).colorScheme.primary, size: 24),
            const SizedBox(width: 8),
            Text(
              'Settlement Recommendations',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (settlements.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Column(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade600, size: 48),
                const SizedBox(height: 16),
                Text(
                  'All Settled Up!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Everyone is even. No payments needed.',
                  style: TextStyle(
                    color: Colors.green.shade600,
                  ),
                ),
              ],
            ),
          )
        else
          ...settlements.map((settlement) => _buildSettlementCard(context, settlement)),
      ],
    );
  }
  
  Widget _buildSettlementCard(BuildContext context, SettlementInfo settlement) {
    final debtorPhone = _getUserPhoneNumber(settlement.debtorId);
    final creditorPhone = _getUserPhoneNumber(settlement.creditorId);
    final canUseSwish = debtorPhone != null && creditorPhone != null;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.arrow_forward, color: Colors.orange.shade800, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_getUserDisplayName(settlement.debtorId)} owes ${_getUserDisplayName(settlement.creditorId)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatCents(settlement.amount),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (canUseSwish && settlement.debtorId == 'dev_user_123') ...[  // Only show when you owe money
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _handleSwishPayment(context, settlement),
                    icon: Icon(Icons.payment, size: 20, color: Colors.white),
                    label: Text('Pay with Swish'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B4F72), // Swish blue
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showSettlementGames(context, settlement),
                  icon: Icon(Icons.casino, size: 20),
                  label: Text('Play Game'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _markAsSettled(context, settlement),
                  icon: const Icon(Icons.check, size: 20),
                  label: const Text('Mark as Paid'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade800,
                    side: BorderSide(color: Colors.orange.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (!canUseSwish)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Phone numbers needed for Swish payments',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  Future<void> _handleSwishPayment(BuildContext context, SettlementInfo settlement) async {
    // Only handle outgoing payments (when you owe money)
    final targetPhone = _getUserPhoneNumber(settlement.creditorId);
    
    if (targetPhone == null) return;
    
    final message = 'Expense settlement - ${_getUserDisplayName(settlement.debtorId)} to ${_getUserDisplayName(settlement.creditorId)}';
    
    // Show Swish payment dialog
    await _showSwishPaymentDialog(
      context: context,
      targetPhone: targetPhone,
      amountCents: settlement.amount,
      message: message,
      isOutgoingPayment: true, // Always true now
    );
  }
  
  void _markAsSettled(BuildContext context, SettlementInfo settlement) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mark payment as completed?',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '${_getUserDisplayName(settlement.debtorId)} → ${_getUserDisplayName(settlement.creditorId)}',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            Text(
              _formatCents(settlement.amount),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              'Who is confirming this payment?',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // For now, just show confirmation - in real app this would update database
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Payment marked as completed: ${_getUserDisplayName(settlement.debtorId)} → ${_getUserDisplayName(settlement.creditorId)}',
                  ),
                  backgroundColor: Colors.green,
                  action: SnackBarAction(
                    label: 'UNDO',
                    textColor: Colors.white,
                    onPressed: () {
                      // Future: Add undo functionality
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Payment unmarked'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    },
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Confirm Payment', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
  
  // Helper function to calculate user's balance in a specific group
  int _calculateUserBalanceInGroup(Group group, List<Expense> expenses) {
    final settlements = _calculateGroupSettlementsDetailed(group, expenses);
    final currentUserId = fb.FirebaseAuth.instance.currentUser?.uid ?? 'dev_user_123';
    
    int userBalance = 0;
    for (final settlement in settlements) {
      if (settlement.debtorId == currentUserId) {
        userBalance -= settlement.amount; // User owes money (negative)
      } else if (settlement.creditorId == currentUserId) {
        userBalance += settlement.amount; // User is owed money (positive)
      }
    }
    return userBalance;
  }
  
  List<SettlementInfo> _calculateGroupSettlementsDetailed(Group group, List<Expense> expenses) {
    final balances = <String, int>{};
    
    // Calculate net balance for each member
    for (final memberId in group.memberUserIds) {
      final totalPaid = expenses.where((e) => e.paidByUserId == memberId)
          .fold<int>(0, (sum, e) => sum + e.amountCents);
      final totalOwed = expenses.fold<int>(0, (sum, expense) {
        return sum + _getOwedAmount(expense, memberId);
      });
      balances[memberId] = totalPaid - totalOwed;
    }
    
    // Use greedy algorithm to minimize number of transactions
    return _greedyDebtSettlement(balances);
  }
  
  // Keep the old method for compatibility with other parts of the app
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

class ExpenseDetailScreen extends ConsumerWidget {
  const ExpenseDetailScreen({
    super.key,
    required this.groupId,
    required this.expenseId,
  });
  
  final String groupId;
  final String expenseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devMode = ref.watch(developerModeProvider);
    
    // Get the expense data
    final expense = devMode 
      ? ref.watch(developerExpensesProvider(groupId)).firstWhere(
          (e) => e.id == expenseId,
          orElse: () => const Expense(
            id: '',
            groupId: '',
            description: 'Not found',
            amountCents: 0,
            paidByUserId: '',
            splitUserIds: [],
            createdAtMs: 0,
            splitMode: SplitMode.equal,
            customAmounts: {},
            percentages: {},
          ),
        )
      : null; // For now, focus on developer mode

    if (expense == null || expense.id.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Expense Not Found'),
        ),
        body: const Center(
          child: Text('Expense not found'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(expense.description),
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'edit') {
                _showEditExpenseDialog(context, ref, expense);
              } else if (value == 'delete') {
                _showDeleteConfirmationDialog(context, ref, expense);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 18),
                    SizedBox(width: 8),
                    Text('Edit Expense'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete Expense', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Expense Header Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.primary.withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.receipt_long,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              expense.description,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatDate(expense.createdAtMs),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total Amount',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            _formatCents(expense.amountCents),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Split Method',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            _getSplitModeText(expense.splitMode),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Paid By Section
            _buildSection(
              context,
              'Paid By',
              Icons.payment,
              Colors.green,
              [_buildPaidByCard(context, expense)],
            ),
            
            const SizedBox(height: 24),
            
            // Participants Section
            _buildSection(
              context,
              'Participants & Split',
              Icons.people,
              Theme.of(context).colorScheme.primary,
              expense.splitUserIds.map((userId) => _buildParticipantDetailCard(context, expense, userId)).toList(),
            ),
            
            const SizedBox(height: 24),
            
            // Settlement Section
            _buildSection(
              context,
              'Settlement Summary',
              Icons.swap_horiz,
              Colors.orange,
              [_buildSettlementSection(context, expense)],
            ),
            
            const SizedBox(height: 24),
            
            // Statistics Section
            _buildSection(
              context,
              'Expense Statistics',
              Icons.analytics,
              Colors.blue,
              [_buildStatisticsCard(context, expense)],
            ),
            
            const SizedBox(height: 32),
            
            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showEditExpenseDialog(context, ref, expense),
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit Expense'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showDeleteConfirmationDialog(context, ref, expense),
                    icon: const Icon(Icons.delete),
                    label: const Text('Delete'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSection(BuildContext context, String title, IconData icon, Color color, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
  
  Widget _buildPaidByCard(BuildContext context, Expense expense) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.green.shade200,
            child: Text(
              _getUserDisplayName(expense.paidByUserId)[0].toUpperCase(),
              style: TextStyle(
                color: Colors.green.shade800,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getUserDisplayName(expense.paidByUserId),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.green.shade800,
                  ),
                ),
                Text(
                  'Paid the full amount',
                  style: TextStyle(
                    color: Colors.green.shade600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.shade200,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _formatCents(expense.amountCents),
              style: TextStyle(
                color: Colors.green.shade800,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildParticipantDetailCard(BuildContext context, Expense expense, String userId) {
    final owedAmount = _getOwedAmount(expense, userId);
    final isPayer = userId == expense.paidByUserId;
    final netAmount = isPayer ? expense.amountCents - owedAmount : -owedAmount;
    
    Color cardColor;
    Color borderColor;
    Color textColor;
    String statusText;
    
    if (isPayer) {
      cardColor = Colors.green.shade50;
      borderColor = Colors.green.shade200;
      textColor = Colors.green.shade800;
      statusText = 'Gets back ${_formatCents(netAmount.abs())}';
    } else if (netAmount < 0) {
      cardColor = Colors.orange.shade50;
      borderColor = Colors.orange.shade200;
      textColor = Colors.orange.shade800;
      statusText = 'Owes ${_formatCents(netAmount.abs())}';
    } else {
      cardColor = Colors.blue.shade50;
      borderColor = Colors.blue.shade200;
      textColor = Colors.blue.shade800;
      statusText = 'All settled';
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: borderColor,
            child: Text(
              _getUserDisplayName(userId)[0].toUpperCase(),
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getUserDisplayName(userId),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: textColor,
                  ),
                ),
                Text(
                  statusText,
                  style: TextStyle(
                    color: textColor.withOpacity(0.8),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatCents(owedAmount),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: textColor,
                ),
              ),
              if (expense.splitMode == SplitMode.percent)
                Text(
                  '${((expense.percentages[userId] ?? 0) * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: textColor.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildSettlementSection(BuildContext context, Expense expense) {
    final settlements = _calculateSettlements(expense);
    
    if (settlements.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade600, size: 24),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'All settled up! No payments needed.',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.green,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Required Payments:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.orange.shade800,
            ),
          ),
          const SizedBox(height: 12),
          ...settlements.map((settlement) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(Icons.arrow_forward, color: Colors.orange.shade600, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    settlement,
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
  
  Widget _buildStatisticsCard(BuildContext context, Expense expense) {
    final avgPerPerson = expense.amountCents / expense.splitUserIds.length;
    final maxContribution = expense.splitUserIds
        .map((userId) => _getOwedAmount(expense, userId))
        .fold(0, (a, b) => a > b ? a : b);
    final minContribution = expense.splitUserIds
        .map((userId) => _getOwedAmount(expense, userId))
        .fold(maxContribution, (a, b) => a < b ? a : b);
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        children: [
          _buildStatRow('Average per person', _formatCents(avgPerPerson.round())),
          _buildStatRow('Highest contribution', _formatCents(maxContribution)),
          _buildStatRow('Lowest contribution', _formatCents(minContribution)),
          _buildStatRow('Total participants', '${expense.splitUserIds.length} people'),
        ],
      ),
    );
  }
  
  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.blue.shade700,
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade800,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
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
  
  List<String> _calculateSettlements(Expense expense) {
    final settlements = <String>[];
    final payer = expense.paidByUserId;
    
    for (final userId in expense.splitUserIds) {
      if (userId != payer) {
        final owedAmount = _getOwedAmount(expense, userId);
        if (owedAmount > 0) {
          settlements.add(
            '${_getUserDisplayName(userId)} pays ${_formatCents(owedAmount)} to ${_getUserDisplayName(payer)}'
          );
        }
      }
    }
    
    return settlements;
  }
  
  void _showDeleteConfirmationDialog(BuildContext context, WidgetRef ref, Expense expense) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Expense'),
        content: Text('Are you sure you want to delete "${expense.description}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final devMode = ref.read(developerModeProvider);
              if (devMode) {
                removeDeveloperExpense(expense.groupId, expense.id);
                ref.invalidate(developerExpensesProvider(expense.groupId));
              } else {
                final repo = ref.read(firestoreRepositoryProvider);
                await repo.removeExpense(groupId: expense.groupId, expenseId: expense.id);
              }
              Navigator.of(ctx).pop();
              context.pop(); // Go back to group detail
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Expense deleted successfully')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// Settlement Games functionality
void _showSettlementGames(BuildContext context, SettlementInfo settlement) {
  showDialog(
    context: context,
    builder: (ctx) => _SettlementGamesDialog(settlement: settlement),
  );
}

class _SettlementGamesDialog extends StatefulWidget {
  const _SettlementGamesDialog({required this.settlement});
  final SettlementInfo settlement;

  @override
  State<_SettlementGamesDialog> createState() => _SettlementGamesDialogState();
}

class _SettlementGamesDialogState extends State<_SettlementGamesDialog> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _cardFlipController;
  late AnimationController _diceRollController;
  late AnimationController _wheelSpinController;
  late AnimationController _confettiController;
  
  late Animation<double> _cardFlipAnimation;
  late Animation<double> _diceScaleAnimation;
  late Animation<double> _wheelRotationAnimation;
  late Animation<double> _confettiAnimation;
  
  String _gameResult = '';
  bool _isPlaying = false;
  bool _currentUserWins = false; // Track if current user wins for confetti
  String _currentCard1 = '';
  String _currentCard2 = '';
  String _currentDice1 = '⚀';
  String _currentDice2 = '⚀';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    
    _cardFlipController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _diceRollController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _wheelSpinController = AnimationController(
      duration: const Duration(milliseconds: 6000), // Longer for more suspense
      vsync: this,
    );
    
    _confettiController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    
    _cardFlipAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _cardFlipController, curve: Curves.elasticOut),
    );
    
    _diceScaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _diceRollController, curve: Curves.bounceOut),
    );
    
    _wheelRotationAnimation = Tween<double>(begin: 0.0, end: 15.0).animate( // More rotations
      CurvedAnimation(parent: _wheelSpinController, curve: Curves.easeOutCubic),
    );
    
    _confettiAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _confettiController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _cardFlipController.dispose();
    _diceRollController.dispose();
    _wheelSpinController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 700),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF7C3AED).withOpacity(0.1),
                        const Color(0xFF06B6D4).withOpacity(0.1),
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C3AED).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.casino,
                          color: Color(0xFF7C3AED),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Settlement Games',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Play a game to decide who pays!',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Content - Make this scrollable
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        // Settlement info - more compact
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.grey.shade800
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Colors.grey.shade600
                                  : Colors.grey.shade200,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Debtor
                              Expanded(
                                child: Column(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: _getUserColor(widget.settlement.debtorId),
                                      child: Text(
                                        _getUserInitials(widget.settlement.debtorId),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _getUserDisplayName(widget.settlement.debtorId),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              // VS and amount
                              Expanded(
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF7C3AED),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: const Text(
                                        'VS',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _formatCents(widget.settlement.amount),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF7C3AED),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Creditor
                              Expanded(
                                child: Column(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: _getUserColor(widget.settlement.creditorId),
                                      child: Text(
                                        _getUserInitials(widget.settlement.creditorId),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _getUserDisplayName(widget.settlement.creditorId),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Game area - more compact
                        Container(
                          height: 160,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                const Color(0xFF7C3AED).withOpacity(0.05),
                                const Color(0xFF06B6D4).withOpacity(0.05),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF7C3AED).withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Center(
                            child: _buildGameAnimation(),
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Game results or buttons
                        if (_gameResult.isNotEmpty && !_isPlaying) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: _currentUserWins
                                    ? [
                                        Colors.green.withOpacity(0.1),
                                        Colors.green.withOpacity(0.05),
                                      ]
                                    : [
                                        const Color(0xFF7C3AED).withOpacity(0.1),
                                        const Color(0xFF06B6D4).withOpacity(0.05),
                                      ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _currentUserWins
                                    ? Colors.green.withOpacity(0.3)
                                    : const Color(0xFF7C3AED).withOpacity(0.3),
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  _currentUserWins ? Icons.celebration : Icons.emoji_events,
                                  size: 28,
                                  color: _currentUserWins ? Colors.green : const Color(0xFF7C3AED),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _currentUserWins ? '🎉 You Win!' : 'Game Result',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: _currentUserWins ? Colors.green : const Color(0xFF7C3AED),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _gameResult,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Action buttons
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _gameResult = '';
                                      _isPlaying = false;
                                      _currentUserWins = false;
                                      _currentCard1 = '';
                                      _currentCard2 = '';
                                      _currentDice1 = '⚀';
                                      _currentDice2 = '⚀';
                                    });
                                    _confettiController.reset();
                                  },
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const Text('Play Again', style: TextStyle(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Game result accepted: $_gameResult'),
                                        backgroundColor: const Color(0xFF7C3AED),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.check, size: 16),
                                  label: const Text('Accept', style: TextStyle(fontSize: 12)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF7C3AED),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ] else if (!_isPlaying) ...[
                          // Game selection buttons
                          const Text(
                            'Choose Your Game',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              _gameButton('🃏 Card Draw', Icons.style, () => _playCardGame()),
                              _gameButton('🎲 Dice Roll', Icons.casino, () => _playDiceGame()),
                              _gameButton('🎯 Spin Wheel', Icons.track_changes, () => _playWheelGame()),
                              _gameButton('� Coin Flip', Icons.monetization_on, () => _playCoinFlip()),
                              _gameButton('✂️ Rock Paper Scissors', Icons.back_hand, () => _playRPSGame()),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                
                // Footer - more compact
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey.shade800.withOpacity(0.5)
                        : Colors.grey.shade50,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Confetti overlay - only show when current user wins
        if (_currentUserWins && _gameResult.isNotEmpty)
          AnimatedBuilder(
            animation: _confettiAnimation,
            builder: (context, child) {
              return Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: ConfettiPainter(_confettiAnimation.value),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildGameAnimation() {
    if (!_isPlaying && _gameResult.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            duration: const Duration(seconds: 2),
            tween: Tween(begin: 0, end: 1),
            builder: (context, value, child) {
              return Transform.scale(
                scale: 0.8 + (value * 0.2),
                child: Transform.rotate(
                  angle: value * 2 * 3.14159,
                  child: Icon(
                    Icons.casino,
                    size: 48,
                    color: Color.lerp(
                      const Color(0xFF7C3AED).withOpacity(0.3),
                      const Color(0xFF06B6D4).withOpacity(0.7),
                      value,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Select a game to begin!',
            style: TextStyle(
              color: const Color(0xFF7C3AED),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    if (_gameResult.contains('Drawing cards')) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Card Battle!',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF7C3AED),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_getUserDisplayName(widget.settlement.debtorId)} vs ${_getUserDisplayName(widget.settlement.creditorId)}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                children: [
                  Text(
                    _getUserDisplayName(widget.settlement.debtorId),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF7C3AED),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  AnimatedBuilder(
                    animation: _cardFlipAnimation,
                    builder: (context, child) {
                      return Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.001)
                          ..rotateY(_cardFlipAnimation.value * 3.14159),
                        child: _buildCard(_currentCard1.isEmpty ? '🂠' : _currentCard1),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'VS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Column(
                children: [
                  Text(
                    _getUserDisplayName(widget.settlement.creditorId),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF7C3AED),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  AnimatedBuilder(
                    animation: _cardFlipAnimation,
                    builder: (context, child) {
                      return Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.001)
                          ..rotateY(_cardFlipAnimation.value * 3.14159),
                        child: _buildCard(_currentCard2.isEmpty ? '🂠' : _currentCard2),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      );
    }

    if (_gameResult.contains('Rolling dice')) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Dice Duel!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF7C3AED),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_getUserDisplayName(widget.settlement.debtorId)} vs ${_getUserDisplayName(widget.settlement.creditorId)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                children: [
                  Text(
                    _getUserDisplayName(widget.settlement.debtorId),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF7C3AED),
                    ),
                  ),
                  const SizedBox(height: 8),
                  AnimatedBuilder(
                    animation: _diceScaleAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _diceScaleAnimation.value,
                        child: Transform.rotate(
                          angle: _diceRollController.value * 4 * 3.14159,
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.black, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 4,
                                  offset: const Offset(2, 2),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                _currentDice1,
                                style: const TextStyle(fontSize: 30),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(width: 30),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'VS',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 30),
              Column(
                children: [
                  Text(
                    _getUserDisplayName(widget.settlement.creditorId),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF7C3AED),
                    ),
                  ),
                  const SizedBox(height: 8),
                  AnimatedBuilder(
                    animation: _diceScaleAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _diceScaleAnimation.value,
                        child: Transform.rotate(
                          angle: _diceRollController.value * 4 * 3.14159,
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.black, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 4,
                                  offset: const Offset(2, 2),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                _currentDice2,
                                style: const TextStyle(fontSize: 30),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      );
    }

    if (_gameResult.contains('Spinning the wheel')) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Wheel of Fortune!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF7C3AED),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_getUserDisplayName(widget.settlement.debtorId)} vs ${_getUserDisplayName(widget.settlement.creditorId)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: _wheelRotationAnimation,
            builder: (context, child) {
              return Transform.rotate(
                angle: _wheelRotationAnimation.value * 10 * 3.14159,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Main wheel
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: CustomPaint(
                        painter: WheelPainter(
                          debtorName: _getUserDisplayName(widget.settlement.debtorId),
                          creditorName: _getUserDisplayName(widget.settlement.creditorId),
                        ),
                      ),
                    ),
                    // Center circle
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black,
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          // Wheel pointer
          Container(
            width: 0,
            height: 0,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(width: 6, color: Colors.transparent),
                right: BorderSide(width: 6, color: Colors.transparent),
                bottom: BorderSide(width: 8, color: Colors.red.shade600),
              ),
            ),
          ),
        ],
      );
    }

    if (_gameResult.contains('The wheel chooses')) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Wheel of Fortune!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF7C3AED),
            ),
          ),
          const SizedBox(height: 8),
          // Show final wheel state (stopped at correct position)
          AnimatedBuilder(
            animation: _wheelRotationAnimation,
            builder: (context, child) {
              return Transform.rotate(
                angle: _wheelRotationAnimation.value * 2 * 3.14159,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: CustomPaint(
                        painter: WheelPainter(
                          debtorName: _getUserDisplayName(widget.settlement.debtorId),
                          creditorName: _getUserDisplayName(widget.settlement.creditorId),
                        ),
                      ),
                    ),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black,
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          // Wheel pointer
          Container(
            width: 0,
            height: 0,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(width: 6, color: Colors.transparent),
                right: BorderSide(width: 6, color: Colors.transparent),
                bottom: BorderSide(width: 8, color: Colors.red.shade600),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _gameResult,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _currentUserWins ? Colors.green.shade600 : Colors.red.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    if (_gameResult.contains('Flipping coin') || _gameResult.contains('Heads') || _gameResult.contains('Tails')) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Coin Flip Challenge!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF7C3AED),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_getUserDisplayName(widget.settlement.creditorId)} calls Heads • ${_getUserDisplayName(widget.settlement.debtorId)} calls Tails',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Heads player
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFD700), width: 1),
                    ),
                    child: Text(
                      _getUserDisplayName(widget.settlement.creditorId),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFB8860B),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'HEADS',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              // Coin animation
              TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 1500),
                tween: Tween(begin: 0, end: _isPlaying ? 12 : 0),
                builder: (context, value, child) {
                  final rotationY = value * 3.14159; // Y-axis rotation for flip effect
                  final bounce = _isPlaying ? (sin(value * 2) * 10).abs().toDouble() : 0.0;
                  
                  return Transform.translate(
                    offset: Offset(0, -bounce),
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.001) // perspective
                        ..rotateY(rotationY),
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFFFFD700),
                              const Color(0xFFB8860B),
                              const Color(0xFFFFD700),
                            ],
                            stops: [0.0, 0.5, 1.0],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(color: const Color(0xFF8B7355), width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 8,
                              offset: Offset(0, bounce / 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            // Show H or T based on rotation, with perspective effect
                            (rotationY % (2 * 3.14159)) < 3.14159 ? 'H' : 'T',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF8B4513),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              // Tails player
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B7355).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF8B7355), width: 1),
                    ),
                    child: Text(
                      _getUserDisplayName(widget.settlement.debtorId),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF5D4E37),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'TAILS',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
    }

    if (_gameResult.contains('Rock... Paper... Scissors')) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Rock Paper Scissors!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF7C3AED),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_getUserDisplayName(widget.settlement.debtorId)} vs ${_getUserDisplayName(widget.settlement.creditorId)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 16),
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 800),
            tween: Tween(begin: 0, end: 1),
            builder: (context, value, child) {
              return Transform.scale(
                scale: 0.8 + (value * 0.4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF7C3AED), width: 2),
                      ),
                      child: Text('✊', style: TextStyle(fontSize: 36)),
                    ),
                    const SizedBox(width: 20),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF7C3AED), width: 2),
                      ),
                      child: Text('✋', style: TextStyle(fontSize: 36)),
                    ),
                    const SizedBox(width: 20),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF7C3AED), width: 2),
                      ),
                      child: Text('✌️', style: TextStyle(fontSize: 36)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      );
    }

    // Show final result state after game completion
    if (_gameResult.isNotEmpty && !_isPlaying && 
        !_gameResult.contains('Drawing') && 
        !_gameResult.contains('Rolling') && 
        !_gameResult.contains('Spinning') && 
        !_gameResult.contains('Rock...')) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF7C3AED).withOpacity(0.1),
                  const Color(0xFF06B6D4).withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF7C3AED), width: 2),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.emoji_events,
                  size: 48,
                  color: const Color(0xFF7C3AED),
                ),
                const SizedBox(height: 12),
                Text(
                  'Game Complete!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF7C3AED),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'The decision has been made.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Container();
  }

  Widget _buildCard(String card) {
    return Container(
      width: 36,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 2,
            offset: const Offset(1, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          card,
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }

  Widget _gameButton(String label, IconData icon, VoidCallback onPressed) {
    return Container(
      width: 110,
      height: 50,
      child: ElevatedButton(
        onPressed: _isPlaying ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF7C3AED).withOpacity(0.15)
              : const Color(0xFF7C3AED).withOpacity(0.08),
          foregroundColor: const Color(0xFF7C3AED),
          side: BorderSide(
            color: const Color(0xFF7C3AED).withOpacity(0.3),
            width: 1,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _playCardGame() async {
    setState(() {
      _isPlaying = true;
      _gameResult = 'Drawing cards...';
      _currentCard1 = '🂠';
      _currentCard2 = '🂠';
      _currentUserWins = false;
    });

    // Start card flip animation
    _cardFlipController.reset();
    _cardFlipController.forward();

    // Simulate card drawing with animation - slower for suspense
    for (int i = 0; i < 15; i++) {
      await Future.delayed(const Duration(milliseconds: 250));
      if (mounted) {
        setState(() {
          _gameResult = 'Drawing cards...';
          // Show random cards during animation
          final random = Random();
          _currentCard1 = _getCardEmoji(random.nextInt(13) + 1);
          _currentCard2 = _getCardEmoji(random.nextInt(13) + 1);
        });
      }
    }

    final random = Random();
    final debtorCard = random.nextInt(13) + 1; // 1-13 (Ace to King)
    final creditorCard = random.nextInt(13) + 1;
    
    final debtorCardName = _getCardName(debtorCard);
    final creditorCardName = _getCardName(creditorCard);
    
    // Show the final cards
    setState(() {
      _currentCard1 = _getCardEmoji(debtorCard);
      _currentCard2 = _getCardEmoji(creditorCard);
    });
    
    await Future.delayed(const Duration(milliseconds: 800));
    
    String winner;
    final debtorName = _getUserDisplayName(widget.settlement.debtorId);
    final creditorName = _getUserDisplayName(widget.settlement.creditorId);
    const currentUserId = 'dev_user_123'; // In real app, get from auth
    bool currentUserWins = false;
    
    if (debtorCard > creditorCard) {
      winner = '$creditorName pays! ($creditorName: $creditorCardName vs $debtorName: $debtorCardName)';
      // Current user wins if they are the debtor (owed money) and the creditor has to pay
      currentUserWins = (widget.settlement.debtorId == currentUserId);
    } else if (creditorCard > debtorCard) {
      winner = '$debtorName pays! ($debtorName: $debtorCardName vs $creditorName: $creditorCardName)';
      // Current user wins if they are the creditor (owed money) and the debtor has to pay
      currentUserWins = (widget.settlement.creditorId == currentUserId);
    } else {
      winner = 'It\'s a tie! Both drew $debtorCardName. Draw again or split the cost!';
      currentUserWins = false;
    }

    setState(() {
      _gameResult = winner;
      _isPlaying = false;
      _currentUserWins = currentUserWins;
    });
    
    if (currentUserWins) {
      _confettiController.forward();
    }
  }

  void _playCoinFlip() async {
    setState(() {
      _isPlaying = true;
      _gameResult = 'Flipping coin...';
      _currentUserWins = false;
    });

    // Simulate coin flip with visual feedback
    for (int i = 0; i < 15; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted) {
        setState(() {
          _gameResult = i.isEven ? 'Heads...' : 'Tails...';
        });
      }
    }

    final random = Random();
    final isHeads = random.nextBool();
    const currentUserId = 'dev_user_123'; // In real app, get from auth
    
    // Current user calls heads, other person calls tails
    // If heads wins, current user wins if they're the creditor (gets paid)
    // If tails wins, current user wins if they're the debtor (doesn't have to pay)
    bool currentUserWins = false;
    String result;
    
    if (isHeads) {
      result = 'Heads! ${_getUserDisplayName(widget.settlement.creditorId)} wins and gets paid!';
      currentUserWins = (widget.settlement.creditorId == currentUserId);
    } else {
      result = 'Tails! ${_getUserDisplayName(widget.settlement.debtorId)} wins and doesn\'t have to pay!';
      currentUserWins = (widget.settlement.debtorId == currentUserId);
    }
    
    setState(() {
      _gameResult = result;
      _isPlaying = false;
      _currentUserWins = currentUserWins;
    });
    
    if (currentUserWins) {
      _confettiController.forward();
    }
  }

  void _playDiceGame() async {
    setState(() {
      _isPlaying = true;
      _gameResult = 'Rolling dice...';
      _currentDice1 = '⚀';
      _currentDice2 = '⚀';
      _currentUserWins = false;
    });

    // Start dice roll animation
    _diceRollController.reset();
    _diceRollController.forward();

    // Simulate dice rolling with visual updates - slower for suspense
    final random = Random();
    for (int i = 0; i < 25; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted) {
        setState(() {
          _gameResult = 'Rolling dice...';
          _currentDice1 = _getDiceEmoji(random.nextInt(6) + 1);
          _currentDice2 = _getDiceEmoji(random.nextInt(6) + 1);
        });
      }
    }

    final debtorRoll = random.nextInt(6) + 1;
    final creditorRoll = random.nextInt(6) + 1;
    
    setState(() {
      _currentDice1 = _getDiceEmoji(debtorRoll);
      _currentDice2 = _getDiceEmoji(creditorRoll);
    });
    
    await Future.delayed(const Duration(milliseconds: 800));
    
    String winner;
    final debtorName = _getUserDisplayName(widget.settlement.debtorId);
    final creditorName = _getUserDisplayName(widget.settlement.creditorId);
    const currentUserId = 'dev_user_123'; // In real app, get from auth
    bool currentUserWins = false;
    
    if (debtorRoll < creditorRoll) {
      winner = '$debtorName pays! ($debtorName rolled $debtorRoll vs $creditorName rolled $creditorRoll)';
      // Debtor pays - current user wins if they are the creditor
      currentUserWins = (widget.settlement.creditorId == currentUserId);
    } else if (creditorRoll < debtorRoll) {
      winner = '$creditorName pays! ($creditorName rolled $creditorRoll vs $debtorName rolled $debtorRoll)';
      // Creditor pays - current user wins if they are the debtor
      currentUserWins = (widget.settlement.debtorId == currentUserId);
    } else {
      winner = 'Both rolled $debtorRoll! Roll again or split the cost!';
      currentUserWins = false;
    }

    setState(() {
      _gameResult = winner;
      _isPlaying = false;
      _currentUserWins = currentUserWins;
    });
    
    if (currentUserWins) {
      _confettiController.forward();
    }
  }

  void _playWheelGame() async {
    setState(() {
      _isPlaying = true;
      _gameResult = 'Spinning the wheel...';
      _currentUserWins = false;
    });

    // Determine result first so we can animate to the correct position
    final random = Random();
    final payingPerson = random.nextBool() ? widget.settlement.debtorId : widget.settlement.creditorId;
    final payingName = _getUserDisplayName(payingPerson);
    const currentUserId = 'dev_user_123'; // In real app, get from auth
    
    // Determine if current user wins
    bool currentUserWins = false;
    if (payingPerson == widget.settlement.debtorId) {
      // Debtor pays - current user wins if they are the creditor
      currentUserWins = (widget.settlement.creditorId == currentUserId);
    } else {
      // Creditor pays - current user wins if they are the debtor
      currentUserWins = (widget.settlement.debtorId == currentUserId);
    }

    // Calculate final wheel position based on result
    // Creditor is top half (0-180 degrees), debtor is bottom half (180-360 degrees)
    double finalRotation;
    if (payingPerson == widget.settlement.creditorId) {
      // Point to top half (creditor) - random position in upper semicircle
      finalRotation = (random.nextDouble() * 3.14159); // 0 to π radians
    } else {
      // Point to bottom half (debtor) - random position in lower semicircle  
      finalRotation = (3.14159 + random.nextDouble() * 3.14159); // π to 2π radians
    }
    
    // Add multiple full rotations for spinning effect
    finalRotation += 15 * 2 * 3.14159; // 15 full rotations plus final position

    // Start wheel spin animation to calculated final position
    _wheelSpinController.reset();
    _wheelRotationAnimation = Tween<double>(
      begin: 0.0, 
      end: finalRotation / (2 * 3.14159), // Convert to rotations
    ).animate(
      CurvedAnimation(parent: _wheelSpinController, curve: Curves.easeOutCubic),
    );
    _wheelSpinController.forward();

    // Wait for the animation to complete
    await Future.delayed(const Duration(milliseconds: 5500));
    
    // Short pause before revealing result
    await Future.delayed(const Duration(milliseconds: 500));
    
    setState(() {
      _gameResult = 'The wheel chooses $payingName to pay!';
      _isPlaying = false;
      _currentUserWins = currentUserWins;
    });
    
    if (currentUserWins) {
      _confettiController.forward();
    }
  }

  void _playRPSGame() async {
    setState(() {
      _isPlaying = true;
      _gameResult = 'Rock... Paper... Scissors!';
      _currentUserWins = false;
    });

    // Simulate RPS countdown with visual effect - slower for suspense
    for (int i = 0; i < 15; i++) {
      await Future.delayed(const Duration(milliseconds: 350));
      if (mounted) {
        setState(() {
          _gameResult = 'Rock... Paper... Scissors!';
        });
      }
    }

    final random = Random();
    final choices = ['Rock', 'Paper', 'Scissors'];
    final debtorChoice = choices[random.nextInt(3)];
    final creditorChoice = choices[random.nextInt(3)];
    
    final debtorName = _getUserDisplayName(widget.settlement.debtorId);
    final creditorName = _getUserDisplayName(widget.settlement.creditorId);
    const currentUserId = 'dev_user_123'; // In real app, get from auth
    
    String winner;
    bool currentUserWins = false;
    
    if ((debtorChoice == 'Rock' && creditorChoice == 'Scissors') ||
        (debtorChoice == 'Paper' && creditorChoice == 'Rock') ||
        (debtorChoice == 'Scissors' && creditorChoice == 'Paper')) {
      winner = '$creditorName pays! ($debtorName: $debtorChoice beats $creditorName: $creditorChoice)';
      // Creditor pays - current user wins if they are the debtor
      currentUserWins = (widget.settlement.debtorId == currentUserId);
    } else if (debtorChoice == creditorChoice) {
      winner = 'Tie! Both chose $debtorChoice. Play again!';
      currentUserWins = false;
    } else {
      winner = '$debtorName pays! ($creditorName: $creditorChoice beats $debtorName: $debtorChoice)';
      // Debtor pays - current user wins if they are the creditor
      currentUserWins = (widget.settlement.creditorId == currentUserId);
    }

    setState(() {
      _gameResult = winner;
      _isPlaying = false;
      _currentUserWins = currentUserWins;
    });
    
    if (currentUserWins) {
      _confettiController.forward();
    }
  }

  String _getCardName(int cardValue) {
    switch (cardValue) {
      case 1: return 'Ace';
      case 11: return 'Jack';
      case 12: return 'Queen';
      case 13: return 'King';
      default: return cardValue.toString();
    }
  }
  
  String _getCardEmoji(int cardValue) {
    switch (cardValue) {
      case 1: return 'A♠';
      case 2: return '2♠';
      case 3: return '3♠';
      case 4: return '4♠';
      case 5: return '5♠';
      case 6: return '6♠';
      case 7: return '7♠';
      case 8: return '8♠';
      case 9: return '9♠';
      case 10: return '10♠';
      case 11: return 'J♠';
      case 12: return 'Q♠';
      case 13: return 'K♠';
      default: return '🂠';
    }
  }
  
  String _getDiceEmoji(int value) {
    switch (value) {
      case 1: return '⚀';
      case 2: return '⚁';
      case 3: return '⚂';
      case 4: return '⚃';
      case 5: return '⚄';
      case 6: return '⚅';
      default: return '⚀';
    }
  }

  // Helper methods for user display
  String _getUserDisplayName(String userId) {
    switch (userId) {
      case 'dev_user_123': return 'You';
      case 'user_alice': return 'Alice Johnson';
      case 'user_bob': return 'Bob Smith';
      case 'user_charlie': return 'Charlie Brown';
      case 'user_david': return 'David Wilson';
      case 'user_eve': return 'Eve Davis';
      case 'user_frank': return 'Frank Miller';
      case 'user_grace': return 'Grace Chen';
      default:
        // For phone/email based users, extract name from ID
        if (userId.contains('@')) {
          return userId.split('@')[0].replaceAll('.', ' ').split(' ')
              .map((word) => word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1)}' : '')
              .join(' ');
        } else if (userId.startsWith('+')) {
          return 'Contact ${userId.substring(userId.length - 4)}';
        }
        return userId.length > 8 ? '${userId.substring(0, 8)}...' : userId;
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
    final displayName = _getUserDisplayName(userId);
    
    // Split into words and take first letter of each
    final words = displayName.split(' ');
    if (words.length >= 2) {
      // For multi-word names, take first letter of first two words
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    } else if (words.isNotEmpty && words[0].length >= 2) {
      // For single word names, take first two letters
      return words[0].substring(0, 2).toUpperCase();
    } else {
      // Fallback to first letter
      return displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    }
  }

  String _formatCents(int cents) {
    return '\$${(cents / 100).toStringAsFixed(2)}';
  }
}

// Custom painter for confetti effect
class WheelPainter extends CustomPainter {
  final String debtorName;
  final String creditorName;

  WheelPainter({required this.debtorName, required this.creditorName});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Draw the two halves of the wheel
    final paint1 = Paint()
      ..color = const Color(0xFF7C3AED)
      ..style = PaintingStyle.fill;
    
    final paint2 = Paint()
      ..color = const Color(0xFF06B6D4)
      ..style = PaintingStyle.fill;

    // Draw first half (top)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.14159 / 2, // -90 degrees
      3.14159, // 180 degrees
      true,
      paint1,
    );

    // Draw second half (bottom)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      3.14159 / 2, // 90 degrees
      3.14159, // 180 degrees
      true,
      paint2,
    );

    // Draw dividing lines
    final linePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      linePaint,
    );

    // Draw text for creditor (top half)
    final creditorTextPainter = TextPainter(
      text: TextSpan(
        text: creditorName,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    creditorTextPainter.layout();
    creditorTextPainter.paint(
      canvas,
      Offset(center.dx - creditorTextPainter.width / 2, center.dy - radius / 2 - creditorTextPainter.height / 2),
    );

    // Draw text for debtor (bottom half)
    final debtorTextPainter = TextPainter(
      text: TextSpan(
        text: debtorName,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    debtorTextPainter.layout();
    debtorTextPainter.paint(
      canvas,
      Offset(center.dx - debtorTextPainter.width / 2, center.dy + radius / 2 - debtorTextPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

class ConfettiPainter extends CustomPainter {
  final double animationValue;
  
  ConfettiPainter(this.animationValue);
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final random = Random(42); // Fixed seed for consistent animation
    
    for (int i = 0; i < 50; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final fallY = y + (animationValue * 100);
      
      paint.color = [
        Colors.red,
        Colors.blue,
        Colors.green,
        Colors.yellow,
        Colors.purple,
        Colors.orange,
      ][random.nextInt(6)];
      
      canvas.save();
      canvas.translate(x, fallY % (size.height + 50));
      canvas.rotate(animationValue * 2 * 3.14159 * (random.nextDouble() - 0.5));
      
      // Draw confetti piece
      canvas.drawRect(
        const Rect.fromLTWH(-3, -3, 6, 6),
        paint,
      );
      
      canvas.restore();
    }
  }
  
  @override
  bool shouldRepaint(ConfettiPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}

