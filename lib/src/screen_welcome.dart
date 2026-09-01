part of '../main.dart';

// The page you land on before signing in.
//
// WHY IT EXISTS. Two reasons, and they turn out to be the same reason.
//
// An app that opens on a login form tells a first-time visitor nothing. They
// have to create an account to find out whether the app is worth creating an
// account for, and most people simply leave. The same is true of an app-store
// reviewer, who will not sign up either — and a reviewer who cannot see what
// the app does is a reviewer who rejects it.
//
// So this explains the platform in full, and it shows REAL listings while it
// does. Those come from the public feed endpoint, which needs no account and
// publishes no phone numbers — so a visitor and a reviewer both see genuine
// stock rather than a screenshot of it. See functions/feed.js.
//
// Everything here has to be TRUE. A landing page that promises escrow, or
// verified sellers, or zero commission, is describing features that either
// exist in this codebase or are a lie told to a reviewer. Every claim below is
// one the app actually implements.

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  List<Listing>? _live;
  bool _failed = false;
  bool _enteringAsGuest = false;

  @override
  void initState() {
    super.initState();
    _loadLive();
  }

  Future<void> _loadLive() async {
    try {
      // fetchFeedPage, not loadFeedPage: the fallback in loadFeedPage reads
      // Firestore directly, and nobody is signed in here, so it would only
      // trade a clean failure for a permission error.
      final page = await fetchFeedPage(limit: 12);
      if (mounted) setState(() => _live = page.items);
    } catch (_) {
      // The strip is evidence, not structure. Losing it must not cost the
      // visitor the explanation.
      if (mounted) setState(() => _failed = true);
    }
  }

  void _signIn(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const AuthScreen()),
  );

  /// Into the app with no account.
  ///
  /// The hero says browsing needs no account, so there has to be a button that
  /// does it — the app has had anonymous sign-in all along, buried at the
  /// bottom of the login form where a first-time visitor would never look for
  /// it, and where an app-store reviewer would never find it either.
  ///
  /// Signing in later UPGRADES this session rather than replacing it, so a
  /// guest keeps their cart and favourites. See signInWithGoogle.
  Future<void> _browseAsGuest() async {
    setState(() => _enteringAsGuest = true);
    try {
      await FirebaseAuth.instance.signInAnonymously();
      // AuthGate is listening; it swaps this screen for the app itself.
    } catch (e) {
      if (!mounted) return;
      setState(() => _enteringAsGuest = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the marketplace: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.accent,
          onRefresh: _loadLive,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _hero(context),
              _liveStrip(),
              _points(),
              _footer(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.page,
      AppSpacing.section,
      AppSpacing.page,
      AppSpacing.section,
    ),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          kPakGreen,
          Color.lerp(kPakGreen, Colors.black, 0.35)!,
        ],
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Image.asset(
              'assets/pakbazar_mark_light.png',
              height: 40,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.storefront, color: Colors.white, size: 40),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Flexible, not bare: a Text in a Row takes whatever width it
            // wants and overflows the rest. Caught by the test at 390px, which
            // is an ordinary phone, not an edge case.
            Flexible(
              child: Text(
                'PakBazar',
                style: AppType.pageTitle.copyWith(color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Spacer(),
            // Sign in sits at the top, always visible, next to the name.
            // Somebody who already has an account should not have to read the
            // pitch or scroll past it to get in.
            TextButton(
              onPressed: () => _signIn(context),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Sign in'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Pakistan’s online marketplace.',
          style: AppType.sectionTitle.copyWith(
            color: Colors.white,
            height: 1.3,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'PakBazar is a place to buy and sell. People and small businesses '
          'across Pakistan list what they have; you search, message them, '
          'agree a price and pay through the app — with the money held until '
          'the item reaches you.',
          style: AppType.body.copyWith(
            color: Colors.white.withValues(alpha: 0.92),
            height: 1.45,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // The categories actually ON the marketplace, in the order they are
        // actually stocked. Naming ones it does not carry would be the easiest
        // way to make this page a lie — the first draft said "livestock",
        // which PakBazar does not sell.
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            // Five, not eight: enough to say "marketplace" at a glance
            // without turning the hero into a directory.
            for (final c in const [
              'Women Essentials',
              'Home & Furniture',
              'Mobiles & Tablets',
              'Electronics',
              'Motors',
            ])
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: AppRadius.rPill,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                child: Text(
                  c,
                  style: AppType.caption.copyWith(color: Colors.white),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: kPakGreen,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            ),
            onPressed: () => _signIn(context),
            child: const Text('Create account or sign in'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.65)),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            ),
            onPressed: _enteringAsGuest ? null : _browseAsGuest,
            icon: _enteringAsGuest
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.storefront_outlined),
            label: const Text('Browse without an account'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'You only sign in to message a seller, buy, or post an ad.',
          style: AppType.caption.copyWith(
            color: Colors.white.withValues(alpha: 0.78),
          ),
        ),
      ],
    ),
  );

  /// Real ads, fetched without an account.
  ///
  /// This is the part that makes the page evidence rather than a brochure: a
  /// reviewer sees the marketplace actually has stock in it, and a visitor
  /// sees what is for sale before deciding whether to sign up.
  Widget _liveStrip() {
    if (_failed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('On PakBazar right now', style: AppType.sectionTitle),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Live listings, updated through the day.',
                  style: AppType.caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 210,
            child: _live == null
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.page,
                    ),
                    itemCount: _live!.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppSpacing.md),
                    itemBuilder: (context, i) => _PreviewCard(
                      listing: _live![i],
                      onTap: () => _signIn(context),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// The whole explanation, in three lines.
  ///
  /// This page carried two step-by-step walkthroughs, a six-point safety card
  /// and a grid of extras. All of it was true and almost none of it was read:
  /// somebody deciding whether to open a marketplace wants to know what it is,
  /// whether their money is safe, and what it costs. Everything else is
  /// discoverable inside the app, which is one tap away.
  Widget _points() => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.page,
      AppSpacing.section,
      AppSpacing.page,
      0,
    ),
    child: Column(
      children: const [
        _Point(
          icon: Icons.verified_user_outlined,
          title: 'Your money is held safely',
          body: 'Pay through PakBazar and we hold it until the item reaches '
              'you. Cash on delivery too, if the seller offers it.',
        ),
        SizedBox(height: AppSpacing.lg),
        _Point(
          icon: Icons.sell_outlined,
          title: 'Selling is free',
          body: 'No fee to list, and no commission on a sale during the '
              'free-launch period.',
        ),
        SizedBox(height: AppSpacing.lg),
        _Point(
          icon: Icons.shield_outlined,
          title: 'Checked before it appears',
          body: 'Every ad is reviewed by our team, sellers verify their '
              'identity, and phone numbers are never shown publicly.',
        ),
      ],
    ),
  );

  Widget _footer(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.page,
      AppSpacing.section,
      AppSpacing.page,
      AppSpacing.section,
    ),
    child: Column(
      children: [
        Text(
          'Ready to start?',
          style: AppType.sectionTitle,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'It takes a minute, and posting your first ad is free.',
          style: AppType.caption,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            ),
            onPressed: () => _signIn(context),
            child: const Text('Create account or sign in'),
          ),
        ),
      ],
    ),
  );
}

/// A listing on the landing page.
///
/// Deliberately not the full marketplace card: that one carries a favourite
/// button and a seller link, both of which need an account. This shows what is
/// for sale and takes a tap to the sign-in screen, which is the honest thing
/// for it to do.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.listing, required this.onTap});

  final Listing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: SizedBox(
      width: 160,
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.vertical(top: AppRadius.rCard.topLeft),
              child: AspectRatio(
                aspectRatio: 1.25,
                child: listing.imageUrl.isEmpty
                    ? Container(
                        color: AppColors.surfaceVariant,
                        child: Icon(
                          Icons.image_outlined,
                          color: AppColors.textMuted,
                        ),
                      )
                    : Image.network(
                        listing.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: AppColors.surfaceVariant,
                          child: Icon(
                            Icons.image_outlined,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatPrice(listing.price),
                    style: AppType.body.copyWith(
                      fontWeight: FontWeight.w800,
                      color: kPakGreen,
                    ),
                  ),
                  Text(
                    listing.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption,
                  ),
                  if (listing.city.isNotEmpty)
                    Text(
                      listing.city,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// One line of the explanation.
class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: kPakGreen.withValues(alpha: 0.10),
          borderRadius: AppRadius.rMd,
        ),
        child: Icon(icon, color: kPakGreen, size: 20),
      ),
      const SizedBox(width: AppSpacing.md),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppType.body.copyWith(
              fontWeight: FontWeight.w700,
            )),
            Text(body, style: AppType.caption.copyWith(height: 1.4)),
          ],
        ),
      ),
    ],
  );
}
