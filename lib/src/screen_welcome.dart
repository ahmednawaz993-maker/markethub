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
              _section(
                title: 'Buying, with your money protected',
                subtitle:
                    'Pay through PakBazar and the money is held until you '
                    'have the item. It is released to the seller when you '
                    'confirm — or returned to you if the deal falls through.',
                steps: const [
                  (
                    Icons.search,
                    'Find it',
                    'Search by city and category, or follow sellers you like.',
                  ),
                  (
                    Icons.forum_outlined,
                    'Agree a price',
                    'Message the seller and make an offer. They can counter.',
                  ),
                  (
                    Icons.verified_user_outlined,
                    'Pay into escrow',
                    'We hold the payment. Cash on delivery is there too, if '
                        'the seller offers it.',
                  ),
                  (
                    Icons.local_shipping_outlined,
                    'Get it, then release',
                    'Confirm delivery and the seller is paid. Not right? Ask '
                        'for a refund or return.',
                  ),
                ],
              ),
              _section(
                title: 'Selling takes a few minutes',
                subtitle:
                    'Post an ad, answer your messages, get paid. There is no '
                    'listing fee, and during the free-launch period there is '
                    'no commission on a sale either.',
                steps: const [
                  (
                    Icons.add_a_photo_outlined,
                    'Post your ad',
                    'Photos, price, city, condition. It goes live once our '
                        'team has checked it.',
                  ),
                  (
                    Icons.badge_outlined,
                    'Verify yourself',
                    'A verified badge on your ads. Businesses get a shopfront '
                        'page of their own.',
                  ),
                  (
                    Icons.payments_outlined,
                    'Get paid',
                    'Money lands in your PakBazar wallet and you withdraw it '
                        'to your account.',
                  ),
                ],
              ),
              _safety(),
              _extras(),
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
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Pakistan’s marketplace for buying and selling anything, safely.',
          style: AppType.sectionTitle.copyWith(
            color: Colors.white,
            height: 1.35,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Cars, phones, property, furniture, livestock — listed by people and '
          'businesses near you. Deal in chat, pay into escrow, and only '
          'release the money when the item is in your hands.',
          style: AppType.body.copyWith(
            color: Colors.white.withValues(alpha: 0.92),
            height: 1.45,
          ),
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

  Widget _section({
    required String title,
    required String subtitle,
    required List<(IconData, String, String)> steps,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.page,
      AppSpacing.section,
      AppSpacing.page,
      0,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppType.sectionTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(subtitle, style: AppType.caption.copyWith(height: 1.45)),
        const SizedBox(height: AppSpacing.lg),
        for (final (icon, heading, detail) in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
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
                      Text(
                        heading,
                        style: AppType.body.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        detail,
                        style: AppType.caption.copyWith(height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _safety() => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.page,
      AppSpacing.section,
      AppSpacing.page,
      0,
    ),
    child: AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined, color: kPakGreen),
              const SizedBox(width: AppSpacing.sm),
              // Expanded for the same reason as the hero title: a heading in a
              // Row beside an icon takes its natural width and pushes off the
              // edge on a narrow phone.
              Expanded(
                child: Text(
                  'How we keep it safe',
                  style: AppType.sectionTitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          for (final line in const [
            'Every ad is reviewed by our team before it appears.',
            'Sellers verify their identity; businesses are verified separately.',
            'Payments sit in escrow until the buyer confirms delivery.',
            'Refunds, returns and cancellations are handled in the app.',
            'Report or block anyone. Suspended accounts disappear from search.',
            'Contact numbers are never shown publicly or to search engines.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check, size: 16, color: kPakGreen),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      line,
                      style: AppType.caption.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Widget _extras() => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.page,
      AppSpacing.section,
      AppSpacing.page,
      0,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('And a reason to come back', style: AppType.sectionTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'A marketplace is only open when you need something. These are for '
          'the other days.',
          style: AppType.caption.copyWith(height: 1.45),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: const [
            Expanded(
              child: _TileCard(
                icon: Icons.casino,
                title: 'Ludo',
                body: 'Play online with friends, with chat at the table.',
              ),
            ),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: _TileCard(
                icon: Icons.stairs,
                title: 'Saanp Seerhi',
                body: 'Snakes and ladders, on one phone.',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: const [
            Expanded(
              child: _TileCard(
                icon: Icons.mosque_outlined,
                title: 'Prayer timings',
                body: 'Daily namaz times for your city.',
              ),
            ),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: _TileCard(
                icon: Icons.menu_book_outlined,
                title: 'Quran',
                body: 'Read with Urdu translation.',
              ),
            ),
          ],
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

class _TileCard extends StatelessWidget {
  const _TileCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: kPakGreen),
        const SizedBox(height: AppSpacing.sm),
        Text(title, style: AppType.body.copyWith(fontWeight: FontWeight.w700)),
        Text(body, style: AppType.caption.copyWith(height: 1.35)),
      ],
    ),
  );
}
