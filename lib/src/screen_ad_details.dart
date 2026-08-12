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
              Positioned(
                left: 8,
                child: _GalleryNavArrow(
                  icon: Icons.chevron_left,
                  onTap: _index > 0 ? () => _go(-1) : null,
                ),
              ),
              Positioned(
                right: 8,
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
          padding: const EdgeInsets.all(8),
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
                Positioned(
                  top: AppSpacing.md,
                  right: AppSpacing.md,
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
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Tap-to-expand button (bottom-right).
              Positioned(
                bottom: AppSpacing.md,
                right: AppSpacing.md,
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
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
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
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
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
                      label: 'Call',
                      onTap: callSeller,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _ContactAction(
                      icon: Icons.chat,
                      label: 'WhatsApp',
                      color: const Color(0xFF25D366),
                      onTap: openWhatsApp,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _ContactAction(
                      icon: Icons.message_outlined,
                      label: 'Chat',
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          listing.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          _DetailFavoriteButton(listing: listing),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share',
            onPressed: shareAd,
          ),
          IconButton(
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Report ad',
            onPressed: reportAd,
          ),
          if (!isOwnAd)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'block') {
                  await blockUser(listing.userId);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Seller blocked — you won't see their ads.",
                      ),
                    ),
                  );
                  Navigator.pop(context);
                } else if (v == 'unblock') {
                  await unblockUser(listing.userId);
                  if (!context.mounted) return;
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
      ),
      bottomNavigationBar: _bottomActions(listing, isOwnAd),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (images.isNotEmpty) _gallery(images),

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
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
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
                        fontSize: 15,
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
                      _Pill(
                        label: '+ ${formatPrice(listing.deliveryFee)} delivery',
                        color: AppColors.success,
                      ),
                    if (listing.hasRecentPriceDrop) ...[
                      Text(
                        formatPrice(listing.previousPrice),
                        style: TextStyle(
                          fontSize: 15,
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
                      child: _IconText(
                        icon: Icons.location_on,
                        text: locationLine,
                      ),
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
                    trailing: Icon(
                      Icons.chevron_right,
                      color: AppColors.textMuted,
                    ),
                  );
                },
              ),
            ),
          ),

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
            Text(
              listing.description.isNotEmpty
                  ? listing.description
                  : 'No description provided.',
              style: TextStyle(
                fontSize: 14.5,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),

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
              child: Center(
                child: Text('This is your ad', style: AppType.caption),
              ),
            ),

          _SimilarAds(listing: listing),
          const SizedBox(height: AppSpacing.section),
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
              fontSize: 11.5,
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
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: c,
        side: BorderSide(color: c.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        minimumSize: const Size(0, 46),
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
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
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
          color = Colors.green.shade700;
        } else if (ratio <= 1.12) {
          label = 'Fair price';
          icon = Icons.check_circle;
          color = Colors.blue.shade700;
        } else {
          label = 'Above typical';
          icon = Icons.trending_up;
          color = Colors.orange.shade800;
        }

        final scope = sameSub ? listing.subcategory : listing.category;
        return Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
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
                        fontSize: 12,
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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 32),
            const Text(
              'Similar ads',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 250,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: shown.length,
                itemBuilder: (context, i) =>
                    HorizontalAdCard(listing: shown[i]),
              ),
            ),
          ],
        );
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
        leading: const Icon(Icons.shield_outlined, color: Colors.amber),
        title: const Text('Safety tips'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Align(
            alignment: Alignment.centerLeft,
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
            alignment: Alignment.centerLeft,
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
