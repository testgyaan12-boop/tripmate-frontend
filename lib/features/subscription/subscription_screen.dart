import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_error.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;
import 'razorpay_web.dart';

/// Premium subscription screen: current plan + Free/Pro/Family cards.
/// Checkout is native Razorpay (Android). On web shows an upgrade nudge.
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  List<Map<String, dynamic>> _plans = [];
  Map<String, dynamic>? _sub;
  bool _loading = true;
  bool _paying = false;
  String? _email;
  Razorpay? _razorpay;
  Map<String, dynamic>? _pendingPlan;
  String _pendingBilling = 'MONTHLY';

  static const _featureLabels = {
    'TRIP_LIMIT': 'Trips',
    'MEMBERS_PER_TRIP': 'Members per trip',
    'STORAGE_MB': 'Gallery storage',
    'AI_PLANNER': 'AI Trip Planner',
    'OFFLINE_MAP': 'Offline maps',
    'EXPORT_PDF': 'Export trip PDF',
    'NO_ADS': 'Remove ads',
    'PRIORITY_SUPPORT': 'Priority support',
  };

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _razorpay = Razorpay();
      _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess);
      _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _onError);
      _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _onWallet);
    }
    _load();
  }

  @override
  void dispose() {
    _razorpay?.clear();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final dio = ref.read(dioClientProvider).dio;
      final res = await Future.wait([
        dio.get('/api/billing/plans'),
        dio.get('/api/billing/subscription/me'),
        dio.get('/api/users/me'),
      ]);
      if (!mounted) return;
      setState(() {
        _plans = ((res[0].data['data'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _sub = Map<String, dynamic>.from(res[1].data['data']);
        _email = ((res[2].data['data'] as Map?)?['email'])?.toString();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    }
  }

  String get _currentCode => (_sub?['planCode'] ?? 'FREE').toString();

  /// Direct checkout — no intermediate popup. Opens the Razorpay payment
  /// page at once (native on Android, JS bridge on web).
  Future<void> _upgrade(Map<String, dynamic> plan, String billing) async {
    if (!mounted) return;
    setState(() => _paying = true);
    try {
      final dio = ref.read(dioClientProvider).dio;
      final res = await dio.post('/api/billing/orders', data: {
        'planCode': (plan['code'] ?? '').toString(),
        'billing': billing,
      });
      final order = Map<String, dynamic>.from(res.data['data'] as Map);
      final amount = (order['amount'] as num).toInt();
      final label =
          '${plan['name']} · ${billing == 'YEARLY' ? 'Yearly' : 'Monthly'}';
      _pendingPlan = plan;
      _pendingBilling = billing;
      if (kIsWeb) {
        // Chrome/PWA: Razorpay.js checkout via index.html bridge.
        Map<String, String>? result;
        try {
          result = await openRazorpayWebCheckout(
            key: order['keyId'].toString(),
            amount: amount,
            currency: (order['currency'] ?? 'INR').toString(),
            name: 'TripMate',
            description: label,
            orderId: order['orderId'].toString(),
            email: _email,
          );
        } catch (e) {
          // Checkout failed/dismissed — no money moved, safe to retry.
          if (mounted) {
            _showFailedDialog(plan, billing, apiErrorMessage(e));
          }
          return;
        }
        await _verify(
            result['orderId']!, result['paymentId']!, result['signature']!);
      } else {
        _razorpay!.open({
          'key': order['keyId'],
          'amount': amount,
          'currency': order['currency'] ?? 'INR',
          'name': 'TripMate',
          'description': label,
          'order_id': order['orderId'],
          'theme': {'color': '#2563EB'},
          if (_email != null && _email!.isNotEmpty)
            'prefill': {'email': _email},
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  void _onDowngrade() {
    final end = (_sub?['endDate'] ?? '').toString();
    String when = '';
    if (end.isNotEmpty) {
      try {
        final dt = DateTime.parse(end);
        when = ' Your plan stays active till ${dt.day}/${dt.month}/${dt.year}.';
      } catch (_) {}
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('To move to Free, let the cycle end.$when')),
    );
  }

  /// Checkout failed BEFORE any money moved — safe to retry payment.
  void _showFailedDialog(
      Map<String, dynamic> plan, String billing, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Payment failed'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _upgrade(plan, billing);
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  /// Money may be deducted but activation unconfirmed — NEVER repay here.
  /// Refresh pulls the true status (verify/webhook may have activated).
  void _showPendingDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirming payment…'),
        content: Text('$message\n\nIf money was deducted, Pro activates '
            'automatically — just refresh status.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _loading = true);
              _load();
            },
            child: const Text('Refresh status'),
          ),
        ],
      ),
    );
  }

  void _onSuccess(PaymentSuccessResponse r) async {
    await _verify(r.orderId ?? '', r.paymentId ?? '', r.signature ?? '');
  }

  Future<void> _verify(String orderId, String paymentId, String signature) async {
    try {
      final dio = ref.read(dioClientProvider).dio;
      await dio.post('/api/billing/verify', data: {
        'orderId': orderId,
        'paymentId': paymentId,
        'signature': signature,
      });
      if (!mounted) return;
      _pendingPlan = null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Welcome to Pro! 🎉'), backgroundColor: Colors.green),
      );
      setState(() => _loading = true);
      _load();
    } catch (e) {
      if (mounted) _showPendingDialog(apiErrorMessage(e));
    }
  }

  void _onError(PaymentFailureResponse r) {
    if (!mounted) return;
    final msg = 'Payment ${r.code ?? ''}: ${r.message ?? 'failed'}'.trim();
    final plan = _pendingPlan;
    if (plan != null) {
      _showFailedDialog(plan, _pendingBilling, msg);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _onWallet(ExternalWalletResponse r) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('External wallet: ${r.walletName ?? ''}')),
    );
  }

  String _rs(int paise) => '₹${(paise / 100).toStringAsFixed(paise % 100 == 0 ? 0 : 2)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold(context),
      appBar: AppBar(
        title: const Text('Subscription'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/profile'),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                setState(() => _loading = true);
                await _load();
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  _CurrentPlanCard(sub: _sub ?? {}),
                  const SizedBox(height: 20),
                  Text('Choose your plan', style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary(context))),
                  const SizedBox(height: 12),
                  for (final p in _plans) ...[
                    _PlanCard(
                      plan: p,
                      isCurrent: (p['code'] ?? '').toString() == _currentCode,
                      isRecommended: (p['code'] ?? '').toString() == 'PRO',
                      paying: _paying,
                      rs: _rs,
                      featureText: _featureText,
                      onPay: (b) => _upgrade(p, b),
                      onDowngrade: _onDowngrade,
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: _loading ? null : () {
                        setState(() => _loading = true);
                        _load();
                      },
                      icon: const Icon(Icons.restore, size: 18),
                      label: const Text('Restore purchase'),
                    ),
                  ),
                  Center(
                    child: Text('Test mode · payments are simulated',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted(context))),
                  ),
                ],
              ),
            ),
    );
  }

  String _featureText(String code, String value) {
    final label = _featureLabels[code] ?? code;
    switch (code) {
      case 'TRIP_LIMIT':
        return value == '999' ? 'Unlimited trips' : '$value trips';
      case 'MEMBERS_PER_TRIP':
        return value == '999' ? 'Unlimited members' : '$value members per trip';
      case 'STORAGE_MB':
        final mb = int.tryParse(value) ?? 0;
        return mb >= 1024 ? '${(mb / 1024).toStringAsFixed(mb % 1024 == 0 ? 0 : 1)} GB gallery' : '$mb MB gallery';
      default:
        return value == '1' ? label : '$label: $value';
    }
  }
}

class _CurrentPlanCard extends StatelessWidget {
  final Map<String, dynamic> sub;
  const _CurrentPlanCard({required this.sub});

  @override
  Widget build(BuildContext context) {
    final name = (sub['planName'] ?? sub['planCode'] ?? 'Free').toString();
    final status = (sub['status'] ?? 'FREE').toString();
    final end = (sub['endDate'] ?? '').toString();
    final limits = Map<String, dynamic>.from(sub['limits'] ?? {});
    final used = ((sub['storageUsedBytes'] ?? 0) as num).toInt();
    final quotaMb = int.tryParse((limits['STORAGE_MB'] ?? '500').toString()) ?? 500;
    final quotaBytes = quotaMb * 1024 * 1024;
    final pct = quotaBytes <= 0 ? 0.0 : (used / quotaBytes).clamp(0.0, 1.0);
    String endLabel = '';
    if (end.isNotEmpty) {
      try {
        final dt = DateTime.parse(end);
        endLabel = 'Renews ${dt.day}/${dt.month}/${dt.year}';
      } catch (_) {}
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium, color: Colors.white, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(
                        color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                    Text(status == 'ACTIVE' ? 'Active plan' : 'Free forever',
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(status,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          if (endLabel.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(endLabel, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Gallery storage', style: TextStyle(color: Colors.white70, fontSize: 12)),
              Text('${(used / 1024 / 1024).toStringAsFixed(1)} / $quotaMb MB',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final Map<String, dynamic> plan;
  final bool isCurrent;
  final bool isRecommended;
  final bool paying;
  final String Function(int) rs;
  final String Function(String, String) featureText;
  final void Function(String billing) onPay;
  final VoidCallback onDowngrade;
  const _PlanCard({
    required this.plan, required this.isCurrent, required this.isRecommended,
    required this.paying, required this.rs, required this.featureText,
    required this.onPay, required this.onDowngrade,
  });

  @override
  Widget build(BuildContext context) {
    final code = (plan['code'] ?? '').toString();
    final name = (plan['name'] ?? code).toString();
    final monthly = ((plan['monthlyPaise'] ?? 0) as num).toInt();
    final yearly = ((plan['yearlyPaise'] ?? 0) as num).toInt();
    final feats = Map<String, dynamic>.from(plan['features'] ?? {});
    final free = code == 'FREE';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: isRecommended
            ? const LinearGradient(
                colors: [Color(0xFF1D4ED8), Color(0xFF6D28D9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isRecommended ? null : AppColors.card(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isRecommended ? Colors.transparent : AppColors.cardBorder(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name, style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800,
                    color: isRecommended ? Colors.white : AppColors.textPrimary(context))),
              ),
              if (isRecommended)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('RECOMMENDED',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
              if (isCurrent && !isRecommended)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.blue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('CURRENT',
                      style: TextStyle(color: AppColors.blue, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (free)
            Text('₹0 forever', style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800,
                color: AppColors.textPrimary(context)))
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${rs(monthly)} / month', style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800,
                    color: isRecommended ? Colors.white : AppColors.textPrimary(context))),
                if (yearly > 0)
                  Text('${rs(yearly)} / year', style: TextStyle(
                      fontSize: 13,
                      color: isRecommended ? Colors.white70 : AppColors.textSecondary(context))),
              ],
            ),
          const SizedBox(height: 12),
          for (final e in feats.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    e.value.toString() == '0' ? Icons.close : Icons.check,
                    size: 16,
                    color: e.value.toString() == '0'
                        ? (isRecommended ? Colors.white38 : AppColors.textMuted(context))
                        : const Color(0xFF10B981),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      featureText(e.key.toString(), e.value.toString()),
                      style: TextStyle(
                        fontSize: 13,
                        color: isRecommended
                            ? (e.value.toString() == '0' ? Colors.white54 : Colors.white)
                            : (e.value.toString() == '0'
                                ? AppColors.textMuted(context)
                                : AppColors.textPrimary(context)),
                        decoration: e.value.toString() == '0' ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: isCurrent
                ? OutlinedButton(
                    onPressed: null,
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Current plan'),
                  )
                : free
                    ? OutlinedButton(
                        onPressed: onDowngrade,
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Downgrade'),
                      )
                    : yearly > 0
                        ? Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: FilledButton(
                                    onPressed: paying ? null : () => onPay('MONTHLY'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: isRecommended ? Colors.white : AppColors.blue,
                                      foregroundColor: isRecommended ? const Color(0xFF1D4ED8) : Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                    child: Text('${rs(monthly)}/mo',
                                        style: const TextStyle(fontWeight: FontWeight.w700)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: OutlinedButton(
                                    onPressed: paying ? null : () => onPay('YEARLY'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: isRecommended ? Colors.white : AppColors.blue,
                                      side: BorderSide(
                                        color: isRecommended ? Colors.white70 : AppColors.blue,
                                      ),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                    child: Text('${rs(yearly)}/yr',
                                        style: const TextStyle(fontWeight: FontWeight.w700)),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : FilledButton(
                            onPressed: paying ? null : () => onPay('MONTHLY'),
                            style: FilledButton.styleFrom(
                              backgroundColor: isRecommended ? Colors.white : AppColors.blue,
                              foregroundColor: isRecommended ? const Color(0xFF1D4ED8) : Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: paying
                                ? const SizedBox(width: 20, height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : Text('Buy ${rs(monthly)}/mo',
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
          ),
        ],
      ),
    );
  }
}
