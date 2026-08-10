part of '../main.dart';

// ---------------------------------------------------------------------------
// Admin Panel -> Categories
//
// The whole marketplace catalog, editable at runtime. It lives in ONE Firestore
// doc (config/categories, an ordered `items` array) rather than a collection,
// because it is small, always read in full, and an array makes reordering a
// single atomic write instead of a fan-out of order fields that can drift.
//
// Every save writes the full array. That is deliberate: it keeps ordering
// authoritative and means a partial failure can never leave half a catalog.
//
// Safety rules that shape this screen:
//   - Listings store their category as a plain STRING. Renaming a category
//     therefore orphans its listings unless they are migrated too, so a rename
//     offers to rewrite them and says exactly how many are affected.
//   - Deleting a category with listings is blocked; Hide is offered instead,
//     which retires it from every picker while existing ads keep working.
//   - The catalog can never be saved empty; loadCategories() falls back to the
//     built-in defaults, and this screen refuses to write an empty list.
// ---------------------------------------------------------------------------

/// Counts listings in a category (or a specific subcategory). Used to warn
/// before a rename and to block a destructive delete.
Future<int> _countListingsIn(String category, {String? subcategory}) async {
  Query<Map<String, dynamic>> q = FirebaseFirestore.instance
      .collection('listings')
      .where('category', isEqualTo: category);
  if (subcategory != null) {
    q = q.where('subcategory', isEqualTo: subcategory);
  }
  final agg = await q.count().get();
  return agg.count ?? 0;
}

class _AdminCategoriesTab extends StatefulWidget {
  const _AdminCategoriesTab();

  @override
  State<_AdminCategoriesTab> createState() => _AdminCategoriesTabState();
}

class _AdminCategoriesTabState extends State<_AdminCategoriesTab> {
  bool _saving = false;

  /// Working copy. Edits apply here first and are written as a whole array, so
  /// the list on screen is always what a save would produce.
  late List<MarketplaceCategory> _items = List.of(appCategories);

  void _resync() => setState(() => _items = List.of(appCategories));

  Future<bool> _save(List<MarketplaceCategory> next, String what) async {
    if (next.isEmpty) {
      _toast('A marketplace needs at least one category.');
      return false;
    }
    setState(() => _saving = true);
    try {
      await categoriesDoc.set({
        'items': next.map((c) => c.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.email ?? '',
      }, SetOptions(merge: true));
      // Apply locally too rather than waiting for the snapshot to echo back, so
      // the list never appears to ignore the edit on a slow connection.
      appCategories = next;
      categoriesVersion.value++;
      if (!mounted) return true;
      setState(() {
        _items = List.of(next);
        _saving = false;
      });
      _toast(what);
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _saving = false);
      _toast('Could not save. $e');
      return false;
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---- category actions -------------------------------------------------

  Future<void> _addCategory() async {
    final result = await showDialog<_CategoryDraft>(
      context: context,
      builder: (_) => const _CategoryEditorDialog(),
    );
    if (result == null) return;
    if (_items.any((c) => c.title.toLowerCase() == result.title.toLowerCase())) {
      _toast('A category called "${result.title}" already exists.');
      return;
    }
    await _save([
      ..._items,
      MarketplaceCategory(
        title: result.title,
        icon: result.icon,
        subcategories: const [],
        advertiseOnly: result.advertiseOnly,
      ),
    ], 'Added "${result.title}".');
  }

  Future<void> _editCategory(int index) async {
    final current = _items[index];
    final result = await showDialog<_CategoryDraft>(
      context: context,
      builder: (_) => _CategoryEditorDialog(existing: current),
    );
    if (result == null) return;

    final renamed = result.title != current.title;
    if (renamed &&
        _items.any(
          (c) =>
              c != current &&
              c.title.toLowerCase() == result.title.toLowerCase(),
        )) {
      _toast('A category called "${result.title}" already exists.');
      return;
    }

    // A rename breaks the link to every listing filed under the old name,
    // because listings store the category as a string. Say how many, and offer
    // to bring them along.
    var migrate = false;
    if (renamed) {
      final count = await _countListingsIn(current.title);
      if (!mounted) return;
      if (count > 0) {
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Move existing ads?'),
            content: Text(
              '$count ${count == 1 ? 'ad is' : 'ads are'} filed under '
              '"${current.title}".\n\n'
              'Renaming to "${result.title}" without moving them leaves those '
              'ads pointing at a category that no longer exists. They stay '
              'live but stop showing up under either name.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'leave'),
                child: const Text('Rename only'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, 'move'),
                child: Text('Rename & move $count'),
              ),
            ],
          ),
        );
        if (choice == null || choice == 'cancel') return;
        migrate = choice == 'move';
      }
    }

    final next = List.of(_items);
    next[index] = current.copyWith(
      title: result.title,
      icon: result.icon,
      advertiseOnly: result.advertiseOnly,
    );
    final ok = await _save(next, 'Updated "${result.title}".');
    if (ok && migrate) {
      await _migrateListings(current.title, result.title);
    }
  }

  /// Rewrites `category` on every listing filed under [from]. Batched at 400
  /// (Firestore's limit is 500 writes) and paged, so a large category cannot
  /// blow the batch limit.
  Future<void> _migrateListings(String from, String to) async {
    setState(() => _saving = true);
    var moved = 0;
    try {
      final fs = FirebaseFirestore.instance;
      while (true) {
        final page = await fs
            .collection('listings')
            .where('category', isEqualTo: from)
            .limit(400)
            .get();
        if (page.docs.isEmpty) break;
        final batch = fs.batch();
        for (final d in page.docs) {
          batch.update(d.reference, {'category': to});
        }
        await batch.commit();
        moved += page.docs.length;
        if (page.docs.length < 400) break;
      }
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Moved $moved ${moved == 1 ? 'ad' : 'ads'} to "$to".');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      // The rename already saved; only the migration failed. Say so precisely
      // rather than implying the whole edit was lost.
      _toast(
        'Renamed, but only $moved ads moved before this failed: $e. '
        'Re-run by renaming again.',
      );
    }
  }

  Future<void> _deleteCategory(int index) async {
    final c = _items[index];
    setState(() => _saving = true);
    final count = await _countListingsIn(c.title);
    if (!mounted) return;
    setState(() => _saving = false);

    if (count > 0) {
      // Deleting would strand real ads. Offer the reversible option instead.
      final hide = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('"${c.title}" still has ads'),
          content: Text(
            '$count ${count == 1 ? 'ad is' : 'ads are'} filed under this '
            'category, so deleting it would strand them.\n\n'
            'Hiding it instead removes it from every picker and the home strip '
            'while those ads keep working. You can unhide it at any time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hide instead'),
            ),
          ],
        ),
      );
      if (hide == true) await _toggleHidden(index);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${c.title}"?'),
        content: const Text(
          'No ads use this category, so nothing will be stranded. This cannot '
          'be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final next = List.of(_items)..removeAt(index);
    await _save(next, 'Deleted "${c.title}".');
  }

  Future<void> _toggleHidden(int index) async {
    final c = _items[index];
    final next = List.of(_items);
    next[index] = c.copyWith(hidden: !c.hidden);
    await _save(
      next,
      c.hidden ? '"${c.title}" is visible again.' : '"${c.title}" hidden.',
    );
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final next = List.of(_items);
    next.insert(newIndex, next.removeAt(oldIndex));
    await _save(next, 'Order updated.');
  }

  Future<void> _restoreDefaults() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore the built-in catalog?'),
        content: const Text(
          'Replaces the whole category list with the one the app ships with. '
          'Ads are not touched, but any category you added will disappear from '
          'the pickers and its ads will be stranded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _save(defaultCatalog(), 'Built-in catalog restored.');
  }

  // ---- subcategory actions ----------------------------------------------

  Future<void> _addSub(int catIndex) async {
    final c = _items[catIndex];
    final result = await showDialog<_SubDraft>(
      context: context,
      builder: (_) => const _SubEditorDialog(),
    );
    if (result == null) return;
    if (c.subcategories.any(
      (s) => s.toLowerCase() == result.name.toLowerCase(),
    )) {
      _toast('"${result.name}" is already in ${c.title}.');
      return;
    }
    final next = List.of(_items);
    next[catIndex] = c.copyWith(
      subcategories: [...c.subcategories, result.name],
      advertiseOnlySubs: result.advertiseOnly
          ? {...c.advertiseOnlySubs, result.name}
          : c.advertiseOnlySubs,
    );
    await _save(next, 'Added "${result.name}".');
  }

  Future<void> _editSub(int catIndex, int subIndex) async {
    final c = _items[catIndex];
    final old = c.subcategories[subIndex];
    final result = await showDialog<_SubDraft>(
      context: context,
      builder: (_) => _SubEditorDialog(
        existing: old,
        advertiseOnly: c.advertiseOnlySubs.contains(old),
      ),
    );
    if (result == null) return;

    var migrate = false;
    if (result.name != old) {
      final count = await _countListingsIn(c.title, subcategory: old);
      if (!mounted) return;
      if (count > 0) {
        final choice = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Move existing ads?'),
            content: Text(
              '$count ${count == 1 ? 'ad uses' : 'ads use'} the subcategory '
              '"$old". Renaming without moving them leaves those ads pointing '
              'at a subcategory that no longer exists.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Rename only'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Rename & move $count'),
              ),
            ],
          ),
        );
        if (choice == null) return;
        migrate = choice;
      }
    }

    final subs = List.of(c.subcategories);
    subs[subIndex] = result.name;
    final flags = Set.of(c.advertiseOnlySubs)..remove(old);
    if (result.advertiseOnly) flags.add(result.name);

    final next = List.of(_items);
    next[catIndex] = c.copyWith(subcategories: subs, advertiseOnlySubs: flags);
    final ok = await _save(next, 'Updated "${result.name}".');
    if (ok && migrate) {
      await _migrateSubcategory(c.title, old, result.name);
    }
  }

  Future<void> _migrateSubcategory(String cat, String from, String to) async {
    setState(() => _saving = true);
    var moved = 0;
    try {
      final fs = FirebaseFirestore.instance;
      while (true) {
        final page = await fs
            .collection('listings')
            .where('category', isEqualTo: cat)
            .where('subcategory', isEqualTo: from)
            .limit(400)
            .get();
        if (page.docs.isEmpty) break;
        final batch = fs.batch();
        for (final d in page.docs) {
          batch.update(d.reference, {'subcategory': to});
        }
        await batch.commit();
        moved += page.docs.length;
        if (page.docs.length < 400) break;
      }
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Moved $moved ${moved == 1 ? 'ad' : 'ads'} to "$to".');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Renamed, but only $moved ads moved before this failed: $e');
    }
  }

  Future<void> _deleteSub(int catIndex, int subIndex) async {
    final c = _items[catIndex];
    final name = c.subcategories[subIndex];
    setState(() => _saving = true);
    final count = await _countListingsIn(c.title, subcategory: name);
    if (!mounted) return;
    setState(() => _saving = false);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove "$name"?'),
        content: Text(
          count == 0
              ? 'No ads use this subcategory.'
              : '$count ${count == 1 ? 'ad uses' : 'ads use'} it. They stay '
                    'live under ${c.title} but their subcategory will no '
                    'longer match anything, so they drop out of subcategory '
                    'filters.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: count == 0 ? null : Colors.red,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final subs = List.of(c.subcategories)..removeAt(subIndex);
    final next = List.of(_items);
    next[catIndex] = c.copyWith(
      subcategories: subs,
      advertiseOnlySubs: Set.of(c.advertiseOnlySubs)..remove(name),
    );
    await _save(next, 'Removed "$name".');
  }

  Future<void> _toggleSubAdvertiseOnly(int catIndex, String name) async {
    final c = _items[catIndex];
    final flags = Set.of(c.advertiseOnlySubs);
    final on = !flags.contains(name);
    if (on) {
      flags.add(name);
    } else {
      flags.remove(name);
    }
    final next = List.of(_items);
    next[catIndex] = c.copyWith(advertiseOnlySubs: flags);
    await _save(
      next,
      on ? '"$name" is now contact-only.' : '"$name" is buyable again.',
    );
  }

  // ---- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ReorderableListView.builder(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.lg,
            AppSpacing.page,
            AppSpacing.navClearance + 72,
          ),
          header: _CategoriesHeader(
            count: _items.length,
            onRestore: _saving ? null : _restoreDefaults,
            onRefresh: _saving ? null : _resync,
          ),
          itemCount: _items.length,
          onReorderItem: _saving ? (_, _) {} : _reorder,
          itemBuilder: (context, i) {
            final c = _items[i];
            return _CategoryCard(
              key: ValueKey('${c.title}-$i'),
              category: c,
              index: i,
              busy: _saving,
              onEdit: () => _editCategory(i),
              onDelete: () => _deleteCategory(i),
              onToggleHidden: () => _toggleHidden(i),
              onAddSub: () => _addSub(i),
              onEditSub: (s) => _editSub(i, s),
              onDeleteSub: (s) => _deleteSub(i, s),
              onToggleSubAdvertise: (name) => _toggleSubAdvertiseOnly(i, name),
            );
          },
        ),
        if (_saving)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 3),
          ),
        Positioned(
          right: 16,
          bottom: 16 + AppSpacing.navClearance / 2,
          child: FloatingActionButton.extended(
            onPressed: _saving ? null : _addCategory,
            icon: const Icon(Icons.add),
            label: const Text('Category'),
          ),
        ),
      ],
    );
  }
}

class _CategoriesHeader extends StatelessWidget {
  final int count;
  final VoidCallback? onRestore;
  final VoidCallback? onRefresh;
  const _CategoriesHeader({
    required this.count,
    this.onRestore,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfacePanel(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.category, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$count categories',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Reload from server',
                  icon: const Icon(Icons.refresh),
                  onPressed: onRefresh,
                ),
                IconButton(
                  tooltip: 'Restore built-in catalog',
                  icon: const Icon(Icons.settings_backup_restore),
                  onPressed: onRestore,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Drag to reorder. This is the order buyers see on the home strip '
              'and in every category picker. Changes reach open apps live.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final MarketplaceCategory category;
  final int index;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleHidden;
  final VoidCallback onAddSub;
  final void Function(int) onEditSub;
  final void Function(int) onDeleteSub;
  final void Function(String) onToggleSubAdvertise;

  const _CategoryCard({
    super.key,
    required this.category,
    required this.index,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleHidden,
    required this.onAddSub,
    required this.onEditSub,
    required this.onDeleteSub,
    required this.onToggleSubAdvertise,
  });

  @override
  Widget build(BuildContext context) {
    final c = category;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: c.hidden ? 0.55 : 1,
        child: ExpansionTile(
          leading: ReorderableDragStartListener(
            index: index,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.drag_indicator, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Icon(c.icon, color: kPakGreen),
              ],
            ),
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  c.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (c.hidden) ...[
                const SizedBox(width: 6),
                const _CatPill(text: 'Hidden', color: Colors.blueGrey),
              ],
              if (c.advertiseOnly) ...[
                const SizedBox(width: 6),
                const _CatPill(text: 'Contact only', color: Colors.deepOrange),
              ],
            ],
          ),
          subtitle: Text(
            c.subcategories.isEmpty
                ? 'No subcategories'
                : '${c.subcategories.length} subcategories',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
          trailing: PopupMenuButton<String>(
            enabled: !busy,
            onSelected: (v) {
              switch (v) {
                case 'edit':
                  onEdit();
                case 'hide':
                  onToggleHidden();
                case 'delete':
                  onDelete();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(
                value: 'hide',
                child: Text(c.hidden ? 'Unhide' : 'Hide'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            for (var s = 0; s < c.subcategories.length; s++)
              _SubRow(
                name: c.subcategories[s],
                advertiseOnly: c.advertiseOnlySubs.contains(c.subcategories[s]),
                busy: busy,
                onEdit: () => onEditSub(s),
                onDelete: () => onDeleteSub(s),
                onToggleAdvertise: () =>
                    onToggleSubAdvertise(c.subcategories[s]),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: busy ? null : onAddSub,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add subcategory'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubRow extends StatelessWidget {
  final String name;
  final bool advertiseOnly;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleAdvertise;

  const _SubRow({
    required this.name,
    required this.advertiseOnly,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleAdvertise,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            Icons.subdirectory_arrow_right,
            size: 15,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
          if (advertiseOnly)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: _CatPill(text: 'Contact only', color: Colors.deepOrange),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: advertiseOnly ? 'Allow Buy Now' : 'Make contact-only',
            icon: Icon(
              advertiseOnly
                  ? Icons.shopping_cart_outlined
                  : Icons.call_outlined,
              size: 17,
            ),
            onPressed: busy ? null : onToggleAdvertise,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Rename',
            icon: const Icon(Icons.edit_outlined, size: 17),
            onPressed: busy ? null : onEdit,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Remove',
            icon: const Icon(Icons.close, size: 17, color: Colors.red),
            onPressed: busy ? null : onDelete,
          ),
        ],
      ),
    );
  }
}

class _CatPill extends StatelessWidget {
  final String text;
  final Color color;
  const _CatPill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ---- dialogs -------------------------------------------------------------

class _CategoryDraft {
  final String title;
  final IconData icon;
  final bool advertiseOnly;
  const _CategoryDraft(this.title, this.icon, this.advertiseOnly);
}

class _CategoryEditorDialog extends StatefulWidget {
  final MarketplaceCategory? existing;
  const _CategoryEditorDialog({this.existing});

  @override
  State<_CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<_CategoryEditorDialog> {
  late final _controller = TextEditingController(
    text: widget.existing?.title ?? '',
  );
  late String _icon = iconNameFor(widget.existing?.icon ?? Icons.category);
  late bool _advertiseOnly = widget.existing?.advertiseOnly ?? false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Edit category' : 'New category'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Home & Furniture',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Icon',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 148,
              width: 320,
              child: GridView.count(
                crossAxisCount: 6,
                children: [
                  for (final e in kCategoryIcons.entries)
                    IconButton(
                      tooltip: e.key,
                      icon: Icon(
                        e.value,
                        color: _icon == e.key ? kPakGreen : null,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: _icon == e.key
                            ? kPakGreen.withValues(alpha: 0.12)
                            : null,
                      ),
                      onPressed: () => setState(() => _icon = e.key),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _advertiseOnly,
              onChanged: (v) => setState(() => _advertiseOnly = v ?? false),
              title: const Text('Contact only', style: TextStyle(fontSize: 14)),
              subtitle: Text(
                'No Buy Now or checkout. Buyers call, WhatsApp or chat the '
                'seller instead. Use for property, jobs and services.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final t = _controller.text.trim();
            if (t.isEmpty) return;
            Navigator.pop(
              context,
              _CategoryDraft(
                t,
                kCategoryIcons[_icon] ?? Icons.category,
                _advertiseOnly,
              ),
            );
          },
          child: Text(editing ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}

class _SubDraft {
  final String name;
  final bool advertiseOnly;
  const _SubDraft(this.name, this.advertiseOnly);
}

class _SubEditorDialog extends StatefulWidget {
  final String? existing;
  final bool advertiseOnly;
  const _SubEditorDialog({this.existing, this.advertiseOnly = false});

  @override
  State<_SubEditorDialog> createState() => _SubEditorDialogState();
}

class _SubEditorDialogState extends State<_SubEditorDialog> {
  late final _controller = TextEditingController(text: widget.existing ?? '');
  late bool _advertiseOnly = widget.advertiseOnly;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'New subcategory' : 'Edit subcategory',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _advertiseOnly,
            onChanged: (v) => setState(() => _advertiseOnly = v ?? false),
            title: const Text('Contact only', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              'Buyable category, but this subcategory is too big or awkward to '
              'ship (e.g. Cars within Motors).',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final t = _controller.text.trim();
            if (t.isEmpty) return;
            Navigator.pop(context, _SubDraft(t, _advertiseOnly));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
