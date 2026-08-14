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
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: appThemeMode,
          builder: (context, mode, _) {
            return MaterialApp(
              title: 'PakBazar',
              debugShowCheckedModeBanner: false,
              navigatorKey: rootNavigatorKey,
              scaffoldMessengerKey: rootMessengerKey,
              theme: buildAppTheme(Brightness.light),
              darkTheme: buildAppTheme(Brightness.dark),
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
                appBrightnessValue = Theme.of(context).brightness;
                return AppBackground(child: child ?? const SizedBox());
              },
              // Deep links (and web URLs) arrive here. Unrecognised routes
              // return null so MaterialApp falls back to `home` — a stale
              // shared link should land the user in the app, not on an error.
              onGenerateRoute: generateAppRoute,
              home: const AppGate(
                child: SecurityGate(child: AuthGate()),
              ),
            );
          },
        );
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Attribute crashes and events to the account. Fire-and-forget; the
        // uid is the account handle, not PII beyond what we already store.
        setObservabilityUser(snapshot.data?.uid);

        if (snapshot.hasData) {
          return const _PresenceHost(child: _GatedHome());
        }

        return const AuthScreen();
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
class _GatedHome extends StatelessWidget {
  const _GatedHome();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || isAdminUser()) return const HomeScreen();
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
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
                  onPressed: () => FirebaseAuth.instance.signOut(),
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
