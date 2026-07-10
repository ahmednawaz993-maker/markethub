part of '../main.dart';

// Sign in / sign up.

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final signupPhoneController = TextEditingController();
  final phoneController = TextEditingController();
  final otpController = TextEditingController();

  bool isLogin = true;
  bool isLoading = false;
  String? errorMessage;

  // Phone / OTP login state.
  bool usePhone = false;
  bool otpSent = false;
  ConfirmationResult? _confirmation;
  String _sentTo = '';

  String get _primaryLabel {
    if (!usePhone) return isLogin ? 'Log In' : 'Sign Up';
    return otpSent ? 'Verify & Log In' : 'Send Code';
  }

  void _primaryAction() {
    if (!usePhone) {
      submit();
    } else if (otpSent) {
      verifyOtp();
    } else {
      sendOtp();
    }
  }

  /// Sends an SMS OTP to the entered Pakistani number. On web this triggers an
  /// (invisible) reCAPTCHA handled by firebase_auth.
  Future<void> sendOtp() async {
    final raw = phoneController.text.trim();
    if (normalizePhoneForWhatsApp(raw).length < 11) {
      setState(() => errorMessage = 'Please enter a valid phone number');
      return;
    }
    // normalizePhoneForWhatsApp -> e.g. '923001234567'; E.164 wants a leading +.
    final phone = '+${normalizePhoneForWhatsApp(raw)}';
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final confirmation = await FirebaseAuth.instance.signInWithPhoneNumber(
        phone,
      );
      if (!mounted) return;
      setState(() {
        _confirmation = confirmation;
        _sentTo = phone;
        otpSent = true;
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => errorMessage = e.message ?? 'Could not send the code');
    } catch (e) {
      if (!mounted) return;
      setState(() => errorMessage = 'Could not send the code: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  /// Confirms the 6-digit code and signs the user in.
  Future<void> verifyOtp() async {
    final code = otpController.text.trim();
    if (code.isEmpty || _confirmation == null) {
      setState(() => errorMessage = 'Please enter the code we sent you');
      return;
    }
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      await _confirmation!.confirm(code);
      // AuthGate listens to authStateChanges and navigates automatically.
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => errorMessage = e.message ?? 'Invalid or expired code');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> submit() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final phoneRaw = signupPhoneController.text.trim();
    // Clear any stale value from an abandoned earlier attempt so it can't
    // attach to this account.
    pendingSignupPhone = null;

    if (email.isEmpty || password.isEmpty) {
      setState(() => errorMessage = 'Please enter email and password');
      return;
    }
    if (!isLogin && phoneRaw.isEmpty) {
      setState(() => errorMessage = 'Please enter your phone number');
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      if (isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        // Stash the phone so ensureUserDoc writes it onto the new profile.
        pendingSignupPhone = '+${normalizePhoneForWhatsApp(phoneRaw)}';
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
      // AuthGate listens to authStateChanges and navigates automatically.
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => errorMessage = e.message ?? 'Authentication failed');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  /// Opens the "Reset your password" dialog, pre-filled with whatever is in the
  /// email field, so a user who forgot their password can get a reset link in a
  /// couple of taps. Firebase emails a link to a page where they set a new
  /// password, then log back in.
  Future<void> forgotPassword() async {
    final resetController = TextEditingController(
      text: emailController.text.trim(),
    );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        String? dialogError;
        bool sending = false;
        bool sent = false;

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> send() async {
              final email = resetController.text.trim();
              if (!isValidEmail(email)) {
                setDialogState(
                  () => dialogError = 'Please enter a valid email address',
                );
                return;
              }
              setDialogState(() {
                sending = true;
                dialogError = null;
              });
              try {
                await FirebaseAuth.instance.sendPasswordResetEmail(
                  email: email,
                );
                setDialogState(() {
                  sending = false;
                  sent = true;
                });
              } on FirebaseAuthException catch (e) {
                // Don't reveal whether an account exists for this email
                // (account enumeration) — show the same success screen.
                if (e.code == 'user-not-found') {
                  setDialogState(() {
                    sending = false;
                    sent = true;
                  });
                  return;
                }
                setDialogState(() {
                  sending = false;
                  dialogError = switch (e.code) {
                    'invalid-email' => 'Please enter a valid email address',
                    'too-many-requests' =>
                      'Too many attempts. Please try again in a few minutes.',
                    'network-request-failed' =>
                      'No internet connection. Please try again.',
                    _ => 'Could not send the reset email. Please try again.',
                  };
                });
              }
            }

            if (sent) {
              return AlertDialog(
                icon: const Icon(
                  Icons.mark_email_read,
                  color: kPakGreen,
                  size: 44,
                ),
                title: const Text('Check your email'),
                content: Text(
                  'If an account exists for ${resetController.text.trim()}, '
                  "we've sent a link to reset your password. Open it, choose a "
                  'new password, then log in.',
                ),
                actions: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Got it'),
                  ),
                ],
              );
            }

            return AlertDialog(
              icon: const Icon(Icons.lock_reset, color: kPakGreen, size: 44),
              title: const Text('Reset your password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Enter your account email and we'll send you a link to set "
                    'a new password.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: resetController,
                    enabled: !sending,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => sending ? null : send(),
                    decoration: InputDecoration(
                      labelText: 'Email',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.email),
                      errorText: dialogError,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: sending ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: sending ? null : send,
                  child: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send reset link'),
                ),
              ],
            );
          },
        );
      },
    );
    resetController.dispose();
  }

  Future<void> continueAsGuest() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      await FirebaseAuth.instance.signInAnonymously();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => errorMessage = e.message ?? 'Could not continue as guest');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    signupPhoneController.dispose();
    phoneController.dispose();
    otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kPakGreen, kPakGreenLight],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset(
                      'assets/pakbazar_logo.png',
                      height: 88,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Pakistan ka apna online bazaar',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: kPakGreen,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                const SizedBox(height: 16),
                // Choose how to sign in: email/password or phone + OTP.
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF1F2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _AuthMethodTab(
                          label: 'Email',
                          icon: Icons.email,
                          selected: !usePhone,
                          onTap: isLoading
                              ? null
                              : () => setState(() {
                                  usePhone = false;
                                  errorMessage = null;
                                }),
                        ),
                      ),
                      Expanded(
                        child: _AuthMethodTab(
                          label: 'Phone',
                          icon: Icons.phone_android,
                          selected: usePhone,
                          onTap: isLoading
                              ? null
                              : () => setState(() {
                                  usePhone = true;
                                  errorMessage = null;
                                }),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (!usePhone) ...[
                  TextField(
                    controller: emailController,
                    enabled: !isLoading,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    enabled: !isLoading,
                    obscureText: true,
                    onSubmitted: (_) => isLoading ? null : submit(),
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock),
                    ),
                  ),
                  if (!isLogin) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: signupPhoneController,
                      enabled: !isLoading,
                      keyboardType: TextInputType.phone,
                      onSubmitted: (_) => isLoading ? null : submit(),
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                        hintText: '03xx xxxxxxx',
                        prefixText: '+92 ',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                    ),
                  ],
                  if (isLogin)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: isLoading ? null : forgotPassword,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Forgot password?'),
                      ),
                    ),
                ] else if (!otpSent) ...[
                  TextField(
                    controller: phoneController,
                    enabled: !isLoading,
                    keyboardType: TextInputType.phone,
                    onSubmitted: (_) => isLoading ? null : sendOtp(),
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      hintText: '03xx xxxxxxx',
                      prefixText: '+92 ',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'We\'ll text you a one-time code to verify your number.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ] else ...[
                  Text(
                    'Enter the 6-digit code sent to $_sentTo',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: otpController,
                    enabled: !isLoading,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    onSubmitted: (_) => isLoading ? null : verifyOtp(),
                    decoration: const InputDecoration(
                      labelText: 'OTP code',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.sms),
                      counterText: '',
                    ),
                  ),
                ],
                if (errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: isLoading ? null : _primaryAction,
                  child: isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_primaryLabel),
                ),
                const SizedBox(height: 8),
                if (!usePhone)
                  TextButton(
                    onPressed: isLoading
                        ? null
                        : () {
                            setState(() {
                              isLogin = !isLogin;
                              errorMessage = null;
                            });
                          },
                    child: Text(
                      isLogin
                          ? "Don't have an account? Sign up"
                          : 'Already have an account? Log in',
                    ),
                  )
                else if (otpSent)
                  TextButton(
                    onPressed: isLoading
                        ? null
                        : () {
                            setState(() {
                              otpSent = false;
                              _confirmation = null;
                              otpController.clear();
                              errorMessage = null;
                            });
                          },
                    child: const Text('Change number'),
                  ),
                const Divider(height: 32),
                    OutlinedButton.icon(
                      onPressed: isLoading ? null : continueAsGuest,
                      icon: const Icon(Icons.person_outline),
                      label: const Text('Continue as Guest'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }
}

/// One segment of the Email/Phone sign-in selector.
class _AuthMethodTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;
  const _AuthMethodTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? kPakGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? Colors.white : kPakGreen,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : kPakGreen,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tappable wrapper that is reachable with the keyboard.
///
/// Arrow keys move focus between [FocusableTap]s (directional focus, built into
/// MaterialApp), Enter/Space activates the focused one, and a blue ring shows
/// which item is currently selected. Off-screen items scroll into view when
/// they receive focus.
