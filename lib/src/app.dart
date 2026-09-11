part of '../main.dart';

// Root app widget and auth gate.

class PakBazarApp extends StatelessWidget {
  const PakBazarApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuild the whole app when the language changes; the locale drives both
    // translations and text direction (Urdu => RTL automatically).
    return ValueListenableBuilder<Locale>(
      valueListenable: appLocale,
      builder: (context, locale, _) {
        return ValueListenableBuilder<AppDensity>(
          valueListenable: appDensity,
          builder: (context, density, _) {
            return ValueListenableBuilder<ThemeMode>(
              valueListenable: appThemeMode,
              builder: (context, mode, _) {
                return MaterialApp(
                  title: 'PakBazar',
                  debugShowCheckedModeBanner: false,
                  navigatorKey: rootNavigatorKey,
                  scaffoldMessengerKey: rootMessengerKey,
                  theme: buildAppTheme(Brightness.light, density),
                  darkTheme: buildAppTheme(Brightness.dark, density),
                  themeMode: mode,
                  locale: locale,
                  supportedLocales: const [kEnglish, kUrdu],
                  localizationsDelegates: const [
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  builder: (context, child) {
                    // Record the resolved brightness so AppColors getters (read in
                    // screens further down) return the matching light/dark family.
                    final brightness = Theme.of(context).brightness;
                    if (brightness != appBrightnessValue) {
                      appBrightnessValue = brightness;
                      // AppColors reads that GLOBAL, not an InheritedWidget, so
                      // Flutter has no dependency to invalidate: switching the
                      // theme rebuilds MaterialApp and anything that reads
                      // Theme.of, and leaves every widget that only read the
                      // global holding the colours of the theme it was built in.
                      // Which is why dark mode used to open with "Browse
                      // categories" and "What's New on PakBazar" still painted in
                      // light-mode navy — invisible on a dark page — until the
                      // screen happened to rebuild for some other reason.
                      //
                      // So mark the tree dirty by hand, once, after the frame that
                      // changed it. Elements rebuild but State survives, so this
                      // costs one extra build pass on a theme toggle and keeps
                      // scroll positions, routes and open streams intact.
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        void markDirty(Element el) {
                          el.markNeedsBuild();
                          el.visitChildren(markDirty);
                        }

                        if (context is Element && context.mounted) {
                          context.visitChildren(markDirty);
                        }
                      });
                    }
                    // The Size selector's other half. Multiplied onto whatever the
                    // device is already asking for, so someone who has raised
                    // their phone's font size keeps that and this sits on top,
                    // rather than the app quietly overriding an accessibility
                    // setting.
                    final mq = MediaQuery.of(context);
                    final systemScale = mq.textScaler.scale(100) / 100;
                    return MediaQuery(
                      data: mq.copyWith(
                        textScaler: TextScaler.linear(
                          systemScale * density.textScale,
                        ),
                      ),
                      child: AppBackground(child: child ?? const SizedBox()),
                    );
                  },
                  // Deep links (and web URLs) arrive here. Unrecognised routes
                  // return null so MaterialApp falls back to `home` — a stale
                  // shared link should land the user in the app, not on an error.
                  onGenerateRoute: generateAppRoute,
                  home: const AppGate(child: SecurityGate(child: AuthGate())),
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Whether signing in should clear whatever is stacked on top of the gate.
///
/// True only on the SIGNED-OUT to SIGNED-IN edge. It is deliberately not "am I
/// signed in": authStateChanges also fires on a token refresh while somebody is
/// happily browsing, and popping their stack then would throw them out of
/// whatever screen they were reading.
bool shouldClearAuthRoutes(bool? wasSignedIn, bool signedIn) =>
    wasSignedIn == false && signedIn;

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// Null until the first auth state arrives, so the app opening already
  /// signed in is not mistaken for somebody signing in.
  bool? _wasSignedIn;

  /// Subscribed ONCE. `authStateChanges()` hands back a fresh stream object on
  /// every call, so building it inline made each rebuild of this gate look
  /// like a new stream to StreamBuilder: it resubscribed, reported `waiting`,
  /// and painted the spinner below — tearing down the entire signed-in app and
  /// rebuilding it from scratch, which is why toggling the theme from the Menu
  /// dropped the user back on the Home tab.
  late final Stream<User?> _authState = FirebaseAuth.instance
      .authStateChanges();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authState,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Attribute crashes and events to the account. Fire-and-forget; the
        // uid is the account handle, not PII beyond what we already store.
        setObservabilityUser(snapshot.data?.uid);

        // THE LOGIN SCREEN IS A PUSHED ROUTE, and this gate only decides what
        // sits UNDERNEATH it. So when somebody signs in, the home screen
        // appears at the bottom of the stack while they carry on looking at
        // the login form — which is exactly what "it does not open the app
        // after signing in with Google" is.
        //
        // It worked before only because the login form used to BE this gate's
        // signed-out branch; putting a landing page in front of it is what
        // introduced the gap. Handled here rather than in each sign-in handler
        // so it covers every way in — Google, email, phone, guest — including
        // any added later.
        final signedIn = snapshot.hasData;
        if (shouldClearAuthRoutes(_wasSignedIn, signedIn)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final nav = Navigator.of(context);
            if (nav.canPop()) nav.popUntil((r) => r.isFirst);
          });
        }
        _wasSignedIn = signedIn;

        if (signedIn) {
          return const _PresenceHost(child: _GatedHome());
        }

        // Signed out, the app opens on the landing page rather than on a
        // login form. Somebody arriving for the first time — including an
        // app-store reviewer, who will not create an account either — can see
        // what PakBazar is and what is for sale on it before being asked for
        // anything. Sign-in is one tap from there. See screen_welcome.dart.
        return const WelcomeScreen();
      },
    );
  }
}

/// Keeps the signed-in user's presence heartbeat running for as long as they
/// are authenticated. Mounted only inside the authenticated branch of AuthGate,
/// so signing out disposes it and writes a final "offline".
class _PresenceHost extends StatefulWidget {
  final Widget child;
  const _PresenceHost({required this.child});

  @override
  State<_PresenceHost> createState() => _PresenceHostState();
}

class _PresenceHostState extends State<_PresenceHost> {
  @override
  void initState() {
    super.initState();
    PresenceService.instance.start();
  }

  @override
  void dispose() {
    PresenceService.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Wraps the home screen with a platform-suspension check: if an admin has set
/// `blocked: true` on the user's profile, they see a suspension notice instead
/// of the app. Admins bypass. Firestore rules independently block all writes
/// from a suspended account — this is the user-facing half of the same gate.
class _GatedHome extends StatefulWidget {
  const _GatedHome();

  @override
  State<_GatedHome> createState() => _GatedHomeState();
}

class _GatedHomeState extends State<_GatedHome> {
  /// Opened ONCE, not rebuilt with the widget.
  ///
  /// This used to be `.snapshots()` inline in build(), which meant every
  /// rebuild of this gate handed StreamBuilder a brand-new stream: it dropped
  /// the old subscription, went back to `waiting`, and painted the spinner —
  /// replacing HomeScreen and destroying its state. The user was standing in
  /// the Menu tab and landed back on Home, with every tab's scroll position
  /// and open listeners thrown away, for no reason they could see. Rare while
  /// nothing rebuilt this gate; routine once the theme switch does.
  late final Stream<DocumentSnapshot>? _profile = _openProfile();

  Stream<DocumentSnapshot>? _openProfile() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || isAdminUser()) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final stream = _profile;
    if (stream == null) return const HomeScreen();
    return StreamBuilder<DocumentSnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snap.data?.data() as Map<String, dynamic>?;
        if (data?['blocked'] == true) {
          return const AccountSuspendedScreen();
        }
        return const HomeScreen();
      },
    );
  }
}

/// Suspended user → submit an appeal (a commitment to fix the violation) for
/// an admin to review. Blocked from every other action, but appealing is
/// deliberately allowed (see the appeals rule).
Future<void> _submitAppeal(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  final controller = TextEditingController();
  try {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Appeal your suspension'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Explain what happened and how you have resolved the issue. An '
              'administrator will review your appeal.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Your appeal…',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Submit appeal'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final text = controller.text.trim();
    if (text.isEmpty) return;
    await FirebaseFirestore.instance.collection('appeals').add({
      'userId': user.uid,
      'userEmail': user.email ?? '',
      'message': text,
      'status': 'pending',
      'createdAt': Timestamp.now(),
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Appeal submitted. An administrator will review it.'),
        ),
      );
    }
  } finally {
    controller.dispose();
  }
}

/// Shown to a user whose account an admin has suspended. They can read the
/// reason (delivered as a notification), submit an appeal, and sign out, but
/// cannot otherwise use the app.
class AccountSuspendedScreen extends StatelessWidget {
  const AccountSuspendedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.block, color: AppColors.error, size: 40),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Account suspended',
                  textAlign: TextAlign.center,
                  style: AppType.pageTitle,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Your PakBazar account has been suspended by an administrator '
                  'for violating our rules. You cannot post ads, buy, make offers '
                  'or chat while suspended. Check your notifications for details, '
                  'or appeal below.',
                  textAlign: TextAlign.center,
                  style: AppType.secondary,
                ),
                const SizedBox(height: AppSpacing.xl),
                PrimaryActionButton(
                  label: 'See details',
                  icon: Icons.notifications_none,
                  expand: false,
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationsScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (uid != null) _AppealSection(uid: uid),
                const SizedBox(height: AppSpacing.sm),
                TextButton.icon(
                  onPressed: () {
                    // Held state, so it has to be dropped deliberately — a
                    // listener would simply have stopped.
                    userSession.clear();
                    FirebaseAuth.instance.signOut();
                  },
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Sign out'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The appeal control on the suspension screen: shows the latest appeal's
/// status, or a button to submit one if there is no pending appeal.
class _AppealSection extends StatelessWidget {
  final String uid;
  const _AppealSection({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('appeals')
          .where('userId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snap) {
        // Newest appeal first (sorted client-side to avoid needing an index).
        final docs = (snap.data?.docs ?? []).toList()
          ..sort((a, b) {
            final at =
                ((a.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            final bt =
                ((b.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ??
                0;
            return bt.compareTo(at);
          });
        final latest = docs.isEmpty
            ? null
            : docs.first.data() as Map<String, dynamic>;
        final status = latest?['status']?.toString();

        if (status == 'pending') {
          return Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: AppRadius.rMd,
              border: Border.all(color: AppColors.borderSoft),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.hourglass_top,
                  color: AppColors.textSecondary,
                  size: 18,
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    'Your appeal is under review',
                    style: AppType.secondary,
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            if (status == 'rejected')
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  'Your previous appeal was declined. You may submit a new one.',
                  textAlign: TextAlign.center,
                  style: AppType.caption,
                ),
              ),
            PrimaryActionButton(
              label: 'Submit an appeal',
              icon: Icons.gavel,
              outlined: true,
              expand: false,
              onPressed: () => _submitAppeal(context),
            ),
          ],
        );
      },
    );
  }
}
