part of '../main.dart';

// Profile, verification, trust & safety, about.

/// Help & Suggestions: lets any user send a support request or an idea. The
/// message is saved to the `feedback` collection (the admin reviews it in
/// Admin Panel → Feedback) and also opens the user's mail app pre-addressed to
/// [supportEmail], so it reaches the admin inbox directly too.
Future<void> showSupportSheet(BuildContext context) async {
  final controller = TextEditingController();
  String type = 'Help';
  final messenger = ScaffoldMessenger.of(context);
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Help & Suggestions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Need help or have an idea to improve PakBazar? Send it to our '
                  'team — we read every message.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Need help'),
                      selected: type == 'Help',
                      onSelected: (_) => setSheetState(() => type = 'Help'),
                    ),
                    ChoiceChip(
                      label: const Text('Suggestion'),
                      selected: type == 'Suggestion',
                      onSelected: (_) =>
                          setSheetState(() => type = 'Suggestion'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  minLines: 3,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Your message',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () async {
                    final msg = controller.text.trim();
                    if (msg.isEmpty) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Please type your message first'),
                        ),
                      );
                      return;
                    }
                    final user = FirebaseAuth.instance.currentUser;
                    // Durable record for the admin (Admin Panel → Feedback).
                    try {
                      await FirebaseFirestore.instance
                          .collection('feedback')
                          .add({
                            'userId': user?.uid ?? '',
                            'email': user?.email ?? '',
                            'type': type,
                            'message': msg,
                            'status': 'open',
                            'createdAt': Timestamp.now(),
                          });
                    } catch (_) {}
                    // Also deliver straight to the admin's email inbox.
                    try {
                      await launchUrl(
                        Uri.parse(
                          'mailto:$supportEmail'
                          '?subject=${Uri.encodeComponent('PakBazar $type')}'
                          '&body=${Uri.encodeComponent(msg)}',
                        ),
                        mode: LaunchMode.externalApplication,
                      );
                    } catch (_) {}
                    if (context.mounted) Navigator.pop(context);
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Thanks! Your message has been sent to our team.',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.send),
                  label: const Text('Send to support'),
                ),
              ],
            ),
          );
        },
      );
    },
  );
  controller.dispose();
}

class _DisplayNameTile extends StatefulWidget {
  const _DisplayNameTile();

  @override
  State<_DisplayNameTile> createState() => _DisplayNameTileState();
}

class _DisplayNameTileState extends State<_DisplayNameTile> {
  final controller = TextEditingController();
  bool loaded = false;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (!mounted) return;
    setState(() {
      controller.text = doc.data()?['displayName']?.toString() ?? '';
      loaded = true;
    });
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => saving = true);
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'displayName': controller.text.trim(),
    }, SetOptions(merge: true));
    if (!mounted) return;
    setState(() => saving = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Display name saved')));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              enabled: loaded,
              decoration: const InputDecoration(
                labelText: 'Display name',
                helperText: 'Shown on your ads instead of your email',
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: (loaded && !saving) ? _save : null,
                child: Text(saving ? 'Saving…' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets a signed-in user mark their account as a business (shows a BUSINESS
/// badge on their ads) and set a business name.
class _BusinessAccountTile extends StatefulWidget {
  const _BusinessAccountTile();

  @override
  State<_BusinessAccountTile> createState() => _BusinessAccountTileState();
}

class _BusinessAccountTileState extends State<_BusinessAccountTile> {
  bool isBusiness = false;
  bool loaded = false;
  bool saving = false;
  final nameController = TextEditingController();
  final taglineController = TextEditingController();
  final policiesController = TextEditingController();
  final ImagePicker picker = ImagePicker();
  String? logoUrl;
  bool uploadingLogo = false;
  String? coverUrl;
  bool uploadingCover = false;
  String? storeCategory;
  bool featuredBusiness = false;
  Timestamp? featuredUntil;
  bool featuredTrialUsed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _pickCover() async {
    final img = await picker.pickImage(source: ImageSource.gallery);
    if (img == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => uploadingCover = true);
    try {
      final bytes = await img.readAsBytes();
      final ref = FirebaseStorage.instance
          .ref()
          .child('business_logos')
          .child('cover_$uid.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() => coverUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Cover upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => uploadingCover = false);
    }
  }

  Future<void> _pickLogo() async {
    final img = await picker.pickImage(source: ImageSource.gallery);
    if (img == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => uploadingLogo = true);
    try {
      final bytes = await img.readAsBytes();
      final ref = FirebaseStorage.instance
          .ref()
          .child('business_logos')
          .child('$uid.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() => logoUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Logo upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => uploadingLogo = false);
    }
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final d = doc.data();
    if (!mounted) return;
    setState(() {
      isBusiness = d?['isBusiness'] == true;
      nameController.text = d?['businessName']?.toString() ?? '';
      taglineController.text = d?['tagline']?.toString() ?? '';
      policiesController.text = d?['storePolicies']?.toString() ?? '';
      logoUrl = d?['logoUrl']?.toString();
      coverUrl = d?['coverUrl']?.toString();
      final sc = d?['storeCategory']?.toString();
      storeCategory = (sc != null && sc.isNotEmpty) ? sc : null;
      featuredBusiness = d?['featuredBusiness'] == true;
      featuredUntil = d?['featuredBusinessUntil'] is Timestamp
          ? d!['featuredBusinessUntil'] as Timestamp
          : null;
      featuredTrialUsed = d?['featuredTrialUsed'] == true;
      loaded = true;
    });
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => saving = true);
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'isBusiness': isBusiness,
      'businessName': nameController.text.trim(),
      'tagline': taglineController.text.trim(),
      'storePolicies': policiesController.text.trim(),
      'logoUrl': logoUrl ?? '',
      'coverUrl': coverUrl ?? '',
      'storeCategory': storeCategory ?? '',
    }, SetOptions(merge: true));
    if (!mounted) return;
    setState(() => saving = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Business profile saved')));
  }

  /// Activates the free 3-month Featured Business trial (no payment).
  Future<void> _activateFeaturedTrial() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final until = Timestamp.fromDate(
      DateTime.now().add(const Duration(days: 90)),
    );
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'isBusiness': true,
      'featuredBusiness': true,
      'featuredBusinessUntil': until,
      'featuredTrialUsed': true,
    }, SetOptions(merge: true));
    if (!mounted) return;
    setState(() {
      featuredBusiness = true;
      featuredUntil = until;
      featuredTrialUsed = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Featured Business activated — free for 3 months!'),
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    taglineController.dispose();
    policiesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('Sell as a business'),
              subtitle: const Text('Shows a BUSINESS badge on your ads'),
              value: isBusiness,
              activeThumbColor: kPakGreen,
              onChanged: loaded ? (v) => setState(() => isBusiness = v) : null,
            ),
            if (isBusiness) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: kPakGreen.withValues(alpha: 0.12),
                      backgroundImage: (logoUrl != null && logoUrl!.isNotEmpty)
                          ? NetworkImage(logoUrl!)
                          : null,
                      child: (logoUrl == null || logoUrl!.isEmpty)
                          ? const Icon(Icons.storefront, color: kPakGreen)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: uploadingLogo ? null : _pickLogo,
                      icon: uploadingLogo
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload),
                      label: Text(uploadingLogo ? 'Uploading…' : 'Upload logo'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    if (coverUrl != null && coverUrl!.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          coverUrl!,
                          width: 64,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const SizedBox(width: 64, height: 40),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    OutlinedButton.icon(
                      onPressed: uploadingCover ? null : _pickCover,
                      icon: uploadingCover
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.panorama),
                      label: Text(
                        uploadingCover ? 'Uploading…' : 'Cover photo',
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Business name'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: taglineController,
                  decoration: const InputDecoration(
                    labelText: 'Tagline (e.g. "Best deals on phones")',
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: DropdownButtonFormField<String>(
                  initialValue: storeCategory,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Store category'),
                  items: [
                    for (final c
                        in appCategories.where((c) => c.title != 'All'))
                      DropdownMenuItem(value: c.title, child: Text(c.title)),
                  ],
                  onChanged: (v) => setState(() => storeCategory = v),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: policiesController,
                  minLines: 3,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Store rules / policies',
                    alignLabelWithHint: true,
                    helperText:
                        'Your returns, delivery & payment rules. They must '
                        'comply with PakBazar\'s platform rules.',
                    helperMaxLines: 2,
                  ),
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: (loaded && !saving) ? _save : null,
                child: Text(saving ? 'Saving…' : 'Save'),
              ),
            ),
            if (isBusiness) ...[
              Builder(
                builder: (context) {
                  final active =
                      featuredBusiness &&
                      featuredUntil != null &&
                      featuredUntil!.toDate().isAfter(DateTime.now());
                  return Card(
                    color: kGold.withValues(alpha: 0.10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.star, color: kGold),
                              const SizedBox(width: 8),
                              const Text(
                                'Featured Business',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: kPakGreen,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'FREE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (active)
                            Text(
                              'Active — featured on the home screen until '
                              '${featuredUntil!.toDate().day}/'
                              '${featuredUntil!.toDate().month}/'
                              '${featuredUntil!.toDate().year}.',
                              style: const TextStyle(fontSize: 13),
                            )
                          else if (featuredTrialUsed)
                            const Text(
                              'Your free 3-month trial has ended.',
                              style: TextStyle(fontSize: 13, color: Colors.grey),
                            )
                          else ...[
                            const Text(
                              'Get a Featured Business spot on the home screen '
                              '— free for 3 months.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: loaded
                                    ? _activateFeaturedTrial
                                    : null,
                                icon: const Icon(Icons.star),
                                label: const Text('Activate free 3-month trial'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BannerAdScreen()),
                  ),
                  icon: const Icon(Icons.view_carousel, color: kGold),
                  label: const Text('Buy a home banner'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Identity verification: user uploads a selfie + CNIC for admin face-match
/// review. On approval the admin sets `idVerified` on the user doc.
/// Lets a user request deletion of their account and data. The request is
/// queued for the admin (Admin Panel → Deletions) to action — satisfies the
/// app stores' account-deletion requirement.
Future<void> _requestAccountDeletion(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  final reasonCtrl = TextEditingController();
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.delete_forever, color: Colors.red, size: 40),
      title: const Text('Delete my account'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'This requests permanent deletion of your PakBazar account and data '
            '(profile, ads, and related records). Our team will process it. '
            'This cannot be undone.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: reasonCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Reason (optional)',
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
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Request deletion'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await FirebaseFirestore.instance
        .collection('deletionRequests')
        .doc(user.uid)
        .set({
          'userId': user.uid,
          'email': user.email ?? '',
          'reason': reasonCtrl.text.trim(),
          'status': 'pending',
          'createdAt': Timestamp.now(),
        });
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Account deletion requested. Our team will process it shortly.',
        ),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not submit request: $e')),
    );
  }
}

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final picker = ImagePicker();
  final addressController = TextEditingController();
  String? selfieUrl;
  String? cnicUrl;
  String? addressProofUrl;
  bool uploadingSelfie = false;
  bool uploadingCnic = false;
  bool uploadingProof = false;
  bool submitting = false;
  bool loaded = false;
  String status = '';
  bool idVerified = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    addressController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final fs = FirebaseFirestore.instance;
    final vDoc = await fs.collection('verifications').doc(uid).get();
    final uDoc = await fs.collection('users').doc(uid).get();
    if (!mounted) return;
    setState(() {
      final v = vDoc.data();
      status = v?['status']?.toString() ?? '';
      selfieUrl = v?['selfieUrl']?.toString();
      cnicUrl = v?['cnicUrl']?.toString();
      addressProofUrl = v?['addressProofUrl']?.toString();
      addressController.text =
          v?['address']?.toString() ?? uDoc.data()?['address']?.toString() ?? '';
      idVerified = uDoc.data()?['idVerified'] == true;
      loaded = true;
    });
  }

  /// Address proof (utility bill, bank letter, etc.) — a document, so gallery
  /// upload is allowed here (unlike the live-camera-only selfie/CNIC).
  Future<void> _uploadProof() async {
    final img = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (img == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => uploadingProof = true);
    try {
      final bytes = await img.readAsBytes();
      final ref = FirebaseStorage.instance
          .ref()
          .child('verifications')
          .child(uid)
          .child('address_proof.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() => addressProofUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => uploadingProof = false);
    }
  }

  Future<void> _upload(bool selfie) async {
    // Camera-only (no gallery upload) to prevent fake/stolen photos. Selfie
    // uses the front camera; the CNIC uses the rear camera.
    final img = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: selfie ? CameraDevice.front : CameraDevice.rear,
      imageQuality: 70,
    );
    if (img == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() {
      if (selfie) {
        uploadingSelfie = true;
      } else {
        uploadingCnic = true;
      }
    });
    try {
      final bytes = await img.readAsBytes();
      final ref = FirebaseStorage.instance
          .ref()
          .child('verifications')
          .child(uid)
          .child(selfie ? 'selfie.jpg' : 'cnic.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() {
        if (selfie) {
          selfieUrl = url;
        } else {
          cnicUrl = url;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          uploadingSelfie = false;
          uploadingCnic = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (selfieUrl == null || cnicUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload both a selfie and your CNIC')),
      );
      return;
    }
    if (addressController.text.trim().length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your full address')),
      );
      return;
    }
    setState(() => submitting = true);
    await FirebaseFirestore.instance
        .collection('verifications')
        .doc(user.uid)
        .set({
          'userId': user.uid,
          'email': user.email ?? '',
          'selfieUrl': selfieUrl,
          'cnicUrl': cnicUrl,
          'address': addressController.text.trim(),
          'addressProofUrl': addressProofUrl,
          'status': 'pending',
          'submittedAt': Timestamp.now(),
        }, SetOptions(merge: true));
    if (!mounted) return;
    setState(() {
      submitting = false;
      status = 'pending';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Submitted — we\'ll review it shortly.')),
    );
  }

  Widget _uploadTile(String label, String? url, bool busy, VoidCallback onTap) {
    return Card(
      child: ListTile(
        leading: SizedBox(
          width: 52,
          height: 52,
          child: url == null
              ? const Icon(Icons.camera_alt, color: kPakGreen)
              : ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(url, fit: BoxFit.cover),
                ),
        ),
        title: Text(label),
        subtitle: Text(url == null ? 'Not captured' : 'Captured ✓'),
        trailing: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: onTap,
                child: Text(url == null ? 'Capture' : 'Retake'),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Identity & Address Verification')),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (idVerified)
                  Card(
                    color: kPakGreen.withValues(alpha: 0.1),
                    child: const ListTile(
                      leading: Icon(Icons.verified_user, color: kPakGreen),
                      title: Text('Your identity is verified'),
                      subtitle: Text('You have the ID-Verified badge.'),
                    ),
                  )
                else if (status == 'pending')
                  const Card(
                    color: Color(0xFFFFF8E1),
                    child: ListTile(
                      leading: Icon(Icons.hourglass_top, color: Colors.orange),
                      title: Text('Under review'),
                      subtitle: Text('We\'re checking your documents.'),
                    ),
                  )
                else if (status == 'rejected')
                  const Card(
                    color: Color(0xFFFFEBEE),
                    child: ListTile(
                      leading: Icon(Icons.cancel, color: Colors.red),
                      title: Text('Verification rejected'),
                      subtitle: Text(
                        'Please re-upload clear photos and resubmit.',
                      ),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 8, 4, 8),
                  child: Text(
                    'Verify your identity to earn an ID-Verified badge that buyers '
                    'and sellers trust. Use your camera to take a live selfie and a '
                    'photo of your CNIC — uploads from the gallery are not allowed. '
                    'Our team checks that the face matches the ID.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                _uploadTile(
                  'Your selfie',
                  selfieUrl,
                  uploadingSelfie,
                  () => _upload(true),
                ),
                _uploadTile(
                  'CNIC (front)',
                  cnicUrl,
                  uploadingCnic,
                  () => _upload(false),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 4, 4, 6),
                  child: Text(
                    'Your residential address',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextField(
                  controller: addressController,
                  enabled: !idVerified,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Full address',
                    hintText: 'House/Street, Area, City',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.home_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                _uploadTile(
                  'Proof of address (bill/letter) — optional',
                  addressProofUrl,
                  uploadingProof,
                  _uploadProof,
                ),
                const SizedBox(height: 12),
                if (!idVerified)
                  ElevatedButton(
                    onPressed: submitting ? null : _submit,
                    child: Text(
                      submitting
                          ? 'Submitting…'
                          : (status == 'pending'
                                ? 'Resubmit for review'
                                : 'Submit for verification'),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Your documents are private — visible only to you and our '
                    'review team, never shown publicly. See the Privacy Policy.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Safe-trading rules that protect both buyers and sellers.
class TrustSafetyScreen extends StatelessWidget {
  const TrustSafetyScreen({super.key});

  Widget _card(IconData icon, String title, Color color, List<String> points) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...points.map(
              (p) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(p)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trust & Safety')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Text(
              'These are the rules every PakBazar member agrees to. Buyers and '
              'sellers each have matching responsibilities at every step of a '
              'deal — follow them to keep the marketplace safe and fair.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          _card(Icons.verified_user, 'For everyone', kPakGreen, const [
            'Be honest and respectful — no harassment, threats, hate speech, '
                'or discrimination.',
            'Keep every chat, offer, and payment on PakBazar so there is a '
                'record — never move a deal off the app.',
            'Never share OTPs, passwords, CNIC numbers, or card PINs with '
                'anyone, for any reason.',
            'Verify your identity and address to build trust and unlock '
                'posting, buying, offers, and chat.',
            'Check the other person\'s ratings and reviews before you deal.',
            'Meet in public, busy places for in-person handovers.',
          ]),
          // Buyer and seller duties are deliberately written as matching
          // pairs (honesty, fair price, on-platform payment, prompt handover,
          // fair confirmation/review) so both sides know what to expect.
          _card(Icons.shopping_cart, 'For buyers', Colors.blue, const [
            'Inspect the item and confirm it matches the ad before you pay.',
            'Pay through PakBazar (escrow or Cash on Delivery) — never pay the '
                'full amount in advance to an unknown seller.',
            'Be cautious of prices that look too good to be true.',
            'Negotiate openly with "Make an Offer" — don\'t ask to deal '
                'outside the app.',
            'Confirm receipt honestly so the seller\'s payment is released '
                'fairly.',
            'Leave an honest rating and review after the deal.',
          ]),
          _card(Icons.sell, 'For sellers', Colors.deepOrange, const [
            'Describe items honestly and use your own real photos — no '
                'misleading or fake listings.',
            'Only list items you actually own and are legally allowed to sell.',
            'Honour the price and details you advertised — no bait-and-switch.',
            'Confirm payment is fully received or escrow is funded before you '
                'hand over the item.',
            'Hand over or ship promptly once paid; never release goods before '
                'payment clears.',
            'Reply quickly and resolve issues fairly to grow your rating.',
          ]),
          _card(Icons.block, 'Prohibited items & conduct', Colors.red, const [
            'No weapons, drugs, alcohol, or other illegal or restricted goods.',
            'No counterfeit, replica, stolen, or recalled/unsafe products.',
            'No adult content, and no items banned under Pakistani law.',
            'No fraud, fake listings, advance-fee scams, or requests to pay '
                'outside PakBazar.',
            'No spam, duplicate ads, or misleading prices.',
            'Breaking these rules can lead to ad removal, a warning, or account '
                'suspension — you can appeal a suspension from the app.',
          ]),
          _card(Icons.shield_moon, 'How PakBazar protects you', kPakGreen, const [
            'Identity & address verification before members can post, buy, '
                'make offers, or chat.',
            'Every ad is reviewed and approved by our team before it goes live.',
            'In-app escrow holds the payment until the buyer confirms receipt.',
            'Scam detection warns you about risky messages in chat.',
            'Admin moderation can warn, block, or suspend rule-breakers.',
          ]),
          _card(Icons.support_agent, 'Support, orders & refunds', Colors.indigo,
              const [
                'Order or delivery problems are between the buyer and the '
                    'seller — contact the seller directly through chat or their '
                    'listed phone number.',
                'PakBazar can only help with a refund if you paid through the '
                    'platform\'s on-platform payment options (escrow).',
                'If you paid the seller directly — Cash on Delivery, bank '
                    'transfer, or any off-platform method — settle it with the '
                    'seller. PakBazar cannot refund money it never held.',
                'For a dispute on an escrow-funded order, or to report a scam, '
                    'open a request in Customer Care (24/7) — we aim to resolve '
                    'it within 24 hours.',
                'Always keep your payment on PakBazar so you stay protected.',
              ]),
          _card(
            Icons.report_gmailerrorred,
            'Spotted something wrong?',
            Colors.deepOrange,
            const [
              'Use the Report button on any suspicious ad or user.',
              'Our team reviews reports and removes bad actors.',
              'Block and stop dealing with anyone who pressures or threatens '
                  'you.',
            ],
          ),
        ],
      ),
    );
  }
}

/// Renders a legal document as titled sections. A line starting with "• " is
/// shown as a bullet; everything else as a paragraph.
class _LegalScreen extends StatelessWidget {
  final String title;
  final String updated;
  final List<(String, List<String>)> sections;
  const _LegalScreen({
    required this.title,
    required this.updated,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Last updated: $updated',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),
          for (final (heading, lines) in sections) ...[
            Text(
              heading,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: kPakGreen,
              ),
            ),
            const SizedBox(height: 6),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: line.startsWith('• ')
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  '),
                          Expanded(child: Text(line.substring(2))),
                        ],
                      )
                    : Text(line, style: const TextStyle(height: 1.4)),
              ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          const Text(
            'Questions? Contact us at ahmednawaz993@gmail.com.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalScreen(
      title: 'Privacy Policy',
      updated: '22 June 2026',
      sections: [
        ('Introduction', [
          'PakBazar ("we", "us") operates an online marketplace in Pakistan '
              'that lets people buy and sell goods and services. This policy '
              'explains what information we collect, how we use it, and the '
              'choices you have. By using PakBazar you agree to this policy.',
        ]),
        ('Information we collect', [
          '• Account details: your email and/or phone number, and a password '
              '(handled by Firebase Authentication).',
          '• Profile: display or business name, city, and address.',
          '• Verification: a live selfie, CNIC photo, your address and an '
              'optional proof-of-address document, submitted for ID and address '
              'verification.',
          '• Listings: photos, descriptions, price, category, the contact '
              'number you choose to show, and the item location (city and, if '
              'you allow it, GPS coordinates).',
          '• Location: approximate or precise device location, only if you '
              'grant permission.',
          '• Usage and device data: app interactions, views and leads, '
              'recently viewed items, saved searches, favourites, and push '
              'notification tokens.',
          '• Communications: in-app chat messages, offers, support requests, '
              'and reports you submit.',
          '• Payments: wallet balance, top-up and withdrawal requests, and '
              'escrow transactions. We do not store full card numbers; payments '
              'are handled manually or by a payment provider.',
        ]),
        ('How we use your information', [
          '• To run the marketplace — show listings, enable chat, offers, '
              'orders, and escrow.',
          '• To verify identity and address and to prevent fraud and abuse.',
          '• To moderate content — every ad is reviewed before it goes live.',
          '• To process payments, escrow, wallet top-ups and withdrawals.',
          '• To send you notifications about chats, offers, orders, and '
              'account decisions.',
          '• To provide support and to improve and secure the service.',
          '• To comply with the law and enforce our Terms and rules.',
        ]),
        ('How we share information', [
          '• With other users: your public profile, listings, ratings, and any '
              'contact number you add to an ad are visible to others.',
          '• With service providers that power the app, such as Google '
              'Firebase / Google Cloud (hosting, database, authentication, '
              'notifications) and our payment and email providers.',
          '• For safety and legal reasons: to investigate fraud, enforce our '
              'rules, or comply with a lawful request.',
          '• We do not sell your personal information.',
        ]),
        ('Your verification documents', [
          'Your selfie, CNIC and address proof are kept private. They are '
              'visible only to you and our review team and are never shown '
              'publicly. They are used solely to verify your identity and '
              'address.',
        ]),
        ('Data retention & security', [
          'We keep your information for as long as your account is active or as '
              'needed to provide the service, resolve disputes, and meet legal '
              'obligations. We use industry-standard safeguards, but no method '
              'of transmission or storage is 100% secure.',
        ]),
        ('Your choices', [
          '• You can edit your profile information in the app at any time.',
          '• You can turn location and notification permissions on or off in '
              'your device/browser settings.',
          '• You can delete your account and data with "Delete my account" in '
              'your Profile, or by contacting us at ahmednawaz993@gmail.com.',
        ]),
        ('Children', [
          'PakBazar is intended for users aged 18 and over. We do not '
              'knowingly collect information from children.',
        ]),
        ('Changes to this policy', [
          'We may update this policy from time to time. We will post the '
              'updated version here with a new "Last updated" date.',
        ]),
      ],
    );
  }
}

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalScreen(
      title: 'Terms of Use',
      updated: '22 June 2026',
      sections: [
        ('Acceptance of terms', [
          'By creating an account or using PakBazar, you agree to these Terms '
              'of Use and to our Privacy Policy and Trust & Safety rules. If you '
              'do not agree, please do not use the app.',
        ]),
        ('Eligibility & account', [
          '• You must be at least 18 years old and provide accurate '
              'information.',
          '• Posting ads, buying, making offers and chatting require identity '
              'and address verification.',
          '• You are responsible for keeping your account secure and for all '
              'activity under it.',
        ]),
        ('Our role', [
          'PakBazar is a venue that connects buyers and sellers. Except where '
              'we hold funds in escrow, we are not a party to transactions '
              'between users and are not responsible for the items, their '
              'quality, legality, or delivery. Deals are between the buyer and '
              'the seller.',
        ]),
        ('Listings & moderation', [
          '• You may list only items you own and are legally allowed to sell.',
          '• Listings must be honest, with your own photos and accurate '
              'details and prices.',
          '• Every ad is reviewed before going live; we may approve, reject, '
              'or remove any listing at our discretion.',
          '• Prohibited items and conduct are described in Trust & Safety and '
              'are not allowed.',
        ]),
        ('Buyer & seller responsibilities', [
          'Buyers and sellers must follow the matched responsibilities set out '
              'in our Trust & Safety rules — including honest dealing, keeping '
              'communication and payment on PakBazar, and completing deals '
              'fairly.',
        ]),
        ('Payments, escrow & fees', [
          '• Payments can be made through in-app escrow or Cash on Delivery '
              'where offered.',
          '• With escrow, we hold the payment until the buyer confirms '
              'receipt, then release it to the seller.',
          '• A platform commission may apply to completed sales, and sellers '
              'can request withdrawals of their wallet balance.',
          '• Never make or request payments outside PakBazar.',
        ]),
        ('Prohibited conduct & enforcement', [
          '• No fraud, scams, off-platform payment requests, harassment, or '
              'illegal activity.',
          '• Breaking these Terms or our rules may lead to ad removal, '
              'warnings, or suspension of your account.',
          '• Suspended users may submit an appeal from within the app.',
        ]),
        ('Intellectual property', [
          'PakBazar and its logo, design and content are our property. By '
              'posting content you grant us a licence to host and display it '
              'for the purpose of operating the marketplace.',
        ]),
        ('Disclaimers & liability', [
          'The service is provided "as is" without warranties of any kind. To '
              'the maximum extent permitted by law, PakBazar is not liable for '
              'any indirect or consequential loss, or for disputes, items, or '
              'conduct of users.',
        ]),
        ('Governing law', [
          'These Terms are governed by the laws of the Islamic Republic of '
              'Pakistan.',
        ]),
        ('Changes to these terms', [
          'We may update these Terms from time to time. Continued use after an '
              'update means you accept the revised Terms.',
        ]),
      ],
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: kPakGreen.withValues(alpha: 0.12),
                  child: const Icon(
                    Icons.storefront,
                    color: kPakGreen,
                    size: 44,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'PakBazar',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: kPakGreen,
                  ),
                ),
                const Text(
                  'Pakistan ka apna online bazaar',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Version 1.0.0',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy Policy'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PrivacyPolicyScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Terms of Use'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TermsScreen()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: const Text('Trust & Safety'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const TrustSafetyScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.support_agent, color: kPakGreen),
                  title: const Text('Customer Care (24/7)'),
                  subtitle: const Text('Open a request — resolved within 24h'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CustomerCareScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('Contact support'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showSupportSheet(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: const Text('Share PakBazar'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Clipboard.setData(
                      const ClipboardData(
                        text:
                            'Buy & sell anything on PakBazar: '
                            'https://pakbazar24.com',
                      ),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Link copied — share it anywhere!'),
                        ),
                      );
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text(
                    'Delete my account',
                    style: TextStyle(color: Colors.red),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.red),
                  onTap: () => _requestAccountDeletion(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              '© 2026 PakBazar',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact "X Followers · Y Following" row for the current user's own profile.
class _FollowStatsRow extends StatelessWidget {
  const _FollowStatsRow();

  Widget _stat(String value, String label) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: kPakGreen,
        ),
      ),
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: userRef.collection('followers').snapshots(),
                builder: (context, snap) =>
                    _stat('${snap.data?.docs.length ?? 0}', 'Followers'),
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FollowingScreen()),
                ),
                child: StreamBuilder<QuerySnapshot>(
                  stream: userRef.collection('following').snapshots(),
                  builder: (context, snap) =>
                      _stat('${snap.data?.docs.length ?? 0}', 'Following'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Seller Profile')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [kPakGreen, kPakGreenLight],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const CircleAvatar(
                      radius: 44,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.person, size: 50, color: kPakGreen),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      user?.email ?? 'Guest user',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (!(user?.isAnonymous ?? true)) ...[
                      const SizedBox(height: 10),
                      if (user?.emailVerified ?? false)
                        const Chip(
                          avatar: Icon(
                            Icons.verified,
                            color: kPakGreen,
                            size: 18,
                          ),
                          label: Text('Verified'),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              await user!.sendEmailVerification();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Verification email sent. Verify, then '
                                      'log out and back in to get your badge.',
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Could not send: $e')),
                                );
                              }
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white70),
                          ),
                          icon: const Icon(Icons.mark_email_read),
                          label: const Text('Verify email'),
                        ),
                    ],
                    if (user?.isAnonymous ?? false) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'You are browsing as a guest. Log in to keep your ads, '
                        'favorites and chats across devices.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.amberAccent),
                      ),
                    ],
                  ],
                ),
              ),
              if (!(user?.isAnonymous ?? true)) ...[
                const SizedBox(height: 16),
                const _FollowStatsRow(),
                const SizedBox(height: 12),
                const _DisplayNameTile(),
                const SizedBox(height: 12),
                const _BusinessAccountTile(),
              ],
              if (canOpenAdminPanel()) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminPanelScreen()),
                  ),
                  icon: const Icon(Icons.admin_panel_settings),
                  label: Text(
                    isSuperAdmin() ? tr('profile.adminPanel') : 'Staff Panel',
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const LanguageTile(),
              const SizedBox(height: 12),
              // White outline/text so these options are clearly visible on the
              // dark navy background.
              OutlinedButtonTheme(
                data: OutlinedButtonThemeData(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white60, width: 1.4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const OrdersScreen()),
                      ),
                      icon: const Icon(Icons.receipt_long),
                      label: Text(tr('profile.orders')),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SalesDashboardScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.insights),
                      label: const Text('Sales & Earnings'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const OffersScreen()),
                      ),
                      icon: const Icon(Icons.local_offer),
                      label: Text(tr('profile.offers')),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const WalletScreen()),
                      ),
                      icon: const Icon(Icons.account_balance_wallet),
                      label: Text(tr('profile.wallet')),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const VerificationScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.verified_user),
                      label: Text(tr('profile.verify')),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const DraftsScreen()),
                      ),
                      icon: const Icon(Icons.edit_note),
                      label: Text(tr('profile.drafts')),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SavedSearchesScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.bookmark),
                      label: Text(tr('profile.savedSearches')),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FollowingScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.people_alt),
                      label: Text(tr('profile.following')),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => showSupportSheet(context),
                      icon: const Icon(Icons.help_outline),
                      label: Text(tr('profile.help')),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AboutScreen()),
                      ),
                      icon: const Icon(Icons.info_outline),
                      label: Text(tr('profile.about')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () async {
                  favoriteListings.clear();
                  await FirebaseAuth.instance.signOut();
                  // AuthGate listens to authStateChanges and shows the login screen.
                },
                icon: const Icon(Icons.logout),
                label: Text(tr('profile.logout')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Make an offer (price negotiation)
// ---------------------------------------------------------------------------
