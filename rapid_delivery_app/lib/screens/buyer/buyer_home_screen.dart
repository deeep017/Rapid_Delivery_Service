import 'package:flutter/material.dart';
import '../../models.dart';
import '../../api_service.dart';
import '../../data_repository.dart';
import '../../location_sheet.dart';
import '../../widgets/widgets.dart';
import '../../services/auth_service.dart';
import '../role_selection_screen.dart';
import 'cart_screen.dart';
import 'order_history_screen.dart';

class BuyerHomeScreen extends StatefulWidget {
  final String userEmail;
  final String userName;

  const BuyerHomeScreen({
    super.key,
    required this.userEmail,
    required this.userName,
  });

  @override
  State<BuyerHomeScreen> createState() => _BuyerHomeScreenState();
}

class _BuyerHomeScreenState extends State<BuyerHomeScreen> {
  // --- STATE ---
  UserLocation? _currentLocation;
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  List<ProductCategory> _categories = [];
  List<PromoBanner> _banners = [];
  String _selectedCategoryId = 'all';

  final Map<String, int> _cart = {};
  final Map<String, int> _stockLevels = {};

  /// Multi-warehouse state
  List<WarehouseInfo> _nearbyWarehouses = [];

  String _warehouseInfo = "Select a location to start";
  bool _isLoading = true;
  bool _deliveryAvailable = false;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    // Load categories and banners (static UI data)
    _categories = DataRepository.getCategories();
    _banners = DataRepository.getBanners();

    setState(() => _isLoading = false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showLocationSheet();
    });
  }

  void _filterByCategory(String categoryId) {
    setState(() {
      _selectedCategoryId = categoryId;

      // Start with products that have stock
      List<Product> baseProducts =
          _deliveryAvailable
              ? _products.where((p) => (_stockLevels[p.id] ?? 0) > 0).toList()
              : [];

      if (categoryId == 'all') {
        _filteredProducts = baseProducts;
      } else {
        _filteredProducts =
            baseProducts.where((p) => p.categoryId == categoryId).toList();
      }
      // Also apply search filter if active
      if (_searchController.text.isNotEmpty) {
        _runProductSearch(_searchController.text);
      }
    });
  }

  void _runProductSearch(String query) {
    setState(() {
      List<Product> inStock =
          _deliveryAvailable
              ? _products.where((p) => (_stockLevels[p.id] ?? 0) > 0).toList()
              : [];

      List<Product> base =
          _selectedCategoryId == 'all'
              ? inStock
              : inStock
                  .where((p) => p.categoryId == _selectedCategoryId)
                  .toList();

      if (query.isEmpty) {
        _filteredProducts = base;
      } else {
        _filteredProducts =
            base
                .where(
                  (p) => p.name.toLowerCase().contains(query.toLowerCase()),
                )
                .toList();
      }
    });
  }

  // =================================================================
  // CORE CHANGE: Aggregated multi-warehouse stock refresh
  // =================================================================
  Future<void> _refreshStock() async {
    if (_currentLocation == null) return;

    setState(() {
      _isLoading = true;
      _warehouseInfo = "Finding nearby warehouses...";
      _deliveryAvailable = false;
      _stockLevels.clear();
      _cart.clear();
      _nearbyWarehouses.clear();
    });

    // ---- Try aggregated endpoint first (multi-warehouse) ----
    final aggData = await ApiService.getAggregatedAvailability(
      _currentLocation!.lat,
      _currentLocation!.lon,
    );

    final aggWarehouses = ApiService.parseWarehouseInfo(aggData);
    final aggProducts = ApiService.parseAggregatedProducts(aggData);

    if (aggWarehouses.isNotEmpty && aggProducts.isNotEmpty) {
      // SUCCESS — aggregated data available
      _nearbyWarehouses = aggWarehouses;

      // Build stock levels from aggregated total stock
      _stockLevels.clear();
      for (var p in aggProducts) {
        _stockLevels[p.id] = p.totalStock;
      }

      final closestWh = aggWarehouses.first;
      setState(() {
        _products = aggProducts;
        _filteredProducts = List.from(aggProducts);
        _deliveryAvailable = true;
        _warehouseInfo =
            "⚡ ${aggWarehouses.length} warehouses nearby • "
            "Closest: ${closestWh.city} (${closestWh.distanceKm.toStringAsFixed(1)} km)";
      });
    } else {
      // ---- Fallback: single-warehouse probe (backward compatible) ----
      await _refreshStockSingleWarehouse();
    }

    setState(() => _isLoading = false);
  }

  /// Fallback for when the aggregated endpoint isn't deployed yet
  Future<void> _refreshStockSingleWarehouse() async {
    var probe = await ApiService.checkStock(
      "apple",
      _currentLocation!.lat,
      _currentLocation!.lon,
    );

    if (probe['available'] == true || probe['warehouse_id'] != null) {
      double dist = (probe['distance_km'] ?? 0).toDouble();
      final warehouseId = probe['warehouse_id'];
      final eta = ApiService.calculateEta(dist);

      // Create a single WarehouseInfo for backward compatibility
      _nearbyWarehouses = [
        WarehouseInfo(
          id: warehouseId,
          city: warehouseId,
          distanceKm: dist,
          etaMinutes: eta,
        ),
      ];

      setState(() {
        _deliveryAvailable = true;
        _warehouseInfo =
            "⚡ Delivery from $warehouseId (${dist.toStringAsFixed(1)} km)";
      });

      // Fetch products from this single warehouse
      final warehouseProducts = await ApiService.getWarehouseProducts(
        warehouseId,
      );

      if (warehouseProducts.isNotEmpty) {
        _stockLevels.clear();

        // Build products with single-source info
        List<Product> enrichedProducts = [];
        for (var p in warehouseProducts) {
          final result = await ApiService.checkStock(
            p.id,
            _currentLocation!.lat,
            _currentLocation!.lon,
          );
          final qty = result['available'] == true ? (result['quantity'] ?? 0) : 0;
          _stockLevels[p.id] = qty;

          // Enrich with source info so ProductCard badges work
          enrichedProducts.add(Product(
            id: p.id,
            name: p.name,
            unit: p.unit,
            imageEmoji: p.imageEmoji,
            price: p.price,
            categoryId: p.categoryId,
            totalStock: qty,
            bestWarehouseId: warehouseId,
            bestEtaMinutes: eta,
            sources: [
              WarehouseSource(
                warehouseId: warehouseId,
                stock: qty,
                distanceKm: dist,
                etaMinutes: eta,
              ),
            ],
          ));
        }

        setState(() {
          _products = enrichedProducts;
          _filteredProducts = List.from(enrichedProducts);
        });
      } else {
        setState(() {
          _products = [];
          _filteredProducts = [];
          _warehouseInfo = "📭 No products available at this warehouse";
        });
      }
    } else {
      setState(() {
        _deliveryAvailable = false;
        _warehouseInfo = "🚫 No delivery available in your area";
        _filteredProducts = [];
        _stockLevels.clear();
        _nearbyWarehouses.clear();
      });
    }
  }

  void _updateCart(String itemId, int change) {
    int currentQty = _cart[itemId] ?? 0;
    int maxStock = _stockLevels[itemId] ?? 0;
    int newQty = currentQty + change;

    if (newQty < 0) newQty = 0;
    if (newQty > maxStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Maximum stock limit reached!"),
          duration: Duration(milliseconds: 800),
        ),
      );
      return;
    }

    setState(() {
      if (newQty == 0) {
        _cart.remove(itemId);
      } else {
        _cart[itemId] = newQty;
      }
    });
  }

  void _showLocationSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (ctx) => LocationSearchSheet(
            onLocationSelected: (location) {
              setState(() => _currentLocation = location);
              _refreshStock();
            },
          ),
    );
  }

  void _openCart() {
    if (!_deliveryAvailable || _nearbyWarehouses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "No delivery available at your location. Please change your address.",
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_cart.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Your cart is empty!")));
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (ctx) => CartScreen(
              cart: _cart,
              products: _products,
              nearbyWarehouses: _nearbyWarehouses,
              userEmail: widget.userEmail,
              userName: widget.userName,
              onOrderPlaced: () {
                setState(() => _cart.clear());
                _refreshStock();
              },
            ),
      ),
    );
  }

  void _openOrders() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => OrderHistoryScreen(userEmail: widget.userEmail),
      ),
    );
  }

  // ignore: unused_element
  Future<void> _handleLogout() async {
    await AuthService.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (ctx) => const RoleSelectionScreen()),
        (route) => false,
      );
    }
  }

  int get _totalCartItems => _cart.values.fold(0, (sum, qty) => sum + qty);

  double get _totalCartAmount {
    double total = 0;
    for (var entry in _cart.entries) {
      final product = _products.firstWhere(
        (p) => p.id == entry.key,
        orElse: () => Product(id: '', name: '', unit: '', imageEmoji: '', price: 0),
      );
      total += product.price * entry.value;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: SafeArea(
        child:
            _isLoading
                ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF0C831F)),
                )
                : Column(
                  children: [
                    // Delivery Address Bar
                    DeliveryAddressBar(
                      currentLocation: _currentLocation,
                      deliveryInfo: _warehouseInfo,
                      onChangeLocation: _showLocationSheet,
                    ),
                    // Main Content
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _refreshStock,
                        color: const Color(0xFF0C831F),
                        child: CustomScrollView(
                          slivers: [
                            _buildSearchBar(),
                            _buildBannerSection(),
                            _buildCategorySection(),
                            _buildWarehouseInfo(),
                            _buildSectionHeader(),
                            _buildProductGrid(),
                          ],
                        ),
                      ),
                    ),
                    // Cart Bottom Bar
                    CartBottomBar(
                      itemCount: _totalCartItems,
                      totalAmount: _totalCartAmount,
                      onViewCart: _openCart,
                    ),
                  ],
                ),
      ),
      appBar: _buildAppBar(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0C831F),
      elevation: 0,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          const Text(
            'Rapid',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              // ignore: deprecated_member_use
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              '10 min',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.receipt_long, color: Colors.white),
          onPressed: _openOrders,
          tooltip: 'Order History',
        ),
        IconButton(
          icon: const Icon(Icons.person_outline, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Profile',
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: TextField(
          controller: _searchController,
          onChanged: _runProductSearch,
          decoration: InputDecoration(
            hintText: 'Search for groceries, snacks & more...',
            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            prefixIcon: Icon(Icons.search, color: Colors.grey.shade500),
            suffixIcon:
                _searchController.text.isNotEmpty
                    ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _runProductSearch('');
                      },
                    )
                    : null,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF0C831F)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBannerSection() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: BannerCarousel(banners: _banners),
      ),
    );
  }

  Widget _buildCategorySection() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: CategoryChips(
          categories: _categories,
          selectedCategoryId: _selectedCategoryId,
          onCategorySelected: _filterByCategory,
        ),
      ),
    );
  }

  Widget _buildWarehouseInfo() {
    if (_warehouseInfo.isEmpty || _currentLocation == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              _deliveryAvailable
                  ? const Color(0xFFE8F5E9)
                  : const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _deliveryAvailable ? Icons.check_circle : Icons.info,
                  color: _deliveryAvailable ? Colors.green : Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _warehouseInfo,
                    style: TextStyle(
                      color:
                          _deliveryAvailable
                              ? Colors.green[800]
                              : Colors.orange[800],
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            // Show warehouse chips when multiple are available
            if (_deliveryAvailable && _nearbyWarehouses.length > 1) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _nearbyWarehouses.map((wh) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Text(
                      '${wh.city} • ${wh.etaLabel}',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader() {
    String title = 'All Products';
    if (_selectedCategoryId != 'all') {
      final cat = _categories.firstWhere((c) => c.id == _selectedCategoryId);
      title = cat.name;
    }

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            Text(
              '${_filteredProducts.length} items',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductGrid() {
    if (_filteredProducts.isEmpty) {
      return const SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('🔍', style: TextStyle(fontSize: 48)),
              SizedBox(height: 16),
              Text(
                'No products found',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(12),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.68,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final product = _filteredProducts[index];
          return ProductCard(
            product: product,
            quantity: _cart[product.id] ?? 0,
            stockLevel: _stockLevels[product.id] ?? 0,
            onIncrement: () => _updateCart(product.id, 1),
            onDecrement: () => _updateCart(product.id, -1),
          );
        }, childCount: _filteredProducts.length),
      ),
    );
  }
}
