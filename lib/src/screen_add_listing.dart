part of '../main.dart';

// Create a listing and draft management.

class DraftsScreen extends StatelessWidget {
  const DraftsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Drafts')),
        body: const EmptyState(icon: Icons.edit_note, title: 'Please log in'),
      );
    }
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('drafts');
    return Scaffold(
      appBar: AppBar(title: const Text('Drafts')),
      body: StreamBuilder<QuerySnapshot>(
        stream: col.orderBy('savedAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const EmptyState(
              icon: Icons.error_outline,
              title: 'Couldn’t load drafts',
              subtitle: 'Please try again.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const EmptyState(
              icon: Icons.edit_note,
              title: 'No drafts',
              subtitle: 'Save an unfinished ad to resume it later.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              final title = d['title']?.toString() ?? '';
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.edit_note, color: kPakGreen),
                  title: Text(
                    title.isEmpty ? '(untitled draft)' : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${d['category'] ?? ''} · ${formatPrice(d['price']?.toString() ?? '')}',
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AddListingScreen(draft: d, draftId: docs[i].id),
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => docs[i].reference.delete(),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class AddListingScreen extends StatefulWidget {
  /// Optional saved draft to resume (and its id, so it's deleted once posted).
  final Map<String, dynamic>? draft;
  final String? draftId;
  const AddListingScreen({super.key, this.draft, this.draftId});

  @override
  State<AddListingScreen> createState() => _AddListingScreenState();
}

class _AddListingScreenState extends State<AddListingScreen> {
  List<XFile> selectedImages = [];
  final ImagePicker picker = ImagePicker();

  final titleController = TextEditingController();
  final priceController = TextEditingController();
  final deliveryFeeController = TextEditingController();
  final locationController = TextEditingController();
  final phoneController = TextEditingController();
  final descriptionController = TextEditingController();

  String selectedCategory = 'Motors';
  String selectedSubcategory = 'Cars';
  String selectedCondition = 'Used';
  String selectedUnit = 'None';
  bool deliveryAvailable = false;
  bool codAvailable = false;
  bool negotiable = false;
  final Map<String, TextEditingController> attrControllers = {};

  TextEditingController _attrCtrl(String label) =>
      attrControllers.putIfAbsent(label, () => TextEditingController());
  String selectedCity = 'Karachi';
  double? latitude;
  double? longitude;
  bool isLocating = false;
  bool isSubmitting = false;
  bool savingDraft = false;

  @override
  void initState() {
    super.initState();
    _prefillPhoneFromProfile();
    final d = widget.draft;
    if (d == null) return;
    titleController.text = d['title']?.toString() ?? '';
    priceController.text = d['price']?.toString() ?? '';
    locationController.text = d['location']?.toString() ?? '';
    phoneController.text = d['phone']?.toString() ?? '';
    descriptionController.text = d['description']?.toString() ?? '';
    final cat = d['category']?.toString() ?? '';
    if (cat.isNotEmpty) selectedCategory = cat;
    final subs = categoryByTitle(selectedCategory).subcategories;
    selectedSubcategory = subs.contains(d['subcategory'])
        ? d['subcategory'].toString()
        : subs.first;
    if (itemConditions.contains(d['condition'])) {
      selectedCondition = d['condition'].toString();
    }
    final u = d['unit']?.toString() ?? '';
    selectedUnit = pricingUnits.contains(u) ? u : 'None';
    deliveryAvailable = d['deliveryAvailable'] == true;
    deliveryFeeController.text = d['deliveryFee']?.toString() ?? '';
    codAvailable = d['codAvailable'] == true;
    negotiable = d['negotiable'] == true;
    // Preselect the saved place even if it's a custom town/village not in the
    // curated list.
    final savedCity = d['city']?.toString() ?? '';
    if (savedCity.isNotEmpty) selectedCity = savedCity;
    final attrs = (d['attributes'] as Map?) ?? {};
    attrs.forEach((k, v) => _attrCtrl(k.toString()).text = v.toString());
  }

  /// Pre-fills the contact number from the seller's saved profile phone, unless
  /// the field already has a value (e.g. restored from a draft).
  Future<void> _prefillPhoneFromProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final phone = doc.data()?['phone']?.toString() ?? '';
      if (phone.isNotEmpty && phoneController.text.trim().isEmpty && mounted) {
        setState(() => phoneController.text = phone);
      }
    } catch (_) {}
  }

  Future<void> saveDraft() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => savingDraft = true);
    final attributes = <String, String>{};
    for (final label in attributeFieldsFor(selectedCategory)) {
      final v = attrControllers[label]?.text.trim() ?? '';
      if (v.isNotEmpty) attributes[label] = v;
    }
    final data = {
      'title': titleController.text.trim(),
      'price': priceController.text.trim(),
      'location': locationController.text.trim(),
      'phone': phoneController.text.trim(),
      'description': descriptionController.text.trim(),
      'category': selectedCategory,
      'subcategory': selectedSubcategory,
      'condition': selectedCondition,
      'unit': selectedUnit,
      'deliveryFee': deliveryFeeController.text.trim(),
      'deliveryAvailable': deliveryAvailable,
      'codAvailable': codAvailable,
      'negotiable': negotiable,
      'city': selectedCity,
      'attributes': attributes,
      'savedAt': Timestamp.now(),
    };
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('drafts');
    if (widget.draftId != null) {
      await col.doc(widget.draftId).set(data);
    } else {
      await col.add(data);
    }
    if (!mounted) return;
    setState(() => savingDraft = false);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Saved to Drafts (Profile → Drafts)')),
    );
  }

  List<String> get currentSubcategories {
    return categoryByTitle(selectedCategory).subcategories;
  }

  Future<void> useCurrentLocation() async {
    setState(() => isLocating = true);
    try {
      final position = await determineCurrentPosition();
      if (!mounted) return;
      setState(() {
        latitude = position.latitude;
        longitude = position.longitude;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Current location added to your ad')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => isLocating = false);
    }
  }

  Future<void> pickImages() async {
    final images = await picker.pickMultiImage();

    if (images.isNotEmpty) {
      setState(() {
        selectedImages = images;
      });
    }
  }

  Future<List<String>> uploadImages() async {
    final urls = <String>[];

    for (var i = 0; i < selectedImages.length; i++) {
      final bytes = await selectedImages[i].readAsBytes();

      final ref = FirebaseStorage.instance
          .ref()
          .child('listings')
          .child('${DateTime.now().millisecondsSinceEpoch}_$i.jpg');

      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      urls.add(await ref.getDownloadURL());
    }

    return urls;
  }

  Future<void> submitListing() async {
    // Guard against a double-tap re-entering during the async gaps below
    // (ensureVerified and the Firestore/Storage writes all await). The flag is
    // set *synchronously* before the first await so a second tap arriving during
    // ensureVerified sees isSubmitting == true and bails — otherwise the same ad
    // could be posted twice. The finally below always clears it.
    if (isSubmitting) return;
    setState(() {
      isSubmitting = true;
    });

    try {
      if (!await ensureVerified(context)) return;
      if (!mounted) return;
      if (titleController.text.trim().isEmpty ||
          priceController.text.trim().isEmpty ||
          locationController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please fill title, price, and location'),
          ),
        );
        return;
      }
      if (parsePrice(priceController.text.trim()) <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid price')),
        );
        return;
      }
      // A contact number is required so buyers can reach the seller.
      if (normalizePhoneForWhatsApp(phoneController.text.trim()).length < 11) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid phone number')),
        );
        return;
      }

      final imageUrls = await uploadImages();

      final attributes = <String, String>{};
      for (final label in attributeFieldsFor(selectedCategory)) {
        final v = attrControllers[label]?.text.trim() ?? '';
        if (v.isNotEmpty) attributes[label] = v;
      }

      // Privacy-friendly seller name: display name > business name > email
      // local-part > generic. Never expose the full email address.
      final me = FirebaseAuth.instance.currentUser;
      String sellerName = 'Seller';
      if (me != null) {
        final udoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(me.uid)
            .get();
        final d = udoc.data();
        final dn = (d?['displayName'] as String?)?.trim() ?? '';
        final bn = (d?['businessName'] as String?)?.trim() ?? '';
        if (dn.isNotEmpty) {
          sellerName = dn;
        } else if (d?['isBusiness'] == true && bn.isNotEmpty) {
          sellerName = bn;
        } else if (me.email != null && me.email!.contains('@')) {
          sellerName = me.email!.split('@').first;
        }
      }

      await FirebaseFirestore.instance.collection('listings').add({
        'title': titleController.text.trim(),
        'price': priceController.text.trim(),
        'location': locationController.text.trim(),
        'city': selectedCity,
        'latitude': latitude,
        'longitude': longitude,
        'phone': phoneController.text.trim(),
        'description': descriptionController.text.trim(),
        'imageUrl': imageUrls.isNotEmpty ? imageUrls.first : '',
        'images': imageUrls,
        'category': selectedCategory,
        'subcategory': selectedSubcategory,
        'condition': selectedCondition,
        'unit': selectedUnit == 'None' ? '' : selectedUnit,
        'deliveryFee': deliveryAvailable
            ? deliveryFeeController.text.trim()
            : '',
        'deliveryAvailable': deliveryAvailable,
        'codAvailable': codAvailable,
        'negotiable': negotiable,
        'sellerVerified': true,
        'attributes': attributes,
        'userId': FirebaseAuth.instance.currentUser?.uid ?? '',
        'sellerName': sellerName,
        'createdAt': Timestamp.now(),
        'views': 0,
        'isFeatured': false,
        // New listings start in stock; the seller controls this afterwards.
        'status': 'in_stock',
        'isSold': false,
        // New ads are hidden until an admin approves them (admin Approvals tab).
        // Demo/review accounts auto-approve so reviewers see ads go live.
        'approvalStatus': isDemoUser() ? 'approved' : 'pending',
      });

      // The ad is now live. Everything below is best-effort cleanup — a failure
      // here must NOT be treated as a post failure (that would show an error and
      // tempt the user to re-submit, creating a duplicate live ad).

      // Mirror the seller's location onto their profile (for the admin panel).
      try {
        await saveUserLocation(
          city: selectedCity,
          lat: latitude,
          lng: longitude,
        );
      } catch (_) {}

      // If this was resumed from a draft, remove the draft.
      if (widget.draftId != null) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .collection('drafts')
                .doc(widget.draftId)
                .delete();
          } catch (_) {}
        }
      }

      if (!mounted) return;
      // A published listing is a meaningful engagement signal for the review
      // prompt (never triggers the prompt here — only records the signal).
      recordMeaningfulAction();
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(
            isDemoUser() ? Icons.check_circle : Icons.hourglass_top,
            color: kPakGreen,
            size: 52,
          ),
          title: Text(
            isDemoUser() ? 'Your ad is live!' : 'Ad submitted for review',
          ),
          content: Text(
            isDemoUser()
                ? 'Your ad has been posted to PakBazar. Boost it to Featured '
                      'from My Ads to reach more buyers.'
                : 'Thanks! Your ad has been submitted and will go live once an '
                      'admin approves it. You can track its status in My Ads.',
            textAlign: TextAlign.center,
          ),
          actions: [
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couldn’t post your ad. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSubmitting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    priceController.dispose();
    deliveryFeeController.dispose();
    locationController.dispose();
    phoneController.dispose();
    descriptionController.dispose();
    for (final c in attrControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subcategories = currentSubcategories;

    return Scaffold(
      appBar: AppBar(title: const Text('Post Ad')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: isSubmitting ? null : pickImages,
                  icon: const Icon(Icons.add_a_photo),
                  label: Text(
                    selectedImages.isEmpty
                        ? 'Add Photos'
                        : '${selectedImages.length} photo(s) selected',
                  ),
                ),
                if (selectedImages.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 90,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: selectedImages.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: FutureBuilder<Uint8List>(
                            future: selectedImages[index].readAsBytes(),
                            builder: (context, snap) {
                              if (!snap.hasData) {
                                return Container(
                                  width: 90,
                                  height: 90,
                                  color: Colors.grey.shade300,
                                  child: const Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return Image.memory(
                                snap.data!,
                                width: 90,
                                height: 90,
                                fit: BoxFit.cover,
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextField(
                  controller: priceController,
                  decoration: const InputDecoration(labelText: 'Price (PKR)'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: locationController,
                  decoration: const InputDecoration(
                    labelText: 'Area / Block',
                    hintText: 'Example: Gulshan-e-Iqbal, Block 5',
                  ),
                ),
                const SizedBox(height: 12),
                CitySelector(
                  value: selectedCity,
                  label: 'City / Town / Village',
                  allowCustom: true,
                  enabled: !isSubmitting,
                  onChanged: (value) => setState(() => selectedCity = value),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: (isSubmitting || isLocating)
                      ? null
                      : useCurrentLocation,
                  icon: isLocating
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          latitude != null
                              ? Icons.location_on
                              : Icons.my_location,
                          color: latitude != null ? Colors.green : null,
                        ),
                  label: Text(
                    latitude != null
                        ? 'Current location added ✓'
                        : 'Use my current location',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedCondition,
                  decoration: const InputDecoration(labelText: 'Condition'),
                  items: itemConditions
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: isSubmitting
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => selectedCondition = value);
                          }
                        },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedUnit,
                  decoration: const InputDecoration(
                    labelText: 'Price unit (optional, e.g. per kg/dozen/plate)',
                  ),
                  items: pricingUnits
                      .map(
                        (u) => DropdownMenuItem(
                          value: u,
                          child: Text(u == 'None' ? 'None' : 'per $u'),
                        ),
                      )
                      .toList(),
                  onChanged: isSubmitting
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => selectedUnit = value);
                          }
                        },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Delivery available'),
                  subtitle: const Text('Show a delivery badge on your ad'),
                  value: deliveryAvailable,
                  activeThumbColor: kPakGreen,
                  onChanged: isSubmitting
                      ? null
                      : (v) => setState(() => deliveryAvailable = v),
                ),
                if (deliveryAvailable)
                  TextField(
                    controller: deliveryFeeController,
                    enabled: !isSubmitting,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Delivery fee (PKR, optional)',
                      hintText: 'Leave blank for free delivery',
                      prefixIcon: Icon(Icons.local_shipping),
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cash on Delivery'),
                  subtitle: const Text(
                    'Let buyers pay cash when the item arrives',
                  ),
                  value: codAvailable,
                  activeThumbColor: kPakGreen,
                  onChanged: isSubmitting
                      ? null
                      : (v) => setState(() => codAvailable = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Price negotiable'),
                  subtitle: const Text('Buyers can make an offer'),
                  value: negotiable,
                  activeThumbColor: kPakGreen,
                  onChanged: isSubmitting
                      ? null
                      : (v) => setState(() => negotiable = v),
                ),
                for (final label in attributeFieldsFor(selectedCategory))
                  if (label == 'Color')
                    ColorSwatchSelector(
                      selected: _attrCtrl('Color').text,
                      onChanged: isSubmitting
                          ? (_) {}
                          : (v) => setState(() => _attrCtrl('Color').text = v),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextField(
                        controller: _attrCtrl(label),
                        enabled: !isSubmitting,
                        decoration: InputDecoration(
                          labelText: '$label (optional)',
                        ),
                      ),
                    ),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp / Phone Number *',
                    hintText: 'Example: 03001234567 or +92 300 1234567',
                  ),
                  keyboardType: TextInputType.phone,
                ),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 3,
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  decoration: const InputDecoration(labelText: 'Main Category'),
                  items: appCategories
                      .where((category) => category.title != 'All')
                      .map(
                        (category) => DropdownMenuItem(
                          value: category.title,
                          child: Text(category.title),
                        ),
                      )
                      .toList(),
                  onChanged: isSubmitting
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              selectedCategory = value;
                              selectedSubcategory = categoryByTitle(
                                value,
                              ).subcategories.first;
                            });
                          }
                        },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: subcategories.contains(selectedSubcategory)
                      ? selectedSubcategory
                      : subcategories.first,
                  decoration: const InputDecoration(labelText: 'Subcategory'),
                  items: subcategories
                      .map(
                        (subcategory) => DropdownMenuItem(
                          value: subcategory,
                          child: Text(subcategory),
                        ),
                      )
                      .toList(),
                  onChanged: isSubmitting
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              selectedSubcategory = value;
                            });
                          }
                        },
                ),
                const SizedBox(height: 20),
                // Seller conduct notice — every seller sees this before posting, so
                // the zero-tolerance policy isn't buried only in the Terms.
                InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TermsScreen()),
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Icon(Icons.gavel, color: Colors.red, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Sell honestly. ',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                TextSpan(
                                  text:
                                      'Any fraud or violent activity will get '
                                      'your seller account suspended immediately. '
                                      'Tap to read the seller terms.',
                                ),
                              ],
                            ),
                            style: TextStyle(fontSize: 12.5, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: isSubmitting ? null : submitListing,
                  child: isSubmitting
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: (isSubmitting || savingDraft) ? null : saveDraft,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(savingDraft ? 'Saving…' : 'Save Draft'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// My ads + edit
// ---------------------------------------------------------------------------

/// Seller dashboard: totals across the user's ads + top performers.
