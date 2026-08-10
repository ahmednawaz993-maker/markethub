import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

// The catalog is now admin-authored data that round-trips through Firestore.
// These guard the two ways that can go wrong silently: an icon that does not
// survive serialisation (so a category renders as a generic box after any edit),
// and a bad stored payload blanking the marketplace.

void main() {
  test('every built-in category icon survives a save/reload round trip', () {
    for (final c in defaultCatalog()) {
      final restored = MarketplaceCategory.fromMap(c.toMap());
      expect(
        restored.icon.codePoint,
        c.icon.codePoint,
        reason:
            '"${c.title}" uses an icon missing from kCategoryIcons, so editing '
            'it in the admin panel would silently downgrade it to a generic '
            'icon. Add it to the registry.',
      );
    }
  });

  test('a category round-trips all of its fields', () {
    const original = MarketplaceCategory(
      title: 'Motors',
      icon: Icons.directions_car,
      subcategories: ['Cars', 'Auto Parts'],
      advertiseOnly: false,
      advertiseOnlySubs: {'Cars'},
      hidden: true,
      attributes: ['Year', 'KM driven'],
      colorValue: 0xFF1E88E5,
    );
    final r = MarketplaceCategory.fromMap(original.toMap());
    expect(r.title, 'Motors');
    expect(r.icon.codePoint, Icons.directions_car.codePoint);
    expect(r.subcategories, ['Cars', 'Auto Parts']);
    expect(r.advertiseOnlySubs, {'Cars'});
    expect(r.hidden, isTrue);
    expect(r.advertiseOnly, isFalse);
    expect(r.attributes, ['Year', 'KM driven']);
    expect(r.colorValue, 0xFF1E88E5);
    expect(r.color, const Color(0xFF1E88E5));
  });

  test('a category with no colour round-trips as auto', () {
    const original = MarketplaceCategory(
      title: 'Plain',
      icon: Icons.category,
      subcategories: [],
    );
    final r = MarketplaceCategory.fromMap(original.toMap());
    expect(r.colorValue, isNull);
    expect(r.color, isNull);
    expect(r.attributes, isEmpty);
  });

  test('copyWith can clear a colour back to auto', () {
    const c = MarketplaceCategory(
      title: 'X',
      icon: Icons.category,
      subcategories: [],
      colorValue: 0xFF123456,
    );
    // A bare null cannot mean "reset" - that is what clearColor is for.
    expect(c.copyWith().colorValue, 0xFF123456);
    expect(c.copyWith(colorValue: null).colorValue, 0xFF123456);
    expect(c.copyWith(clearColor: true).colorValue, isNull);
  });

  test('advertise-only defaults are folded onto the built-in catalog', () {
    final cat = defaultCatalog();
    final props = cat.firstWhere((c) => c.title == 'Properties');
    expect(props.advertiseOnly, isTrue);
    final motors = cat.firstWhere((c) => c.title == 'Motors');
    expect(motors.advertiseOnly, isFalse);
    expect(motors.advertiseOnlySubs, contains('Cars'));
  });

  test('attribute and colour defaults are folded onto the catalog', () {
    final cat = defaultCatalog();
    final motors = cat.firstWhere((c) => c.title == 'Motors');
    expect(motors.attributes, contains('KM driven'));
    expect(motors.colorValue, 0xFF1E88E5);
    // A category with no curated spec fields stays empty rather than inheriting.
    final community = cat.firstWhere((c) => c.title == 'Community');
    expect(community.attributes, isEmpty);
  });

  group('attributeFieldsFor reads the live catalog', () {
    setUp(() => appCategories = defaultCatalog());

    test('returns the built-in fields before any admin edit', () {
      expect(attributeFieldsFor('Motors'), contains('Year'));
    });

    test('follows an admin edit', () {
      applyStoredCategories({
        'items': [
          {
            'title': 'Motors',
            'icon': 'directions_car',
            'attributes': ['Engine size', 'Fuel'],
          },
        ],
      });
      expect(attributeFieldsFor('Motors'), ['Engine size', 'Fuel']);
    });

    test('an admin emptying the fields is respected, not re-defaulted', () {
      applyStoredCategories({
        'items': [
          {
            'title': 'Motors',
            'icon': 'directions_car',
            'attributes': <String>[],
          },
        ],
      });
      expect(attributeFieldsFor('Motors'), isEmpty);
    });

    test('an unknown category still falls back to the built-ins', () {
      applyStoredCategories({
        'items': [
          {'title': 'Something Else', 'icon': 'category'},
        ],
      });
      expect(attributeFieldsFor('Properties'), contains('Bedrooms'));
    });
  });

  group('categoryAccent', () {
    setUp(() => appCategories = defaultCatalog());

    test('uses the category colour when set', () {
      expect(categoryAccent('Motors', 0), const Color(0xFF1E88E5));
    });

    test('falls back to a stable palette slot when unset', () {
      applyStoredCategories({
        'items': [
          {'title': 'Nameless', 'icon': 'category'},
        ],
      });
      expect(categoryAccent('Nameless', 0), kCategoryPalette[0]);
      expect(categoryAccent('Nameless', 1), kCategoryPalette[1]);
      // Wraps rather than throwing once the index exceeds the palette.
      expect(
        categoryAccent('Nameless', kCategoryPalette.length),
        kCategoryPalette[0],
      );
    });

    test('follows an admin colour change', () {
      applyStoredCategories({
        'items': [
          {'title': 'Motors', 'icon': 'directions_car', 'colorValue': 0xFFAA0000},
        ],
      });
      expect(categoryAccent('Motors', 0), const Color(0xFFAA0000));
    });
  });

  group('applyStoredCategories refuses to blank the marketplace', () {
    setUp(() => appCategories = defaultCatalog());

    test('null / missing payload is rejected', () {
      expect(applyStoredCategories(null), isFalse);
      expect(applyStoredCategories({}), isFalse);
      expect(appCategories, isNotEmpty);
    });

    test('an empty list is rejected', () {
      expect(applyStoredCategories({'items': []}), isFalse);
      expect(appCategories, isNotEmpty);
    });

    test('a list of unusable entries is rejected', () {
      final ok = applyStoredCategories({
        'items': [
          'not a map',
          {'title': ''},
        ],
      });
      expect(ok, isFalse);
      expect(appCategories, isNotEmpty);
    });

    test('a valid payload replaces the catalog and skips junk entries', () {
      final ok = applyStoredCategories({
        'items': [
          {
            'title': 'Spices',
            'icon': 'grain',
            'subcategories': ['Whole', 'Ground'],
            'advertiseOnly': false,
            'advertiseOnlySubs': <String>[],
            'hidden': false,
          },
          {'title': ''}, // dropped, not fatal
        ],
      });
      expect(ok, isTrue);
      expect(appCategories.length, 1);
      expect(appCategories.first.title, 'Spices');
      expect(appCategories.first.icon.codePoint, Icons.grain.codePoint);
    });

    test('an unknown icon name degrades instead of throwing', () {
      final ok = applyStoredCategories({
        'items': [
          {'title': 'Mystery', 'icon': 'no_such_icon'},
        ],
      });
      expect(ok, isTrue);
      expect(appCategories.first.icon.codePoint, Icons.category.codePoint);
      expect(appCategories.first.subcategories, isEmpty);
    });
  });

  group('derived views follow the live catalog', () {
    setUp(() => appCategories = defaultCatalog());

    test('advertiseOnly sets are derived, not frozen', () {
      expect(advertiseOnlyCategories, contains('Properties'));
      applyStoredCategories({
        'items': [
          {
            'title': 'Books',
            'icon': 'menu_book',
            'subcategories': ['Rare'],
            'advertiseOnly': true,
            'advertiseOnlySubs': ['Rare'],
          },
        ],
      });
      expect(advertiseOnlyCategories, {'Books'});
      expect(advertiseOnlySubcategories, {'Rare'});
    });

    test('hidden categories leave the pickers but stay resolvable', () {
      applyStoredCategories({
        'items': [
          {'title': 'Live', 'icon': 'storefront'},
          {'title': 'Retired', 'icon': 'storefront', 'hidden': true},
        ],
      });
      expect(visibleCategories.map((c) => c.title), ['Live']);
      expect(categoryByTitle('Retired').title, 'Retired');
    });
  });

  group('categoryChoices keeps a dropdown value valid', () {
    setUp(() {
      applyStoredCategories({
        'items': [
          {'title': 'All', 'icon': 'apps'},
          {'title': 'Live', 'icon': 'storefront'},
          {'title': 'Retired', 'icon': 'storefront', 'hidden': true},
        ],
      });
    });

    test('drops the synthetic All bucket', () {
      expect(categoryChoices(null).map((c) => c.title), ['Live']);
    });

    test('re-adds a hidden current value so the dropdown cannot assert', () {
      expect(categoryChoices('Retired').map((c) => c.title), [
        'Retired',
        'Live',
      ]);
    });

    test('re-adds a deleted current value too', () {
      final titles = categoryChoices('Deleted Category').map((c) => c.title);
      expect(titles, ['Deleted Category', 'Live']);
    });

    test('does not duplicate a current value that is already visible', () {
      expect(categoryChoices('Live').map((c) => c.title), ['Live']);
    });
  });
}
