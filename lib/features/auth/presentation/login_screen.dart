import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'auth_provider.dart';
import '../../../core/network/api_error.dart';
import '../../../core/router/pending_invite.dart';
import 'widgets/auth_header.dart';
import 'widgets/auth_text_field.dart';
import 'widgets/google_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _State();
}

class _State extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _googleBusy = false;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  String? _emailError(String? v) {
    if (v == null || v.trim().isEmpty) return 'Enter your email address';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) {
      return 'Enter a valid email address';
    }
    return null;
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    ref.read(authStateProvider.notifier).login(_email.text.trim(), _pass.text);
  }

  Future<void> _google() async {
    setState(() => _googleBusy = true);
    try {
      final account =
          await GoogleSignIn(scopes: const ['email']).signIn();
      if (account == null) return; // user cancelled the picker
      final idToken = (await account.authentication).idToken;
      if (idToken == null) {
        throw Exception(
            'Google did not return an ID token. Configure OAuth client IDs.');
      }
      await ref.read(authStateProvider.notifier).loginWithGoogle(idToken);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    ref.listen(authStateProvider, (_, s) {
      s.whenOrNull(
        data: (d) {
          if (d != null) {
            final pending =
                ref.read(pendingInviteProvider.notifier).state;
            if (pending != null && pending.isNotEmpty) {
              ref.read(pendingInviteProvider.notifier).state = null;
              context.go('/join?code=$pending');
            } else {
              context.go('/home');
            }
          }
        },
        error: (e, _) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        ),
      );
    });
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AuthHeader(
                      title: 'Welcome back',
                      subtitle:
                          'Log in to continue planning trips together',
                    ),
                    const SizedBox(height: 24),
                    AuthTextField(
                      controller: _email,
                      hint: 'Email Address',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: _emailError,
                    ),
                    const SizedBox(height: 12),
                    AuthTextField(
                      controller: _pass,
                      hint: 'Password',
                      icon: Icons.lock_outline,
                      obscure: true,
                      validator: (v) => v == null || v.isEmpty
                          ? 'Enter your password'
                          : null,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 56,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: auth.isLoading ? null : _submit,
                        child: Text(
                            auth.isLoading ? 'Please wait…' : 'Continue'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'or',
                            style: TextStyle(color: Color(0xFF94A3B8)),
                          ),
                        ),
                        Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    GoogleButton(onPressed: _google, busy: _googleBusy),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          "Don't have account?",
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                        TextButton(
                          onPressed: () => context.go('/register'),
                          child: const Text('Create account'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
