import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SwishReturnDetector with WidgetsBindingObserver {
  static final SwishReturnDetector _instance = SwishReturnDetector._internal();
  factory SwishReturnDetector() => _instance;
  SwishReturnDetector._internal();

  Function(List<PendingSwishPayment>)? _onReturnFromSwish;
  List<PendingSwishPayment> _pendingPayments = [];
  DateTime? _swishLaunchTime;
  bool _isActive = true;

  void initialize({
    required Function(List<PendingSwishPayment>) onReturnFromSwish,
  }) {
    _onReturnFromSwish = onReturnFromSwish;
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _onReturnFromSwish = null;
  }

  // Track when Swish is launched
  void trackSwishLaunch(PendingSwishPayment payment) {
    _swishLaunchTime = DateTime.now();
    _pendingPayments.add(payment);
    _saveToPreferences();
  }

  // Clear a specific payment (when manually confirmed)
  void clearPayment(String paymentId) {
    _pendingPayments.removeWhere((p) => p.id == paymentId);
    _saveToPreferences();
  }

  // Clear all pending payments
  void clearAllPayments() {
    _pendingPayments.clear();
    _swishLaunchTime = null;
    _saveToPreferences();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.paused:
        _isActive = false;
        break;
      case AppLifecycleState.resumed:
        if (!_isActive && _shouldTriggerSwishReturn()) {
          _handleReturnFromSwish();
        }
        _isActive = true;
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // No action needed
        break;
    }
  }

  bool _shouldTriggerSwishReturn() {
    // Only trigger if:
    // 1. We have pending payments
    // 2. Swish was launched recently (within last 10 minutes)
    // 3. App was paused for at least 5 seconds (user actually went to Swish)
    
    if (_pendingPayments.isEmpty || _swishLaunchTime == null) {
      return false;
    }

    final now = DateTime.now();
    final timeSinceLaunch = now.difference(_swishLaunchTime!);
    
    // Don't trigger if too much time has passed (user probably did something else)
    if (timeSinceLaunch.inMinutes > 10) {
      _clearExpiredPayments();
      return false;
    }

    // Only trigger if app was paused for at least 5 seconds
    return timeSinceLaunch.inSeconds >= 5;
  }

  void _handleReturnFromSwish() {
    if (_pendingPayments.isNotEmpty && _onReturnFromSwish != null) {
      // Create a copy for the callback
      final paymentsToConfirm = List<PendingSwishPayment>.from(_pendingPayments);
      
      // Trigger the callback
      _onReturnFromSwish!(paymentsToConfirm);
    }
  }

  void _clearExpiredPayments() {
    final now = DateTime.now();
    _pendingPayments.removeWhere((payment) {
      return now.difference(payment.timestamp).inMinutes > 10;
    });
    
    if (_pendingPayments.isEmpty) {
      _swishLaunchTime = null;
    }
    
    _saveToPreferences();
  }

  // Persistence to survive app restarts
  Future<void> _saveToPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final paymentsJson = _pendingPayments.map((p) => p.toJson()).toList();
    await prefs.setString('pending_swish_payments', paymentsJson.toString());
    if (_swishLaunchTime != null) {
      await prefs.setInt('swish_launch_time', _swishLaunchTime!.millisecondsSinceEpoch);
    }
  }

  Future<void> _loadFromPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load launch time
    final launchTimeMs = prefs.getInt('swish_launch_time');
    if (launchTimeMs != null) {
      _swishLaunchTime = DateTime.fromMillisecondsSinceEpoch(launchTimeMs);
    }
    
    // Load pending payments (simplified - you'd need proper JSON parsing)
    // For now, we'll start fresh each app session
    _pendingPayments.clear();
  }

  // Initialize from preferences when app starts
  Future<void> loadPersistentData() async {
    await _loadFromPreferences();
    _clearExpiredPayments(); // Clean up old data
  }
}

class PendingSwishPayment {
  final String id;
  final String debtorId;
  final String creditorId;
  final int amountCents;
  final String groupId;
  final DateTime timestamp;
  final String? settlementId;

  PendingSwishPayment({
    required this.id,
    required this.debtorId,
    required this.creditorId,
    required this.amountCents,
    required this.groupId,
    required this.timestamp,
    this.settlementId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'debtorId': debtorId,
    'creditorId': creditorId,
    'amountCents': amountCents,
    'groupId': groupId,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'settlementId': settlementId,
  };

  static PendingSwishPayment fromJson(Map<String, dynamic> json) => PendingSwishPayment(
    id: json['id'],
    debtorId: json['debtorId'],
    creditorId: json['creditorId'],
    amountCents: json['amountCents'],
    groupId: json['groupId'],
    timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
    settlementId: json['settlementId'],
  );
}