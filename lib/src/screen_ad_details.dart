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
      body: Stack(
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
      await FirebaseFirestore.instance
          .collection('listings')
          .doc(id)
          .update({field: FieldValue.increment(1)});
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
      'See more on PakBazar: https://pakbazar24.com',
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
                        (r) => RadioListTile<String>(
                          title: Text(r),
                          value: r,
                        ),
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

    await FirebaseFirestore.instance.collection('reports').add({
      'listingId': widget.listing.id,
      'listingTitle': widget.listing.title,
      'reason': selected,
      'reporterId': FirebaseAuth.instance.currentUser?.uid ?? '',
      'createdAt': Timestamp.now(),
    });

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

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final images = listing.galleryImages;
    final me = FirebaseAuth.instance.currentUser;
    final isOwnAd = me != null && me.uid == listing.userId;
    final posted = timeAgo(listing.createdAt);

    return Scaffold(
      appBar: AppBar(
        title: Text(listing.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
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
                      content: Text("Seller blocked — you won't see their ads."),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            if (images.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: isPhone(context) ? 250 : 320,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      PageView.builder(
                        controller: _imageController,
                        itemCount: images.length,
                        onPageChanged: (i) =>
                            setState(() => currentImage = i),
                        itemBuilder: (context, index) {
                          return GestureDetector(
                            onTap: () => _openGallery(images, index),
                            child: Image.network(
                              images[index],
                              width: double.infinity,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return Container(
                                  color: Colors.grey.shade200,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: Colors.grey.shade200,
                                  child: const Center(
                                    child: Icon(Icons.image, size: 80),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                      // Photo counter (top-right).
                      if (images.length > 1)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.photo_library,
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
                        bottom: 10,
                        right: 10,
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
              ),
              // Thumbnail strip for quick jumping between photos.
              if (images.length > 1) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 60,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: images.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final selected = i == currentImage;
                      return GestureDetector(
                        onTap: () => _goToImage(i),
                        child: Container(
                          width: 60,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selected ? kPakGreen : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              images[i],
                              fit: BoxFit.cover,
                              width: 60,
                              height: 60,
                              errorBuilder: (_, _, _) => Container(
                                color: Colors.grey.shade300,
                                child: const Icon(Icons.image, size: 20),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
            const SizedBox(height: 16),
            if (listing.isSold)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.red.shade700,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'SOLD',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    letterSpacing: 3,
                  ),
                ),
              ),
            Text(
              listing.title,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  priceLabel(listing),
                  style: const TextStyle(
                    fontSize: 24,
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (listing.hasRecentPriceDrop) ...[
                  Text(
                    formatPrice(listing.previousPrice),
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.grey,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.south, size: 12, color: Colors.red.shade700),
                        const SizedBox(width: 2),
                        Text(
                          'Price dropped',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (listing.negotiable)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Negotiable',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 4,
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _IconText(
                    icon: Icons.location_on,
                    text: [
                      listing.city,
                      listing.location,
                    ].where((e) => e.isNotEmpty).join(', '),
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
              const SizedBox(height: 8),
              _IconText(
                icon: Icons.category,
                text: listing.subcategory.isEmpty
                    ? listing.category
                    : '${listing.category} • ${listing.subcategory}',
              ),
            ],
            const Divider(height: 32),
            // Seller row
            InkWell(
              onTap: openSellerProfile,
              child: StreamBuilder<DocumentSnapshot>(
                stream: listing.userId.isEmpty
                    ? null
                    : FirebaseFirestore.instance
                          .collection('users')
                          .doc(listing.userId)
                          .snapshots(),
                builder: (context, snap) {
                  final data =
                      snap.data?.data() as Map<String, dynamic>? ?? {};
                  final count =
                      (data['ratingCount'] as num?)?.toInt() ?? 0;
                  final sum = (data['ratingSum'] as num?)?.toDouble() ?? 0;
                  final avg = count > 0 ? sum / count : 0.0;
                  final verified = data['verified'] == true;

                  return Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: kPakGreen,
                        child: Icon(Icons.person, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    listing.sellerName.isEmpty
                                        ? 'Seller'
                                        : listing.sellerName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (verified) ...[
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.verified,
                                    size: 16,
                                    color: kPakGreen,
                                  ),
                                ],
                                if (data['idVerified'] == true) ...[
                                  const SizedBox(width: 4),
                                  const Tooltip(
                                    message: 'ID Verified',
                                    child: Icon(
                                      Icons.verified_user,
                                      size: 16,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ],
                                if (data['isBusiness'] == true) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: kPakGreen,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'BUSINESS',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            StarRating(rating: avg, count: count, size: 14),
                            if (data['isBusiness'] == true) ...[
                              const SizedBox(height: 6),
                              OutlinedButton.icon(
                                onPressed: openSellerProfile,
                                icon: const Icon(Icons.storefront, size: 16),
                                label: const Text('Visit store'),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 2,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  );
                },
              ),
            ),
            if (listing.attributes.isNotEmpty) ...[
              const Divider(height: 32),
              const Text(
                'Details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...listing.attributes.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 150,
                        child: Text(
                          e.key,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                      Expanded(
                        child: (e.key == 'Color' &&
                                productColorByName(e.value) != null)
                            ? Row(
                                children: [
                                  Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: productColorByName(e.value),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    e.value,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              )
                            : Text(
                                e.value,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const Divider(height: 32),
            const Text(
              'Description',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              listing.description.isNotEmpty
                  ? listing.description
                  : 'No description provided.',
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 16),
            const _SafetyTips(),
            const SizedBox(height: 24),
            if (!isOwnAd) ...[
              if (!listing.isSold && isBuyable(listing)) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPakGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () => showBuyNowSheet(context, listing),
                    icon: const Icon(Icons.shopping_cart_checkout),
                    label: const Text(
                      'Buy Now',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => showOfferSheet(context, listing),
                    icon: const Icon(Icons.local_offer_outlined),
                    label: const Text('Make an Offer'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: callSeller,
                      icon: const Icon(Icons.phone),
                      label: const Text('Call'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: openWhatsApp,
                      icon: const Icon(Icons.chat),
                      label: const Text('WhatsApp'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: openChat,
                  icon: const Icon(Icons.message),
                  label: const Text('Chat with Seller'),
                ),
              ),
            ] else
              const Center(
                child: Text(
                  'This is your ad',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            _SimilarAds(listing: listing),
            const SizedBox(height: 24),
              ],
            ),
          ),
        ),
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
        final high = prices[(prices.length * 0.85).floor().clamp(
          0,
          prices.length - 1,
        )];
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
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
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

        final items = snapshot.data!.docs
            .map((d) => Listing.fromDoc(d))
            .where((l) =>
                l.id != listing.id &&
                l.isApproved &&
                !l.isSold &&
                !isHiddenSeller(l.userId))
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
        Icon(icon, size: 16, color: Colors.grey[700]),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text, style: TextStyle(color: Colors.grey[800])),
        ),
      ],
    );
  }
}

class _SafetyTips extends StatelessWidget {
  const _SafetyTips();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.amber.shade50,
      child: ExpansionTile(
        leading: const Icon(Icons.shield_outlined, color: Colors.amber),
        title: const Text('Safety tips'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '• Meet in a public place during the day.\n'
              '• Inspect the item before you pay.\n'
              '• Never send money or a deposit in advance.\n'
              '• Avoid sharing personal/banking details.\n'
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
