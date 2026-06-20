part of '../main.dart';

// Profile, verification, trust & safety, about.

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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Display name saved')),
    );
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
  final ImagePicker picker = ImagePicker();
  String? logoUrl;
  bool uploadingLogo = false;
  String? coverUrl;
  bool uploadingCover = false;

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
      logoUrl = d?['logoUrl']?.toString();
      coverUrl = d?['coverUrl']?.toString();
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
      'logoUrl': logoUrl ?? '',
      'coverUrl': coverUrl ?? '',
    }, SetOptions(merge: true));
    if (!mounted) return;
    setState(() => saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Business profile saved')),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    taglineController.dispose();
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
                      backgroundImage:
                          (logoUrl != null && logoUrl!.isNotEmpty)
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
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: (loaded && !saving) ? _save : null,
                child: Text(saving ? 'Saving…' : 'Save'),
              ),
            ),
            if (isBusiness) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      showBusinessAdSheet(context, nameController.text.trim()),
                  icon: const Icon(Icons.campaign, color: kGold),
                  label: const Text('Advertise my business'),
                ),
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
class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final picker = ImagePicker();
  String? selfieUrl;
  String? cnicUrl;
  bool uploadingSelfie = false;
  bool uploadingCnic = false;
  bool submitting = false;
  bool loaded = false;
  String status = '';
  bool idVerified = false;

  @override
  void initState() {
    super.initState();
    _load();
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
      idVerified = uDoc.data()?['idVerified'] == true;
      loaded = true;
    });
  }

  Future<void> _upload(bool selfie) async {
    // Camera-only (no gallery upload) to prevent fake/stolen photos. Selfie
    // uses the front camera; the CNIC uses the rear camera.
    final img = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: selfie
          ? CameraDevice.front
          : CameraDevice.rear,
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
    setState(() => submitting = true);
    await FirebaseFirestore.instance
        .collection('verifications')
        .doc(user.uid)
        .set({
          'userId': user.uid,
          'email': user.email ?? '',
          'selfieUrl': selfieUrl,
          'cnicUrl': cnicUrl,
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
      appBar: AppBar(title: const Text('Identity Verification')),
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
                      subtitle: Text('Please re-upload clear photos and resubmit.'),
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
              'PakBazar is a safer marketplace when everyone follows a few simple '
              'rules. These protect both buyers and sellers.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          _card(Icons.verified_user, 'For everyone', kPakGreen, const [
            'Meet in public, busy places for in-person handovers.',
            'Keep your chat and deal on PakBazar so there is a record.',
            'Never share OTPs, passwords, or card PINs with anyone.',
            'Check the other person\'s ratings and reviews first.',
          ]),
          _card(Icons.shopping_cart, 'For buyers', Colors.blue, const [
            'Inspect the item and confirm it matches the ad before you pay.',
            'Be cautious of prices that look too good to be true.',
            'Avoid paying the full amount in advance to unknown sellers — '
                'prefer cash on inspection or delivery.',
            'Use "Make an Offer" to negotiate openly and on the record.',
          ]),
          _card(Icons.sell, 'For sellers', Colors.deepOrange, const [
            'Describe items honestly and use your own real photos.',
            'Confirm payment is fully received before handing over the item.',
            'Do not ship or release goods before payment clears.',
            'Reply quickly and complete deals smoothly to grow your rating.',
          ]),
          _card(Icons.report_gmailerrorred, 'Spotted something wrong?', Colors.red, const [
            'Use the Report button on any suspicious ad or user.',
            'Our team reviews reports and removes bad actors.',
            'Block and stop dealing with anyone who pressures or threatens you.',
          ]),
        ],
      ),
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
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => launchUrl(
                    Uri.parse('https://pakbazar24.com/privacy.html'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Terms of Use'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => launchUrl(
                    Uri.parse('https://pakbazar24.com/terms.html'),
                    mode: LaunchMode.externalApplication,
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
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('Contact support'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => launchUrl(
                    Uri.parse('mailto:support@pakbazar.pk?subject=PakBazar'),
                    mode: LaunchMode.externalApplication,
                  ),
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
                  colors: [kPakGreen, Color(0xFF0B6E3D)],
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
            if (isAdminUser()) ...[
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
                label: const Text('Admin Panel'),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OrdersScreen()),
              ),
              icon: const Icon(Icons.receipt_long),
              label: const Text('My Orders'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OffersScreen()),
              ),
              icon: const Icon(Icons.local_offer),
              label: const Text('Offers'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WalletScreen()),
              ),
              icon: const Icon(Icons.account_balance_wallet),
              label: const Text('PakBazar Wallet'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VerificationScreen()),
              ),
              icon: const Icon(Icons.verified_user),
              label: const Text('Verify Identity'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DraftsScreen()),
              ),
              icon: const Icon(Icons.edit_note),
              label: const Text('Drafts'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SavedSearchesScreen()),
              ),
              icon: const Icon(Icons.bookmark),
              label: const Text('Saved Searches'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FollowingScreen()),
              ),
              icon: const Icon(Icons.people_alt),
              label: const Text('Following'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final url = Uri.parse(
                  'mailto:support@pakbazar.pk?subject=PakBazar Feedback',
                );
                await launchUrl(url, mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.help_outline),
              label: const Text('Help & Feedback'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              ),
              icon: const Icon(Icons.info_outline),
              label: const Text('About PakBazar'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () async {
                favoriteListings.clear();
                await FirebaseAuth.instance.signOut();
                // AuthGate listens to authStateChanges and shows the login screen.
              },
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Make an offer (price negotiation)
// ---------------------------------------------------------------------------
