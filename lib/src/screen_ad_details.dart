part of '../main.dart';

// Ad details, gallery, price insight and safety tips.

class FullScreenGallery extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const FullScreenGallery({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  @override
  State<FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<FullScreenGallery> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final next = (_index + delta).clamp(0, widget.images.length - 1);
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// Desktop/web keyboard control: left/right arrows change photo, Esc closes.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      _go(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _go(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    final multi = images.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: multi
            ? Text(
                '${_index + 1} / ${images.length}',
                style: const TextStyle(fontSize: 16, color: Colors.white),
              )
            : null,
      ),
      body: Focus(
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Stack(
          alignment: Alignment.center,
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: images.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Image.network(
                    images[i],
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    },
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image,
                      color: Colors.white,
                      size: 80,
                    ),
                  ),
                ),
              ),
            ),
            // Prev / next arrows — the primary way to move between photos on
            // web/desktop where there's no swipe gesture.
            if (multi) ...[
              PositionedDirectional(
                start: 8,
                child: _GalleryNavArrow(
                  icon: Icons.chevron_left,
                  onTap: _index > 0 ? () => _go(-1) : null,
                ),
              ),
              PositionedDirectional(
                end: 8,
                child: _GalleryNavArrow(
                  icon: Icons.chevron_right,
                  onTap: _index < images.length - 1 ? () => _go(1) : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A round, semi-transparent navigation arrow used over a photo. Disabled
/// (dimmed, non-tappable) when [onTap] is null.
class _GalleryNavArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _GalleryNavArrow({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: Colors.black.withValues(alpha: enabled ? 0.45 : 0.15),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Icon(
            icon,
            color: Colors.white.withValues(alpha: enabled ? 1 : 0.4),
            size: 28,
          ),
        ),
      ),
    );
  }
}

class AdDetailsScreen extends StatefulWidget {
  final Listing listing;

  const AdDetailsScreen({super.key, required this.listing});

  @override
  State<AdDetailsScreen> createState() => _AdDetailsScreenState();
}

class _AdDetailsScreenState extends State<AdDetailsScreen> {
  int currentImage = 0;
  final PageController _imageController = PageController();

  @override
  void initState() {
    super.initState();
    _incrementViews();
    recordRecentlyViewed(widget.listing);
    trackViewListing(
      listingId: widget.listing.id,
      category: widget.listing.category,
      price: parsePrice(widget.listing.price),
    );
  }

  @override
  void dispose() {
    _imageController.dispose();
    super.dispose();
  }

  void _openGallery(List<String> images, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenGallery(images: images, initialIndex: index),
      ),
    );
  }

  void _goToImage(int i) {
    _imageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _incrementViews() async {
    await _bumpStat('views');
  }

  /// Increments a non-owner lead/stat counter on the listing (best-effort).
  Future<void> _bumpStat(String field) async {
    final id = widget.listing.id;
    if (id.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('listings').doc(id).update({
        field: FieldValue.increment(1),
      });
    } catch (_) {
      // Non-critical; ignore failures (e.g. favorites cache docs).
    }
  }

  Future<void> openWhatsApp() async {
    if (!await ensureVerified(context)) return;
    if (!mounted) return;
    if (widget.listing.phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seller phone number is missing')),
      );
      return;
    }

    _bumpStat('whatsapps');
    final cleanedPhone = normalizePhoneForWhatsApp(widget.listing.phone);
    final url = Uri.parse('https://wa.me/$cleanedPhone');

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open WhatsApp')));
    }
  }

  Future<void> callSeller() async {
    if (!await ensureVerified(context)) return;
    if (!mounted) return;
    if (widget.listing.phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seller phone number is missing')),
      );
      return;
    }

    _bumpStat('calls');
    final url = Uri.parse('tel:${widget.listing.phone.trim()}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> openChat() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    if (!await ensureVerified(context)) return;
    if (!mounted) return;
    _bumpStat('chats');

    final listing = widget.listing;
    final buyerId = me.uid;
    final sellerId = listing.userId;
    final chatId = '${listing.id}_$buyerId';

    // Use a privacy-friendly buyer name (never the raw email).
    final myDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(buyerId)
        .get();
    if (!mounted) return;
    final buyerName = friendlyName(myDoc.data(), email: me.email);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: chatId,
          listingId: listing.id,
          listingTitle: listing.title,
          listingImage: listing.galleryImages.isEmpty
              ? ''
              : listing.galleryImages.first,
          buyerId: buyerId,
          sellerId: sellerId,
          buyerName: buyerName,
          sellerName: listing.sellerName.isEmpty
              ? 'Seller'
              : listing.sellerName,
        ),
      ),
    );
  }

  Future<void> shareAd() async {
    final l = widget.listing;
    final loc = [l.city, l.location].where((e) => e.isNotEmpty).join(', ');
    final text = [
      l.title,
      '${formatPrice(l.price)}${loc.isEmpty ? '' : ' · $loc'}',
      // Link to the ad itself, not the site root. WhatsApp is the main way
      // sellers distribute their listings here, and sharing previously sent
      // the buyer to a homepage with no way back to the item.
      'See it on PakBazar: ${listingShareUrl(l.id)}',
    ].join('\n');
    final messenger = ScaffoldMessenger.of(context);

    await showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.chat, color: Color(0xFF25D366)),
              title: const Text('Share on WhatsApp'),
              onTap: () async {
                Navigator.pop(context);
                final uri = Uri.parse(
                  'https://wa.me/?text=${Uri.encodeComponent(text)}',
                );
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy details'),
              onTap: () async {
                Navigator.pop(context);
                await Clipboard.setData(ClipboardData(text: text));
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Ad details copied — paste anywhere to share',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> reportAd() async {
    final reasons = [
      'Spam or scam',
      'Prohibited item',
      'Wrong category',
      'Fraudulent / fake',
      'Other',
    ];
    String selected = reasons.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Report this ad'),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return RadioGroup<String>(
                groupValue: selected,
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selected = value);
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: reasons
                      .map(
                        (r) => RadioListTile<String>(title: Text(r), value: r),
                      )
                      .toList(),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance.collection('reports').add({
        'listingId': widget.listing.id,
        'listingTitle': widget.listing.title,
        'reason': selected,
        'reporterId': FirebaseAuth.instance.currentUser?.uid ?? '',
        'createdAt': Timestamp.now(),
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not submit report. Try again.')),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Thanks, your report was submitted')),
    );
  }

  Future<void> openMap() async {
    final listing = widget.listing;
    if (!listing.hasCoordinates) return;

    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query='
      '${listing.latitude},${listing.longitude}',
    );

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open the map')));
    }
  }

  void openSellerProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SellerProfileScreen(
          sellerId: widget.listing.userId,
          sellerName: widget.listing.sellerName,
        ),
      ),
    );
  }

  /// The full-bleed image carousel with counter, expand button, arrows and a
  /// thumbnail strip. Sits above the scrolling body, edge to edge.

  /// Page chrome, shared by the phone and desktop layouts.
  PreferredSizeWidget _detailAppBar(Listing listing, bool isOwnAd) {
    return AppBar(
      title: Text(listing.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        _DetailFavoriteButton(listing: listing),
        IconButton(
          icon: const Icon(Icons.share_outlined),
          tooltip: 'Share',
          onPressed: shareAd,
        ),
        IconButton(
          icon: const Icon(Icons.flag_outlined),
          tooltip: tr('ad.reportAd', 'Report ad'),
          onPressed: reportAd,
        ),
        if (!isOwnAd)
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'block') {
                await blockUser(listing.userId);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Seller blocked — you won't see their ads."),
                  ),
                );
                Navigator.pop(context);
              } else if (v == 'unblock') {
                await unblockUser(listing.userId);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Seller unblocked.')),
                );
                setState(() {});
              }
            },
            itemBuilder: (context) => [
              blockedUserIds.contains(listing.userId)
                  ? const PopupMenuItem(
                      value: 'unblock',
                      child: Text('Unblock seller'),
                    )
                  : const PopupMenuItem(
                      value: 'block',
                      child: Text('Block seller'),
                    ),
            ],
          ),
      ],
    );
  }

  Widget _gallery(List<String> images) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _imageController,
                itemCount: images.length,
                onPageChanged: (i) => setState(() => currentImage = i),
                itemBuilder: (context, index) => GestureDetector(
                  onTap: () => _openGallery(images, index),
                  child: AppNetworkImage(url: images[index], iconSize: 56),
                ),
              ),
              // Photo counter (top-right).
              if (images.length > 1)
                PositionedDirectional(
                  top: AppSpacing.md,
                  end: AppSpacing.md,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: AppRadius.rPill,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.photo_library_outlined,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${currentImage + 1}/${images.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Tap-to-expand button (bottom-right).
              PositionedDirectional(
                bottom: AppSpacing.md,
                end: AppSpacing.md,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _openGallery(images, currentImage),
                    child: const Padding(
                      padding: EdgeInsets.all(7),
                      child: Icon(
                        Icons.fullscreen,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
              // Prev / next arrows — web/desktop friendly.
              if (images.length > 1) ...[
                Positioned.fill(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 6),
                      child: _GalleryNavArrow(
                        icon: Icons.chevron_left,
                        onTap: currentImage > 0
                            ? () => _goToImage(currentImage - 1)
                            : null,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: _GalleryNavArrow(
                        icon: Icons.chevron_right,
                        onTap: currentImage < images.length - 1
                            ? () => _goToImage(currentImage + 1)
                            : null,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (images.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: SizedBox(
              height: 58,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: AppSpacing.pageH,
                itemCount: images.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, i) {
                  final selected = i == currentImage;
                  return GestureDetector(
                    onTap: () => _goToImage(i),
                    child: Container(
                      width: 58,
                      decoration: BoxDecoration(
                        borderRadius: AppRadius.rSm,
                        border: Border.all(
                          color: selected
                              ? AppColors.accent
                              : AppColors.borderSoft,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: AppNetworkImage(url: images[i], iconSize: 18),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  /// A titled block in the detail body, with the page's standard padding.
  Widget _section(String title, Widget child) => Padding(
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
        const SizedBox(height: AppSpacing.md),
        child,
      ],
    ),
  );

  /// The fixed contact / purchase bar pinned to the bottom of the screen, so a
  /// buyer can always reach Call / WhatsApp / Chat without scrolling back.
  Widget? _bottomActions(Listing listing, bool isOwnAd) {
    if (isOwnAd) return null;
    final canBuy = listing.isAvailableForSale && isBuyable(listing);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.borderSoft)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.md,
            AppSpacing.page,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canBuy) ...[
                Row(
                  children: [
                    Expanded(
                      child: PrimaryActionButton(
                        label: 'Buy Now',
                        icon: Icons.shopping_cart_checkout,
                        onPressed: () => openCheckout(context, listing),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: AddToCartButton(listing: listing)),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Row(
                children: [
                  Expanded(
                    child: _ContactAction(
                      icon: Icons.phone,
                      label: tr('ad.call', 'Call'),
                      onTap: callSeller,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _ContactAction(
                      icon: Icons.chat,
                      label: tr('ad.whatsapp', 'WhatsApp'),
                      color: const Color(0xFF25D366),
                      onTap: openWhatsApp,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _ContactAction(
                      icon: Icons.message_outlined,
                      label: tr('ad.chat', 'Chat'),
                      onTap: openChat,
                    ),
                  ),
                  if (canBuy) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _ContactAction(
                        icon: Icons.local_offer_outlined,
                        label: 'Offer',
                        onTap: () => showOfferSheet(context, listing),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final images = listing.galleryImages;
    final me = FirebaseAuth.instance.currentUser;
    final isOwnAd = me != null && me.uid == listing.userId;
    final posted = timeAgo(listing.createdAt);
    final locationLine = [
      listing.city,
      listing.location,
    ].where((e) => e.isNotEmpty).join(', ');

    // The page is ONE list on a phone and TWO columns on a desktop, so each
    // section is built once here and arranged twice below. On a monitor the
    // photo and the write-up belong on the left, and everything a buyer acts
    // on — price, contact, seller — belongs in a rail beside them that stays
    // put while they read. The phone keeps its sticky bar; a desktop does not
    // need one, because the rail is already always on screen.
    final galleryBlock = <Widget>[if (images.isNotEmpty) _gallery(images)];
    final headlineBlock = <Widget>[
      // ── Headline: status, price, title, meta, location ──
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.xl,
          AppSpacing.page,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!listing.isAvailableForSale)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: switch (listing.status) {
                    'sold' => AppColors.error,
                    'out_of_stock' => AppColors.warning,
                    _ => AppColors.textMuted,
                  },
                  borderRadius: AppRadius.rMd,
                ),
                child: Text(
                  listing.statusLabel.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: 2.5,
                  ),
                ),
              ),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  priceLabel(listing),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (deliveryFeeOf(listing) > 0)
                  // Muted, not green. Delivery is money the buyer has to
                  // add on, and the success colour is what this app uses
                  // to say something went their way.
                  _Pill(
                    label: '+ ${formatPrice(listing.deliveryFee)} delivery',
                    color: AppColors.textSecondary,
                  ),
                if (listing.hasRecentPriceDrop) ...[
                  Text(
                    formatPrice(listing.previousPrice),
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textMuted,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  _Pill(
                    label: 'Price dropped',
                    icon: Icons.south,
                    color: AppColors.error,
                  ),
                ],
                if (listing.negotiable)
                  _Pill(label: 'Negotiable', color: AppColors.warning),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              listing.title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1.3,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: 6,
              children: [
                if (posted.isNotEmpty)
                  _IconText(icon: Icons.access_time, text: posted),
                _IconText(
                  icon: Icons.remove_red_eye,
                  text: '${listing.views} views',
                ),
                if (listing.condition.isNotEmpty)
                  _IconText(icon: Icons.verified, text: listing.condition),
                if (listing.deliveryAvailable)
                  const _IconText(
                    icon: Icons.delivery_dining,
                    text: 'Delivery available',
                  ),
                if (listing.codAvailable)
                  const _IconText(
                    icon: Icons.local_shipping,
                    text: 'Cash on Delivery',
                  ),
              ],
            ),
            if (!listing.isSold) _PriceInsight(listing: listing),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _IconText(icon: Icons.location_on, text: locationLine),
                ),
                if (listing.hasCoordinates)
                  TextButton.icon(
                    onPressed: openMap,
                    icon: const Icon(Icons.map, size: 18),
                    label: const Text('View on map'),
                  ),
              ],
            ),
            if (listing.category.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _IconText(
                icon: Icons.category,
                text: listing.subcategory.isEmpty
                    ? listing.category
                    : '${listing.category} • ${listing.subcategory}',
              ),
            ],
          ],
        ),
      ),
    ];
    final sellerBlock = <Widget>[
      // ── Seller ──
      _section(
        'Seller',
        InkWell(
          borderRadius: AppRadius.rCard,
          onTap: openSellerProfile,
          child: StreamBuilder<DocumentSnapshot>(
            stream: listing.userId.isEmpty
                ? null
                : FirebaseFirestore.instance
                      .collection('users')
                      .doc(listing.userId)
                      .snapshots(),
            builder: (context, snap) {
              final data = snap.data?.data() as Map<String, dynamic>? ?? {};
              final count = (data['ratingCount'] as num?)?.toInt() ?? 0;
              final sum = (data['ratingSum'] as num?)?.toDouble() ?? 0;
              final avg = count > 0 ? sum / count : 0.0;
              final labels = <String>[
                if (data['idVerified'] == true) 'ID verified',
                if (data['isBusiness'] == true) 'Business',
              ];

              return SellerCard(
                name: listing.sellerName.isEmpty
                    ? 'Seller'
                    : listing.sellerName,
                subtitle: labels.join(' · '),
                avatarUrl: data['photoUrl']?.toString() ?? '',
                verified: data['verified'] == true,
                rating: count > 0 ? avg : null,
                reviewCount: count > 0 ? count : null,
                onTap: openSellerProfile,
                trailing: Icon(Icons.chevron_right, color: AppColors.textMuted),
              );
            },
          ),
        ),
      ),
    ];
    final detailBlock = <Widget>[
      // ── Specifications ──
      if (listing.attributes.isNotEmpty)
        _section(
          'Specifications',
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              children: [
                for (final e in listing.attributes.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 4,
                          child: Text(e.key, style: AppType.secondary),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          flex: 6,
                          child:
                              (e.key == 'Color' &&
                                  productColorByName(e.value) != null)
                              ? Row(
                                  children: [
                                    Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: productColorByName(e.value),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: AppColors.border,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Text(
                                        e.value,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  e.value,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

      // ── Description ──
      _section(
        'Description',
        ExpandableText(
          text: listing.description.isNotEmpty
              ? listing.description
              : 'No description provided.',
          style: TextStyle(
            fontSize: 15,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
      ),

      // Sits between the description and the safety notice on purpose: the
      // buyer has just read what the thing is, and this is the moment they
      // decide how many of them they want.
      _MoreDesigns(listing: listing),

      const Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.section,
          AppSpacing.page,
          0,
        ),
        child: _SafetyTips(),
      ),

      if (isOwnAd)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.section),
          child: Center(child: Text('This is your ad', style: AppType.caption)),
        ),

      _SimilarAds(listing: listing),
      const SizedBox(height: AppSpacing.section),
    ];

    if (AppBreak.isWide(context)) {
      return Scaffold(
        appBar: _detailAppBar(listing, isOwnAd),
        body: ContentColumn(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: AppSpacing.section),
                  children: [...galleryBlock, ...detailBlock],
                ),
              ),
              const SizedBox(width: AppSpacing.xl),
              SizedBox(
                width: 380,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: AppSpacing.section),
                  children: [
                    ...headlineBlock,
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.page,
                        AppSpacing.lg,
                        AppSpacing.page,
                        0,
                      ),
                      child: _bottomActions(listing, isOwnAd),
                    ),
                    ...sellerBlock,
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: _detailAppBar(listing, isOwnAd),
      bottomNavigationBar: _bottomActions(listing, isOwnAd),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          ...galleryBlock,
          ...headlineBlock,
          ...sellerBlock,
          ...detailBlock,
        ],
      ),
    );
  }
}

/// The heart in the detail app bar. Shares [favoriteListings] and the same
/// Firestore write as the cards, so state stays consistent everywhere.
class _DetailFavoriteButton extends StatefulWidget {
  final Listing listing;
  const _DetailFavoriteButton({required this.listing});

  @override
  State<_DetailFavoriteButton> createState() => _DetailFavoriteButtonState();
}

class _DetailFavoriteButtonState extends State<_DetailFavoriteButton> {
  bool get _isFav => favoriteListings.any((i) => i.id == widget.listing.id);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _isFav ? 'Saved' : 'Save ad',
      icon: Icon(
        _isFav ? Icons.favorite : Icons.favorite_border,
        color: _isFav ? AppColors.error : null,
      ),
      onPressed: () async {
        final was = _isFav;
        setState(() {
          if (was) {
            favoriteListings.removeWhere((i) => i.id == widget.listing.id);
          } else {
            favoriteListings.add(widget.listing);
          }
        });
        await toggleFavoriteListing(widget.listing, wasFav: was);
      },
    );
  }
}

/// A small labelled pill used beside the price (delivery fee, price drop…).
class _Pill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;

  const _Pill({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadius.rSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// One compact button in the fixed bottom contact bar.
class _ContactAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ContactAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.accent;
    // A TEXT button, not an outlined one.
    //
    // Six actions sat on this bar in two rows — Buy Now, Add to Cart, Call,
    // WhatsApp, Chat, Offer — every one of them boxed, and together they held
    // a fifth of the screen on every ad. Six equally-loud buttons is not six
    // choices, it is a decision to make before you have finished reading the
    // ad.
    //
    // Nothing is removed: buying stays the filled button it was, and these
    // four keep their icon, their label and their colour. They simply stop
    // shouting, and the bar gets shorter.
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: c,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        minimumSize: const Size(0, 40),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Horizontal rail of other ads in the same category (excludes this ad).
/// Compares this ad's price against recent comparable ads (same subcategory, or
/// category as a fallback) and shows a "Great price / Fair price / Above
/// typical" badge plus the typical range. Hidden when there aren't enough
/// comparable ads to be meaningful.
class _PriceInsight extends StatelessWidget {
  final Listing listing;

  const _PriceInsight({required this.listing});

  @override
  Widget build(BuildContext context) {
    final myPrice = parsePrice(listing.price);
    if (listing.category.isEmpty || myPrice <= 0) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('listings')
          .where('category', isEqualTo: listing.category)
          .where('approvalStatus', isEqualTo: 'approved')
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final sameSub = listing.subcategory.isNotEmpty;
        final prices =
            snapshot.data!.docs
                .map((d) => Listing.fromDoc(d))
                .where(
                  (l) =>
                      l.id != listing.id &&
                      !l.isSold &&
                      l.isApproved &&
                      !isHiddenSeller(l.userId) &&
                      (!sameSub || l.subcategory == listing.subcategory),
                )
                .map((l) => parsePrice(l.price))
                .where((p) => p > 0)
                .toList()
              ..sort();
        if (prices.length < 4) return const SizedBox.shrink();

        final median = prices[prices.length ~/ 2];
        if (median <= 0) return const SizedBox.shrink();
        final low = prices[(prices.length * 0.15).floor()];
        final high =
            prices[(prices.length * 0.85).floor().clamp(0, prices.length - 1)];
        final ratio = myPrice / median;

        final String label;
        final IconData icon;
        final Color color;
        if (ratio <= 0.85) {
          label = 'Great price';
          icon = Icons.thumb_up;
          color = AppColors.success;
        } else if (ratio <= 1.12) {
          label = 'Fair price';
          icon = Icons.check_circle;
          color = AppColors.info;
        } else {
          label = 'Above typical';
          icon = Icons.trending_up;
          color = AppColors.warning;
        }

        final scope = sameSub ? listing.subcategory : listing.category;
        return Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: AppRadius.rSm,
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Text(
                      'Similar $scope ads sell for '
                      '${formatPrice(low.toStringAsFixed(0))}–'
                      '${formatPrice(high.toStringAsFixed(0))}',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The seller's other designs of the same thing, pickable in one go.
///
/// Sellers here do not post one ad with options — they post one ad PER design.
/// "Meer Collections" has five separate DHANAK suit ads at the same price, one
/// per embroidery. A buyer who wants two of them has to leave this page, find
/// the other ad, and add each separately, which is exactly the point where
/// somebody gives up and asks on WhatsApp instead.
///
/// So the designs come to the buyer: every in-stock ad from this seller in the
/// same subcategory, each with a quantity, and one button that puts the lot in
/// the cart. The cart is already multi-item and the master order already fans
/// out per seller, so "ordered at the same time" needs no change to the money
/// path — this is the selection step that was missing.
///
/// THIS ad is the first tile and starts selected, because the buyer is already
/// looking at it: the common case is "this one, plus that one", and making them
/// tick the thing they are reading would be silly.
class _MoreDesigns extends StatefulWidget {
  final Listing listing;

  const _MoreDesigns({required this.listing});

  @override
  State<_MoreDesigns> createState() => _MoreDesignsState();
}

class _MoreDesignsState extends State<_MoreDesigns> {
  /// listingId → quantity. Absent means unselected; the current ad starts here.
  late final Map<String, int> _picked = {widget.listing.id: 1};
  bool _busy = false;

  /// Matching is by subcategory when the ad has one, because that is what
  /// separates "another design of this suit" from "this seller also sells
  /// watches". Only ads with no subcategory at all fall back to the category.
  bool _isSibling(Listing l) {
    if (l.id == widget.listing.id) return false;
    if (!l.isApproved || !l.isAvailableForSale || !isBuyable(l)) return false;
    return widget.listing.subcategory.isNotEmpty
        ? l.subcategory == widget.listing.subcategory
        : l.category == widget.listing.category;
  }

  void _toggle(String id) => setState(() {
    if (_picked.containsKey(id)) {
      _picked.remove(id);
    } else {
      _picked[id] = 1;
    }
  });

  /// Clamped to the same ceiling as [updateCartQty], so a held-down stepper
  /// cannot build a line the cart would then refuse to reproduce.
  void _setQty(String id, int q) => setState(() {
    if (q < 1) {
      _picked.remove(id);
    } else {
      _picked[id] = q > 99 ? 99 : q;
    }
  });

  Future<void> _addPicked(List<Listing> pool) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final byId = {for (final l in pool) l.id: l};

    var added = 0;
    var refused = 0;
    for (final entry in _picked.entries) {
      final l = byId[entry.key];
      // An ad the seller marked sold while this page was open is skipped
      // rather than silently dropped — the count in the snackbar is what
      // actually reached the cart.
      if (l == null) continue;
      final ok = await addListingToCart(l, qty: entry.value);
      ok ? added += entry.value : refused++;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      // Back to the starting state: this ad only. Leaving four designs ticked
      // after they are in the cart invites adding them twice.
      _picked
        ..clear()
        ..[widget.listing.id] = 1;
    });

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          added == 0
              ? 'Those designs are no longer available.'
              : '$added item${added == 1 ? '' : 's'} added to cart'
                    '${refused > 0 ? ' · $refused unavailable' : ''}.',
        ),
        action: added == 0
            ? null
            : SnackBarAction(
                label: 'View cart',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CartScreen()),
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser?.uid;
    // Nothing to offer on your own ad, on an ad nobody can buy, or from a
    // seller the app is hiding.
    if (me == widget.listing.userId ||
        !widget.listing.isAvailableForSale ||
        !isBuyable(widget.listing) ||
        isHiddenSeller(widget.listing.userId)) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot>(
      // Ordered, not just limited: a shop with 200 ads would otherwise hand
      // back an arbitrary 40 and the designs posted this week — the ones a
      // buyer is here for — might not be among them. The
      // userId + approvalStatus + createdAt index this needs already exists
      // (My Ads uses it), so it costs nothing to ask for.
      stream: FirebaseFirestore.instance
          .collection('listings')
          .where('userId', isEqualTo: widget.listing.userId)
          .where('approvalStatus', isEqualTo: 'approved')
          .orderBy('createdAt', descending: true)
          .limit(40)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        // Already newest-first from the query.
        final siblings = snapshot.data!.docs
            .map((d) => Listing.fromDoc(d))
            .where(_isSibling)
            .toList();
        if (siblings.isEmpty) return const SizedBox.shrink();

        final pool = [widget.listing, ...siblings.take(12)];
        // A tile the buyer scrolled past and ticked, on an ad that has since
        // gone out of stock, must not keep counting toward the total.
        final live = {for (final l in pool) l.id};
        final units = _picked.entries
            .where((e) => live.contains(e.key))
            .fold<int>(0, (a, e) => a + e.value);
        final total = _picked.entries
            .where((e) => live.contains(e.key))
            .fold<double>(
              0,
              (a, e) =>
                  a +
                  parsePrice(pool.firstWhere((l) => l.id == e.key).price) *
                      e.value,
            );

        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.section),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: 'More designs from this seller',
                subtitle: 'Pick the ones you want — they go in one order.',
                icon: Icons.grid_view_rounded,
              ),
              SizedBox(
                height: _DesignTile.height,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.page,
                  ),
                  itemCount: pool.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: AppSpacing.md),
                  itemBuilder: (context, i) {
                    final l = pool[i];
                    return _DesignTile(
                      listing: l,
                      isThisAd: i == 0,
                      quantity: _picked[l.id],
                      onToggle: () => _toggle(l.id),
                      onQty: (q) => _setQty(l.id, q),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.md,
                  AppSpacing.page,
                  0,
                ),
                child: PrimaryActionButton(
                  label: units == 0
                      ? 'Select a design'
                      : 'Add $units item${units == 1 ? '' : 's'} to cart · '
                            '${formatPrice(total.toStringAsFixed(0))}',
                  icon: Icons.add_shopping_cart,
                  busy: _busy,
                  onPressed: units == 0 ? null : () => _addPicked(pool),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One design in the picker: photo, price, and a tick that becomes a stepper.
class _DesignTile extends StatelessWidget {
  final Listing listing;
  final bool isThisAd;
  final int? quantity; // null = not selected
  final VoidCallback onToggle;
  final ValueChanged<int> onQty;

  const _DesignTile({
    required this.listing,
    required this.isThisAd,
    required this.quantity,
    required this.onToggle,
    required this.onQty,
  });

  static const double width = 148;

  /// Photo + price line + title line + the stepper row, all fixed, so the rail
  /// gets a real height instead of a guessed one.
  static const double height = width + 104;

  @override
  Widget build(BuildContext context) {
    final selected = quantity != null;
    return SizedBox(
      width: width,
      child: AppCard(
        padding: EdgeInsets.zero,
        color: selected ? AppColors.primarySoft : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SizedBox(
                  width: width,
                  height: width,
                  child: AppNetworkImage(
                    url: listing.imageUrl,
                    decodeWidth: width,
                  ),
                ),
                Positioned(
                  top: AppSpacing.sm,
                  left: AppSpacing.sm,
                  child: GestureDetector(
                    onTap: onToggle,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.accent : AppColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? AppColors.accent
                              : AppColors.borderSoft,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        selected ? Icons.check : Icons.add,
                        size: 17,
                        color: selected
                            ? AppColors.textOnPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                if (isThisAd)
                  Positioned(
                    top: AppSpacing.sm,
                    right: AppSpacing.sm,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.overlay,
                        borderRadius: AppRadius.rPill,
                      ),
                      child: Text(
                        'This ad',
                        style: AppType.caption.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatPrice(listing.price),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.price,
                  ),
                  Text(
                    listing.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption,
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xs,
                0,
                AppSpacing.xs,
                AppSpacing.xs,
              ),
              child: selected
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _StepButton(
                          icon: Icons.remove,
                          onTap: () => onQty(quantity! - 1),
                        ),
                        Text('$quantity', style: AppType.cardTitle),
                        _StepButton(
                          icon: Icons.add,
                          onTap: () => onQty(quantity! + 1),
                        ),
                      ],
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: onToggle,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('Select'),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.rPill,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Icon(icon, size: 18, color: AppColors.textSecondary),
      ),
    );
  }
}

class _SimilarAds extends StatelessWidget {
  final Listing listing;

  const _SimilarAds({required this.listing});

  @override
  Widget build(BuildContext context) {
    if (listing.category.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('listings')
          .where('category', isEqualTo: listing.category)
          .where('approvalStatus', isEqualTo: 'approved')
          .limit(12)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final items =
            snapshot.data!.docs
                .map((d) => Listing.fromDoc(d))
                .where(
                  (l) =>
                      l.id != listing.id &&
                      l.isApproved &&
                      !l.isSold &&
                      !isHiddenSeller(l.userId),
                )
                .toList()
              ..sort((a, b) {
                final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
                final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
                return bt.compareTo(at);
              });
        final shown = items.take(10).toList();
        if (shown.isEmpty) return const SizedBox.shrink();

        // The same rail every other list of ads in the app uses: page
        // padding, separators, and a height derived from the card rather
        // than guessed. This one was hand-rolled with none of the three, so
        // its heading and its first card sat flush against the screen edge
        // while everything above them was inset.
        return HorizontalListingSection(title: 'Similar ads', listings: shown);
      },
    );
  }
}

class _IconText extends StatelessWidget {
  final IconData icon;
  final String text;

  const _IconText({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text, style: TextStyle(color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}

class _SafetyTips extends StatelessWidget {
  const _SafetyTips();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      color: dark ? const Color(0xFF33301E) : Colors.amber.shade50,
      child: ExpansionTile(
        leading: Icon(Icons.shield_outlined, color: AppColors.warning),
        title: const Text('Safety tips'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              // "Never send money in advance" directly contradicted the
              // product: paying online IS sending money in advance, into
              // PakBazar's hold. The distinction that matters to a buyer is
              // paying through the platform versus paying the seller directly.
              '• Pay through PakBazar — your money is held until you '
              'confirm delivery.\n'
              '• Never send money directly to a seller\'s bank or wallet '
              'account.\n'
              '• Meet in a public place during the day for cash deals.\n'
              '• Inspect the item before you confirm delivery.\n'
              '• Avoid sharing personal/banking details in chat.\n'
              '• Report suspicious ads using the flag icon.',
              style: TextStyle(height: 1.5),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TrustSafetyScreen()),
              ),
              child: const Text('Read full Trust & Safety guidelines →'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Seller profile + reviews
// ---------------------------------------------------------------------------

/// Star-picker + text dialog for rating a seller. No-op if not signed in or
/// reviewing yourself.
