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
        return MaterialApp(
          title: 'PakBazar',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: rootMessengerKey,
          theme: buildAppTheme(),
          locale: locale,
          supportedLocales: const [kEnglish, kUrdu],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) =>
              AppBackground(child: child ?? const SizedBox()),
          home: const AuthGate(),
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

        if (snapshot.hasData) {
          return const _GatedHome();
        }

        return const AuthScreen();
      },
    );
  }
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
      backgroundColor: Colors.transparent,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.block, color: Colors.redAccent, size: 72),
              const SizedBox(height: 20),
              const Text(
                'Account suspended',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Your PakBazar account has been suspended by an administrator '
                'for violating our rules. You cannot post ads, buy, make offers '
                'or chat while suspended. Check your notifications for details, '
                'or appeal below.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationsScreen(),
                  ),
                ),
                icon: const Icon(Icons.notifications),
                label: const Text('See details'),
              ),
              const SizedBox(height: 12),
              if (uid != null) _AppealSection(uid: uid),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => FirebaseAuth.instance.signOut(),
                icon: const Icon(Icons.logout, color: Colors.white70),
                label: const Text(
                  'Sign out',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
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
            final at = ((a.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ?? 0;
            final bt = ((b.data() as Map)['createdAt'] as Timestamp?)
                    ?.millisecondsSinceEpoch ?? 0;
            return bt.compareTo(at);
          });
        final latest = docs.isEmpty
            ? null
            : docs.first.data() as Map<String, dynamic>;
        final status = latest?['status']?.toString();

        if (status == 'pending') {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hourglass_top, color: Colors.white70, size: 18),
                SizedBox(width: 8),
                Text(
                  'Your appeal is under review',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            if (status == 'rejected')
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Your previous appeal was declined. You may submit a new one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
            OutlinedButton.icon(
              onPressed: () => _submitAppeal(context),
              icon: const Icon(Icons.gavel, color: Colors.white),
              label: const Text(
                'Submit an appeal',
                style: TextStyle(color: Colors.white),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white54),
              ),
            ),
          ],
        );
      },
    );
  }
}
