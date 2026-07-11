part of '../main.dart';

// Saved delivery addresses: manage (from Profile) or select (from Checkout).

/// Lists the buyer's saved addresses. In [selectMode] tapping an address pops
/// with it (used by checkout); otherwise tapping edits it.
class AddressBookScreen extends StatelessWidget {
  final bool selectMode;
  const AddressBookScreen({super.key, this.selectMode = false});

  Future<void> _add(BuildContext context) async {
    final saved = await Navigator.push<DeliveryAddress>(
      context,
      MaterialPageRoute(builder: (_) => const AddressFormScreen()),
    );
    // In select mode, adding an address immediately picks it for checkout.
    if (selectMode && saved != null && context.mounted) {
      Navigator.pop(context, saved);
    }
  }

  Future<void> _edit(BuildContext context, DeliveryAddress a) async {
    final saved = await Navigator.push<DeliveryAddress>(
      context,
      MaterialPageRoute(builder: (_) => AddressFormScreen(existing: a)),
    );
    if (selectMode && saved != null && context.mounted) {
      Navigator.pop(context, saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(selectMode ? 'Select address' : 'Delivery addresses'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('Add address'),
      ),
      body: StreamBuilder<List<DeliveryAddress>>(
        stream: addressStream(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data!;
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.location_off,
              title: 'No saved addresses',
              subtitle: 'Add a delivery address to check out faster.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final a = list[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  onTap: selectMode
                      ? () => Navigator.pop(context, a)
                      : () => _edit(context, a),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: kPakGreen.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                a.label,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: kPakGreen,
                                ),
                              ),
                            ),
                            if (a.isDefault) ...[
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.check_circle,
                                size: 14,
                                color: kPakGreen,
                              ),
                              const SizedBox(width: 2),
                              const Text(
                                'Default',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: kPakGreen,
                                ),
                              ),
                            ],
                            const Spacer(),
                            PopupMenuButton<String>(
                              onSelected: (v) async {
                                switch (v) {
                                  case 'edit':
                                    await _edit(context, a);
                                  case 'default':
                                    await setDefaultAddress(a.id);
                                  case 'delete':
                                    await _confirmDelete(context, a);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit'),
                                ),
                                if (!a.isDefault)
                                  const PopupMenuItem(
                                    value: 'default',
                                    child: Text('Set as default'),
                                  ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          a.fullName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          a.phone,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 2),
                        Text(a.shortSummary),
                        if (selectMode) ...[
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => Navigator.pop(context, a),
                              child: const Text('Deliver here'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, DeliveryAddress a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete address?'),
        content: Text('Remove "${a.label}" from your saved addresses?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await deleteAddress(a);
  }
}

/// Add / edit an address. Pops with the saved [DeliveryAddress] on success.
class AddressFormScreen extends StatefulWidget {
  final DeliveryAddress? existing;
  const AddressFormScreen({super.key, this.existing});

  @override
  State<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends State<AddressFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullName;
  late final TextEditingController _phone;
  late final TextEditingController _city;
  late final TextEditingController _area;
  late final TextEditingController _street;
  late final TextEditingController _house;
  late final TextEditingController _landmark;
  late final TextEditingController _postal;
  late final TextEditingController _instructions;

  String _label = 'Home';
  String? _province;
  bool _isDefault = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _fullName = TextEditingController(text: e?.fullName ?? '');
    // Show the saved E.164 phone back in a friendly local format for editing.
    _phone = TextEditingController(text: e?.phone ?? '');
    _city = TextEditingController(text: e?.city ?? '');
    _area = TextEditingController(text: e?.area ?? '');
    _street = TextEditingController(text: e?.streetAddress ?? '');
    _house = TextEditingController(text: e?.houseOrBuilding ?? '');
    _landmark = TextEditingController(text: e?.landmark ?? '');
    _postal = TextEditingController(text: e?.postalCode ?? '');
    _instructions = TextEditingController(text: e?.deliveryInstructions ?? '');
    _label = (e?.label.trim().isNotEmpty ?? false) ? e!.label : 'Home';
    if (e != null && pakProvinces.contains(e.province)) _province = e.province;
    _isDefault = e?.isDefault ?? false;
  }

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _city.dispose();
    _area.dispose();
    _street.dispose();
    _house.dispose();
    _landmark.dispose();
    _postal.dispose();
    _instructions.dispose();
    super.dispose();
  }

  String? _required(String? v, String field) =>
      (v == null || v.trim().isEmpty) ? 'Please enter $field' : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final a = DeliveryAddress(
      id: widget.existing?.id ?? '',
      label: addressLabels.contains(_label) ? _label : 'Home',
      fullName: _fullName.text,
      phone: _phone.text,
      province: _province ?? '',
      city: _city.text,
      area: _area.text,
      streetAddress: _street.text,
      houseOrBuilding: _house.text,
      landmark: _landmark.text,
      postalCode: _postal.text,
      deliveryInstructions: _instructions.text,
      isDefault: _isDefault,
    );
    try {
      String id = a.id;
      if (a.id.isEmpty) {
        id = await saveNewAddress(a);
      } else {
        await updateExistingAddress(a);
      }
      if (!mounted) return;
      // Return the saved address (with normalized phone) so a caller in select
      // mode can use it directly.
      final saved = a.copy()..phone = normalizePakMobile(a.phone);
      Navigator.pop(
        context,
        DeliveryAddress(
          id: id,
          label: saved.label,
          fullName: saved.fullName.trim(),
          phone: saved.phone,
          province: saved.province.trim(),
          city: saved.city.trim(),
          area: saved.area.trim(),
          streetAddress: saved.streetAddress.trim(),
          houseOrBuilding: saved.houseOrBuilding.trim(),
          landmark: saved.landmark.trim(),
          postalCode: saved.postalCode.trim(),
          deliveryInstructions: saved.deliveryInstructions.trim(),
          isDefault: saved.isDefault,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save the address. Please try again.'),
        ),
      );
    }
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    border: const OutlineInputBorder(),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Add address' : 'Edit address'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final l in addressLabels)
                  ChoiceChip(
                    label: Text(l),
                    selected: _label == l,
                    selectedColor: kPakGreen.withValues(alpha: 0.18),
                    onSelected: _saving
                        ? null
                        : (_) => setState(() => _label = l),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fullName,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: _dec('Full name'),
              validator: (v) => _required(v, 'the full name'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              enabled: !_saving,
              keyboardType: TextInputType.phone,
              decoration: _dec('Mobile number', hint: '03XX XXXXXXX'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Please enter a mobile number';
                }
                if (!isValidPakMobile(v)) {
                  return 'Enter a valid Pakistani mobile (03XXXXXXXXX)';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _province,
              isExpanded: true,
              decoration: _dec('Province'),
              items: [
                for (final p in pakProvinces)
                  DropdownMenuItem(value: p, child: Text(p)),
              ],
              onChanged: _saving ? null : (v) => setState(() => _province = v),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Please select a province' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _city,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: _dec('City'),
              validator: (v) => _required(v, 'the city'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _area,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: _dec('Area / locality'),
              validator: (v) => _required(v, 'the area'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _street,
              enabled: !_saving,
              decoration: _dec('Complete street address'),
              validator: (v) => _required(v, 'the street address'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _house,
              enabled: !_saving,
              decoration: _dec('House / flat / shop / building no.'),
              validator: (v) => _required(v, 'the house/building number'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _landmark,
              enabled: !_saving,
              decoration: _dec('Nearby landmark (optional)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _postal,
              enabled: !_saving,
              keyboardType: TextInputType.number,
              decoration: _dec('Postal code (optional)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _instructions,
              enabled: !_saving,
              maxLines: 2,
              decoration: _dec('Delivery instructions (optional)'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Set as default address'),
              value: _isDefault,
              activeThumbColor: kPakGreen,
              onChanged: _saving ? null : (v) => setState(() => _isDefault = v),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save address'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
