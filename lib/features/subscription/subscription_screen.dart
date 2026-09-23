import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_error.dart';
import '../auth/presentation/auth_provider.dart' show dioClientProvider;

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

  Future<void> _upgrade(Map<String, dynamic> plan) async {
    if (kIsWeb) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Upgrade on mobile'),
          content: const Text(
              'Payments work in the TripMate Android app. Your plans stay in sync everywhere.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    }
    final code = (plan['code'] ?? '').toString();
    final billing = await _pickBilling(plan);
    if (billing == null || !mounted) return;
    setState(() => _paying = true);
    try {
      final dio = ref.read(dioClientProvider).dio;
      final res = await dio.post('/api/billing/orders', data: {
        'planCode': code,
        'billing': billing,
      });
      final order = Map<String, dynamic>.from(res.data['data'] as Map);
      final amount = (order['amount'] as num).toInt();
      _razorpay!.open({
        'key': order['keyId'],
        'amount': amount,
        'currency': order['currency'] ?? 'INR',
        'name': 'TripMate',
        'description': '${plan['name']} · ${billing == 'YEARLY' ? 'Yearly' : 'Monthly'}',
        'order_id': order['orderId'],
        'theme': {'color': '#2563EB'},
        if (_email != null && _email!.isNotEmpty)
          'prefill': {'email': _email},
      });
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

  Future<String?> _pickBilling(Map<String, dynamic> plan) {
    final monthly = ((plan['monthlyPaise'] ?? 0) as num).toInt();
    final yearly = ((plan['yearlyPaise'] ?? 0) as num).toInt();
    final opts = <Map<String, String>>[];
    if (monthly > 0) opts.add({'cycle': 'MONTHLY', 'label': 'Monthly · ${_rs(monthly)}'});
    if (yearly > 0) opts.add({'cycle': 'YEARLY', 'label': 'Yearly · ${_rs(yearly)} (save)'});
    if (opts.isEmpty) return Future.value(null);
    if (opts.length == 1) return Future.value(opts.first['cycle']);
    return showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.cardBorder(context),
                borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Text('Choose billing', style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800,
                color: AppColors.textPrimary(context))),
            const SizedBox(height: 8),
            for (final o in opts)
              ListTile(
                title: Text(o['label']!, style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(ctx, o['cycle']),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _onSuccess(PaymentSuccessResponse r) async {
    try {
      final dio = ref.read(dioClientProvider).dio;
      await dio.post('/api/billing/verify', data: {
        'orderId': r.orderId,
        'paymentId': r.paymentId,
        'signature': r.signature,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Welcome to Pro! 🎉'), backgroundColor: Colors.green),
      );
      setState(() => _loading = true);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    }
  }

  void _onError(PaymentFailureResponse r) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Payment ${r.code ?? ''}: ${r.message ?? 'failed'}'.trim())),
    );
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
                      onUpgrade: () => _upgrade(p),
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
  final VoidCallback onUpgrade;
  const _PlanCard({
    required this.plan, required this.isCurrent, required this.isRecommended,
    required this.paying, required this.rs, required this.featureText,
    required this.onUpgrade,
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
                : FilledButton(
                    onPressed: paying ? null : onUpgrade,
                    style: FilledButton.styleFrom(
                      backgroundColor: isRecommended ? Colors.white : AppColors.blue,
                      foregroundColor: isRecommended ? const Color(0xFF1D4ED8) : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: paying
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(free ? 'Downgrade' : 'Upgrade Now',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
          ),
        ],
      ),
    );
  }
}
