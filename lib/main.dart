import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (FirebaseAuth.instance.currentUser == null) {
    await FirebaseAuth.instance.signInAnonymously();
  }

  runApp(const MarketHubApp());
}

class MarketplaceCategory {
  final String title;
  final IconData icon;
  final List<String> subcategories;

  const MarketplaceCategory({
    required this.title,
    required this.icon,
    required this.subcategories,
  });
}

const List<MarketplaceCategory> appCategories = [
  MarketplaceCategory(title: 'All', icon: Icons.apps, subcategories: ['All']),
  MarketplaceCategory(
    title: 'Motors',
    icon: Icons.directions_car,
    subcategories: [
      'Cars',
      'Motorcycles',
      'Auto Parts',
      'Boats',
      'Heavy Vehicles',
      'Number Plates',
      'Car Accessories',
      'Car Rental',
    ],
  ),
  MarketplaceCategory(
    title: 'Properties',
    icon: Icons.home,
    subcategories: [
      'Apartments for Rent',
      'Apartments for Sale',
      'Villas for Rent',
      'Villas for Sale',
      'Rooms for Rent',
      'Commercial Property',
      'Holiday Homes',
      'Land',
      'Property Services',
    ],
  ),
  MarketplaceCategory(
    title: 'Mobiles & Tablets',
    icon: Icons.phone_android,
    subcategories: [
      'Mobile Phones',
      'Tablets',
      'Smart Watches',
      'Mobile Accessories',
      'SIM Cards',
      'Repair Services',
    ],
  ),
  MarketplaceCategory(
    title: 'Electronics',
    icon: Icons.devices,
    subcategories: [
      'Computers & Laptops',
      'TV & Audio',
      'Cameras',
      'Gaming',
      'Home Appliances',
      'Kitchen Appliances',
      'Computer Accessories',
      'Security Cameras',
    ],
  ),
  MarketplaceCategory(
    title: 'Home & Furniture',
    icon: Icons.chair,
    subcategories: [
      'Furniture',
      'Home Decor',
      'Garden & Outdoor',
      'Kitchenware',
      'Lighting',
      'Beds & Mattresses',
      'Tools',
      'Moving & Storage',
    ],
  ),
  MarketplaceCategory(
    title: 'Men Essentials',
    icon: Icons.man,
    subcategories: [
      'Men Clothing',
      'Men Shoes',
      'Watches',
      'Wallets & Bags',
      'Grooming',
      'Perfumes',
      'Sportswear',
      'Sunglasses',
    ],
  ),
  MarketplaceCategory(
    title: 'Women Essentials',
    icon: Icons.woman,
    subcategories: [
      'Women Clothing',
      'Women Shoes',
      'Bags',
      'Jewellery',
      'Beauty & Makeup',
      'Perfumes',
      'Watches',
      'Accessories',
    ],
  ),
  MarketplaceCategory(
    title: 'Kids Essentials',
    icon: Icons.child_care,
    subcategories: [
      'Kids Clothing',
      'Kids Shoes',
      'Toys',
      'Baby Gear',
      'Strollers',
      'School Items',
      'Kids Furniture',
      'Maternity',
    ],
  ),
  MarketplaceCategory(
    title: 'Jobs',
    icon: Icons.work,
    subcategories: [
      'Accounting',
      'Admin',
      'Customer Service',
      'Drivers',
      'Engineering',
      'Hospitality',
      'IT',
      'Marketing',
      'Sales',
      'Real Estate',
      'Construction',
      'Domestic Staff',
    ],
  ),
  MarketplaceCategory(
    title: 'Services',
    icon: Icons.handyman,
    subcategories: [
      'Cleaning',
      'Maintenance',
      'Moving',
      'Car Services',
      'Beauty Services',
      'Tutoring',
      'Photography',
      'Events',
      'Legal Services',
      'Business Services',
      'Home Repair',
      'AC Repair',
      'Plumbing',
      'Electrical',
    ],
  ),
  MarketplaceCategory(
    title: 'Pets',
    icon: Icons.pets,
    subcategories: [
      'Cats',
      'Dogs',
      'Birds',
      'Fish',
      'Pet Food',
      'Pet Accessories',
      'Pet Services',
      'Adoption',
    ],
  ),
  MarketplaceCategory(
    title: 'Sports & Hobbies',
    icon: Icons.sports_soccer,
    subcategories: [
      'Gym Equipment',
      'Bicycles',
      'Sports Gear',
      'Musical Instruments',
      'Books',
      'Collectibles',
      'Camping',
      'Tickets',
    ],
  ),
  MarketplaceCategory(
    title: 'Business & Industrial',
    icon: Icons.business_center,
    subcategories: [
      'Office Furniture',
      'Restaurant Equipment',
      'Industrial Equipment',
      'Medical Equipment',
      'Retail Equipment',
      'Wholesale',
      'Machinery',
    ],
  ),
  MarketplaceCategory(
    title: 'Community',
    icon: Icons.groups,
    subcategories: [
      'Classes',
      'Activities',
      'Lost & Found',
      'Volunteers',
      'Announcements',
      'Free Stuff',
    ],
  ),
];

MarketplaceCategory categoryByTitle(String title) {
  return appCategories.firstWhere(
    (category) => category.title == title,
    orElse: () => appCategories.first,
  );
}

class Listing {
  String id;
  String title;
  String price;
  String location;
  String imageUrl;
  String category;
  String subcategory;
  String phone;
  String description;
  String userId;

  Listing({
    required this.id,
    required this.title,
    required this.price,
    required this.location,
    required this.imageUrl,
    required this.category,
    this.subcategory = '',
    this.phone = '',
    this.description = '',
    this.userId = '',
  });
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'price': price,
      'location': location,
      'imageUrl': imageUrl,
      'category': category,
      'subcategory': subcategory,
      'phone': phone,
      'description': description,
      'userId': userId,
    };
  }

  factory Listing.fromDoc(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return Listing(
      id: doc.id,
      title: data['title']?.toString() ?? '',
      price: data['price']?.toString() ?? '',
      location: data['location']?.toString() ?? '',
      imageUrl: data['imageUrl']?.toString() ?? '',
      category: data['category']?.toString() ?? '',
      subcategory: data['subcategory']?.toString() ?? '',
      phone: data['phone']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      userId: data['userId']?.toString() ?? '',
    );
  }
}

final List<Listing> favoriteListings = [];

class MarketHubApp extends StatelessWidget {
  const MarketHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MarketHub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: false),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedIndex = 0;
  String searchQuery = '';

  Widget homeContent() {
    final filteredCategories = appCategories.where((category) {
      return category.title.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search categories...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              setState(() {
                searchQuery = value;
              });
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: MediaQuery.of(context).size.width > 900
                          ? 4
                          : 2,
                      childAspectRatio: 1.4,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: filteredCategories.length,
                    itemBuilder: (context, index) {
                      final category = filteredCategories[index];

                      return InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  CategoryScreen(title: category.title),
                            ),
                          );
                        },
                        child: Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(category.icon, size: 42, color: Colors.blue),
                              const SizedBox(height: 12),
                              Text(
                                category.title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                category.title == 'All'
                                    ? 'Browse all ads'
                                    : '${category.subcategories.length} subcategories',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Latest Ads',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 250,
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('listings')
                          .limit(10)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final docs = snapshot.data!.docs;
                        final filteredDocs = docs.where((doc) {
                          final data = doc.data() as Map<String, dynamic>;

                          final title =
                              data['title']?.toString().toLowerCase() ?? '';
                          final location =
                              data['location']?.toString().toLowerCase() ?? '';
                          final price =
                              data['price']?.toString().toLowerCase() ?? '';

                          final query = searchQuery.toLowerCase();

                          return title.contains(query) ||
                              location.contains(query) ||
                              price.contains(query);
                        }).toList();

                        if (docs.isEmpty) {
                          return const Center(child: Text('No ads yet'));
                        }

                        return ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: filteredDocs.length,
                          itemBuilder: (context, index) {
                            final data =
                                filteredDocs[index].data()
                                    as Map<String, dynamic>;

                            return InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ListingDetailsScreen(data: data),
                                  ),
                                );
                              },
                              child: Card(
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                clipBehavior: Clip.antiAlias,
                                margin: const EdgeInsets.all(8),
                                child: SizedBox(
                                  width: 280,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child:
                                            data['imageUrl'] != null &&
                                                data['imageUrl']
                                                    .toString()
                                                    .isNotEmpty
                                            ? Image.network(
                                                data['imageUrl'],
                                                width: double.infinity,
                                                fit: BoxFit.cover,
                                              )
                                            : Container(
                                                color: Colors.grey.shade300,
                                                child: const Center(
                                                  child: Icon(
                                                    Icons.image,
                                                    size: 50,
                                                  ),
                                                ),
                                              ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              data['title'] ?? '',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text('AED ${data['price'] ?? ''}'),
                                            Text(
                                              data['location'] ?? '',
                                              style: TextStyle(
                                                color: Colors.grey[600],
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
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      homeContent(),
      const FavoritesScreen(),
      const MyAdsScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('MarketHub')),
      body: pages[selectedIndex],
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddListingScreen()),
          );
          setState(() {});
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          setState(() {
            selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite),
            label: 'Favorites',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'My Ads'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class CategoryScreen extends StatefulWidget {
  final String title;

  const CategoryScreen({super.key, required this.title});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  String searchText = '';
  String selectedSubcategory = 'All';

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection(
      'listings',
    );

    if (widget.title != 'All') {
      query = query.where('category', isEqualTo: widget.title);
    }

    final currentCategory = categoryByTitle(widget.title);
    final subcategories = ['All', ...currentCategory.subcategories];

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: StreamBuilder<QuerySnapshot>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Error loading listings: ${snapshot.error}'),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          final filteredDocs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;

            final title = data['title']?.toString().toLowerCase() ?? '';
            final location = data['location']?.toString().toLowerCase() ?? '';
            final price = data['price']?.toString().toLowerCase() ?? '';
            final subcategory = data['subcategory']?.toString() ?? '';

            final query = searchText.toLowerCase();

            final matchesSearch =
                title.contains(query) ||
                location.contains(query) ||
                price.contains(query);

            final matchesSubcategory =
                selectedSubcategory == 'All' ||
                subcategory == selectedSubcategory;

            return matchesSearch && matchesSubcategory;
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search by title, location or price...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() {
                      searchText = value;
                    });
                  },
                ),
              ),
              if (widget.title != 'All')
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    scrollDirection: Axis.horizontal,
                    itemCount: subcategories.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final subcategory = subcategories[index];
                      final isSelected = selectedSubcategory == subcategory;

                      return ChoiceChip(
                        label: Text(subcategory),
                        selected: isSelected,
                        onSelected: (_) {
                          setState(() {
                            selectedSubcategory = subcategory;
                          });
                        },
                      );
                    },
                  ),
                ),
              Expanded(
                child: filteredDocs.isEmpty
                    ? const Center(child: Text('No listings found'))
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: filteredDocs.map((doc) {
                          final listing = Listing.fromDoc(doc);

                          return ListingCard(listing: listing);
                        }).toList(),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ListingCard extends StatefulWidget {
  final Listing listing;

  const ListingCard({super.key, required this.listing});

  @override
  State<ListingCard> createState() => _ListingCardState();
}

class _ListingCardState extends State<ListingCard> {
  bool get isFavorite {
    return favoriteListings.any((item) => item.id == widget.listing.id);
  }

  void toggleFavorite() async {
    setState(() {
      if (isFavorite) {
        favoriteListings.removeWhere((item) => item.id == widget.listing.id);
      } else {
        favoriteListings.add(widget.listing);
      }
    });

    if (isFavorite) {
      await FirebaseFirestore.instance
          .collection('favorites')
          .doc(widget.listing.id)
          .set(widget.listing.toMap());
    } else {
      await FirebaseFirestore.instance
          .collection('favorites')
          .doc(widget.listing.id)
          .delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.listing.imageUrl.trim().isNotEmpty;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AdDetailsScreen(listing: widget.listing),
          ),
        );
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        elevation: 5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              child: Stack(
                children: [
                  hasImage
                      ? Image.network(
                          widget.listing.imageUrl,
                          height: 170,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const SizedBox(
                              height: 170,
                              child: Center(
                                child: Icon(Icons.broken_image, size: 60),
                              ),
                            );
                          },
                        )
                      : const SizedBox(
                          height: 170,
                          child: Center(child: Icon(Icons.image, size: 60)),
                        ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: CircleAvatar(
                      backgroundColor: Colors.white,
                      child: IconButton(
                        icon: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border,
                          color: Colors.red,
                        ),
                        onPressed: toggleFavorite,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.listing.title.isEmpty
                              ? 'Untitled ad'
                              : widget.listing.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'AED ${widget.listing.price}',
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.listing.location,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        if (widget.listing.subcategory.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            widget.listing.subcategory,
                            style: const TextStyle(
                              color: Colors.blueGrey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: isFavorite ? Colors.red : null,
                    ),
                    onPressed: toggleFavorite,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AddListingScreen extends StatefulWidget {
  const AddListingScreen({super.key});

  @override
  State<AddListingScreen> createState() => _AddListingScreenState();
}

class _AddListingScreenState extends State<AddListingScreen> {
  XFile? selectedImage;
  final ImagePicker picker = ImagePicker();

  final titleController = TextEditingController();
  final priceController = TextEditingController();
  final locationController = TextEditingController();
  final phoneController = TextEditingController();
  final descriptionController = TextEditingController();

  String selectedCategory = 'Motors';
  String selectedSubcategory = 'Cars';
  bool isSubmitting = false;

  List<String> get currentSubcategories {
    return categoryByTitle(selectedCategory).subcategories;
  }

  Future<void> pickImage() async {
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      setState(() {
        selectedImage = image;
      });
    }
  }

  Future<String> uploadImage() async {
    if (selectedImage == null) return '';

    final bytes = await selectedImage!.readAsBytes();

    final ref = FirebaseStorage.instance
        .ref()
        .child('listings')
        .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));

    return ref.getDownloadURL();
  }

  Future<void> submitListing() async {
    if (titleController.text.trim().isEmpty ||
        priceController.text.trim().isEmpty ||
        locationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill title, price, and location')),
      );
      return;
    }

    setState(() {
      isSubmitting = true;
    });

    try {
      final imageUrl = await uploadImage();

      await FirebaseFirestore.instance.collection('listings').add({
        'title': titleController.text.trim(),
        'price': priceController.text.trim(),
        'location': locationController.text.trim(),
        'phone': phoneController.text.trim(),
        'description': descriptionController.text.trim(),
        'imageUrl': imageUrl,
        'category': selectedCategory,
        'subcategory': selectedSubcategory,
        'userId': FirebaseAuth.instance.currentUser?.uid ?? '',
        'sellerName':
            FirebaseAuth.instance.currentUser?.email ?? 'Anonymous seller',
        'createdAt': Timestamp.now(),
        'isFeatured': false,
      });

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to post ad: $e')));
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
    locationController.dispose();
    phoneController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subcategories = currentSubcategories;

    return Scaffold(
      appBar: AppBar(title: const Text('Post Ad')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: isSubmitting ? null : pickImage,
              child: const Text('Select Image'),
            ),
            if (selectedImage != null) ...[
              const SizedBox(height: 8),
              Text(selectedImage!.name),
            ],
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: priceController,
              decoration: const InputDecoration(labelText: 'Price'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: locationController,
              decoration: const InputDecoration(labelText: 'Location'),
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: 'WhatsApp Number',
                hintText: 'Example: 971543436947',
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
          ],
        ),
      ),
    );
  }
}

class MyAdsScreen extends StatefulWidget {
  const MyAdsScreen({super.key});

  @override
  State<MyAdsScreen> createState() => _MyAdsScreenState();
}

class _MyAdsScreenState extends State<MyAdsScreen> {
  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('My Ads')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('listings')
            .where('userId', isEqualTo: userId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading ads: ${snapshot.error}'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text('No ads posted yet'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final listing = Listing.fromDoc(docs[index]);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: listing.imageUrl.isEmpty
                      ? const Icon(Icons.image, size: 40)
                      : Image.network(
                          listing.imageUrl,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(Icons.image, size: 40);
                          },
                        ),
                  title: Text(listing.title),
                  subtitle: Text(
                    listing.subcategory.isEmpty
                        ? listing.location
                        : '${listing.location} • ${listing.subcategory}',
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditListingScreen(listing: listing),
                      ),
                    );
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () async {
                      await FirebaseFirestore.instance
                          .collection('listings')
                          .doc(listing.id)
                          .delete();
                    },
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

class EditListingScreen extends StatefulWidget {
  final Listing listing;

  const EditListingScreen({super.key, required this.listing});

  @override
  State<EditListingScreen> createState() => _EditListingScreenState();
}

class _EditListingScreenState extends State<EditListingScreen> {
  late TextEditingController titleController;
  late TextEditingController priceController;
  late TextEditingController locationController;
  late TextEditingController phoneController;
  late TextEditingController descriptionController;
  late String selectedCategory;
  late String selectedSubcategory;

  @override
  void initState() {
    super.initState();

    titleController = TextEditingController(text: widget.listing.title);
    priceController = TextEditingController(text: widget.listing.price);
    locationController = TextEditingController(text: widget.listing.location);
    phoneController = TextEditingController(text: widget.listing.phone);
    descriptionController = TextEditingController(
      text: widget.listing.description,
    );
    selectedCategory = widget.listing.category.isEmpty
        ? 'Motors'
        : widget.listing.category;
    selectedSubcategory = widget.listing.subcategory.isEmpty
        ? categoryByTitle(selectedCategory).subcategories.first
        : widget.listing.subcategory;
  }

  Future<void> updateListing() async {
    await FirebaseFirestore.instance
        .collection('listings')
        .doc(widget.listing.id)
        .update({
          'title': titleController.text.trim(),
          'price': priceController.text.trim(),
          'location': locationController.text.trim(),
          'phone': phoneController.text.trim(),
          'description': descriptionController.text.trim(),
          'category': selectedCategory,
          'subcategory': selectedSubcategory,
        });

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  void dispose() {
    titleController.dispose();
    priceController.dispose();
    locationController.dispose();
    phoneController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subcategories = categoryByTitle(selectedCategory).subcategories;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Ad')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: priceController,
              decoration: const InputDecoration(labelText: 'Price'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: locationController,
              decoration: const InputDecoration(labelText: 'Location'),
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'WhatsApp Number'),
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
              onChanged: (value) {
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
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    selectedSubcategory = value;
                  });
                }
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: updateListing,
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }
}

class AdDetailsScreen extends StatelessWidget {
  final Listing listing;

  const AdDetailsScreen({super.key, required this.listing});

  Future<void> openWhatsApp(BuildContext context) async {
    if (listing.phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seller phone number is missing')),
      );
      return;
    }

    final cleanedPhone = listing.phone.replaceAll(RegExp(r'[^0-9]'), '');
    final url = Uri.parse('https://wa.me/$cleanedPhone');

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open WhatsApp')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final images = <String>[];

    if (listing.imageUrl.trim().isNotEmpty) {
      images.add(listing.imageUrl);
    }

    return Scaffold(
      appBar: AppBar(title: Text(listing.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (images.isNotEmpty)
              SizedBox(
                height: 260,
                width: double.infinity,
                child: PageView.builder(
                  itemCount: images.length,
                  itemBuilder: (context, index) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        images[index],
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Icon(Icons.image, size: 80),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 20),
            Text(
              listing.title,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Price: AED ${listing.price}',
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 12),
            Text(
              'Location: ${listing.location}',
              style: const TextStyle(fontSize: 20),
            ),
            if (listing.category.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Category: ${listing.category}',
                style: const TextStyle(fontSize: 18),
              ),
            ],
            if (listing.subcategory.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Subcategory: ${listing.subcategory}',
                style: const TextStyle(fontSize: 18),
              ),
            ],
            if (listing.phone.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Contact: ${listing.phone}',
                style: const TextStyle(fontSize: 18),
              ),
            ],
            const SizedBox(height: 20),
            const Text(
              'Description:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              listing.description.isNotEmpty
                  ? listing.description
                  : 'No description provided.',
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => openWhatsApp(context),
              icon: const Icon(Icons.chat),
              label: const Text('WhatsApp Seller'),
            ),
          ],
        ),
      ),
    );
  }
}

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favorites')),
      body: favoriteListings.isEmpty
          ? const Center(child: Text('No favorites yet'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: favoriteListings.length,
              itemBuilder: (context, index) {
                return ListingCard(listing: favoriteListings[index]);
              },
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.account_circle, size: 90),
            const SizedBox(height: 20),
            Text(
              user?.email ?? 'Anonymous user',
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 12),
            Text('User ID: ${user?.uid ?? 'Unknown'}'),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                await FirebaseAuth.instance.signInAnonymously();

                if (!context.mounted) return;

                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Signed out')));
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

class ListingDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> data;

  const ListingDetailsScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(data['title'] ?? '')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.network(
              data['imageUrl'] ?? '',
              width: double.infinity,
              height: 300,
              fit: BoxFit.cover,
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data['title'] ?? '',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    'AED ${data['price']}',
                    style: const TextStyle(fontSize: 22, color: Colors.blue),
                  ),

                  const SizedBox(height: 10),

                  Text('Location: ${data['location'] ?? ''}'),

                  const SizedBox(height: 20),

                  Text(data['description'] ?? 'No description'),
                  const SizedBox(height: 25),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.phone),
                      label: const Text('Call Seller'),
                      onPressed: () async {
                        final phone = data['phone'] ?? '';

                        final url = Uri.parse('tel:$phone');

                        if (await canLaunchUrl(url)) {
                          await launchUrl(url);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 30),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.chat),
                      label: const Text('Contact on WhatsApp'),
                      onPressed: () async {
                        final whatsapp = data['whatsapp'] ?? '';

                        final url = Uri.parse('https://wa.me/$whatsapp');

                        if (await canLaunchUrl(url)) {
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
