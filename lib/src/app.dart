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

/// Shown to a user whose account an admin has suspended. They can read the
/// reason (delivered as a notification) and sign out, but cannot use the app.
class AccountSuspendedScreen extends StatelessWidget {
  const AccountSuspendedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Padding(
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
                'or chat while suspended. Check your notifications for details '
                'or contact support.',
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
