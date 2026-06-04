import 'package:flutter/material.dart';
import '../../services/inventory_service.dart';
import 'warehouse_orders_screen.dart';

class InventoryScreen extends StatefulWidget {
  final String warehouseId;
  final String warehouseName;
  final String userEmail;

  const InventoryScreen({
    super.key,
    required this.warehouseId,
    required this.warehouseName,
    required this.userEmail,
  });

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<Map<String, dynamic>> _inventory = [];
  List<Map<String, dynamic>> _filteredInventory = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _sortBy = 'name';

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  Future<void> _loadInventory() async {
    setState(() => _isLoading = true);

    final inventory = await InventoryService.getWarehouseInventory(
      widget.warehouseId,
    );

    setState(() {
      _inventory = inventory.isNotEmpty ? inventory : _getSampleInventory();
      _filteredInventory = List.from(_inventory);
      _isLoading = false;
    });
  }

  List<Map<String, dynamic>> _getSampleInventory() {
    return [
      {
        'product_id': 'apple',
        'name': 'Red Apple',
        'category': 'Fruits',
        'stock': 100,
        'min_stock': 20,
        'price': 120,
      },
      {
        'product_id': 'banana',
        'name': 'Bananas',
        'category': 'Fruits',
        'stock': 80,
        'min_stock': 15,
        'price': 60,
      },
      {
        'product_id': 'milk',
        'name': 'Fresh Milk',
        'category': 'Dairy',
        'stock': 200,
        'min_stock': 50,
        'price': 65,
      },
      {
        'product_id': 'eggs',
        'name': 'Farm Eggs (12)',
        'category': 'Dairy',
        'stock': 0,
        'min_stock': 30,
        'price': 85,
      },
      {
        'product_id': 'bread',
        'name': 'Wheat Bread',
        'category': 'Bakery',
        'stock': 50,
        'min_stock': 20,
        'price': 45,
      },
      {
        'product_id': 'rice',
        'name': 'Basmati Rice',
        'category': 'Grocery',
        'stock': 5,
        'min_stock': 15,
        'price': 180,
      },
      {
        'product_id': 'chips',
        'name': 'Potato Chips',
        'category': 'Snacks',
        'stock': 150,
        'min_stock': 30,
        'price': 35,
      },
      {
        'product_id': 'coke',
        'name': 'Cola Can',
        'category': 'Beverages',
        'stock': 120,
        'min_stock': 40,
        'price': 40,
      },
    ];
  }

  void _filterInventory(String query) {
    setState(() {
      _searchQuery = query;
      _filteredInventory =
          _inventory.where((item) {
            final name = (item['name'] ?? '').toString().toLowerCase();
            final category = (item['category'] ?? '').toString().toLowerCase();
            return name.contains(query.toLowerCase()) ||
                category.contains(query.toLowerCase());
          }).toList();
      _sortInventory(_sortBy);
    });
  }

  void _sortInventory(String by) {
    setState(() {
      _sortBy = by;
      _filteredInventory.sort((a, b) {
        switch (by) {
          case 'stock_low':
            return (a['stock'] as int).compareTo(b['stock'] as int);
          case 'stock_high':
            return (b['stock'] as int).compareTo(a['stock'] as int);
          case 'category':
            return (a['category'] ?? '').toString().compareTo(
              (b['category'] ?? '').toString(),
            );
          default:
            return (a['name'] ?? '').toString().compareTo(
              (b['name'] ?? '').toString(),
            );
        }
      });
    });
  }

  Future<void> _updateStock(Map<String, dynamic> item, int newStock) async {
    final result = await InventoryService.updateStock(
      warehouseId: widget.warehouseId,
      productId: item['product_id'],
      newStock: newStock,
    );

    if (result.containsKey('error')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['error']), backgroundColor: Colors.red),
        );
      }
    } else {
      // Update local state
      setState(() {
        final index = _inventory.indexWhere(
          (i) => i['product_id'] == item['product_id'],
        );
        if (index != -1) {
          _inventory[index]['stock'] = newStock;
        }
        _filterInventory(_searchQuery);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Stock updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _showUpdateDialog(Map<String, dynamic> item) {
    final controller = TextEditingController(text: item['stock'].toString());

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text('Update Stock: ${item['name']}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Current Stock: ${item['stock']}',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'New Stock Quantity',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _QuickAdjustButton(
                      label: '-10',
                      onTap: () {
                        int current = int.tryParse(controller.text) ?? 0;
                        controller.text =
                            (current - 10).clamp(0, 9999).toString();
                      },
                    ),
                    _QuickAdjustButton(
                      label: '-1',
                      onTap: () {
                        int current = int.tryParse(controller.text) ?? 0;
                        controller.text =
                            (current - 1).clamp(0, 9999).toString();
                      },
                    ),
                    _QuickAdjustButton(
                      label: '+1',
                      onTap: () {
                        int current = int.tryParse(controller.text) ?? 0;
                        controller.text =
                            (current + 1).clamp(0, 9999).toString();
                      },
                      isAdd: true,
                    ),
                    _QuickAdjustButton(
                      label: '+10',
                      onTap: () {
                        int current = int.tryParse(controller.text) ?? 0;
                        controller.text =
                            (current + 10).clamp(0, 9999).toString();
                      },
                      isAdd: true,
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final newStock = int.tryParse(controller.text);
                  if (newStock != null && newStock >= 0) {
                    Navigator.pop(ctx);
                    _updateStock(item, newStock);
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text(
                  'Update',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lowStockCount =
        _inventory
            .where((i) => (i['stock'] as int) < (i['min_stock'] as int))
            .length;
    final outOfStockCount =
        _inventory.where((i) => (i['stock'] as int) == 0).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.warehouseName,
              style: const TextStyle(color: Colors.white),
            ),
            Text(
              '${_inventory.length} products',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long, color: Colors.white),
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (ctx) => WarehouseOrdersScreen(
                          warehouseId: widget.warehouseId,
                          warehouseName: widget.warehouseName,
                        ),
                  ),
                ),
            tooltip: 'View Orders',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort, color: Colors.white),
            onSelected: _sortInventory,
            itemBuilder:
                (ctx) => [
                  const PopupMenuItem(
                    value: 'name',
                    child: Text('Sort by Name'),
                  ),
                  const PopupMenuItem(
                    value: 'stock_low',
                    child: Text('Stock: Low to High'),
                  ),
                  const PopupMenuItem(
                    value: 'stock_high',
                    child: Text('Stock: High to Low'),
                  ),
                  const PopupMenuItem(
                    value: 'category',
                    child: Text('Sort by Category'),
                  ),
                ],
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  _buildAlerts(lowStockCount, outOfStockCount),
                  _buildSearchBar(),
                  Expanded(child: _buildInventoryList()),
                ],
              ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddProductDialog,
        backgroundColor: Colors.orange,
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
      ),
    );
  }

  Widget _buildAlerts(int lowStock, int outOfStock) {
    if (lowStock == 0 && outOfStock == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: outOfStock > 0 ? Colors.red.shade50 : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: outOfStock > 0 ? Colors.red.shade200 : Colors.amber.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning,
            color: outOfStock > 0 ? Colors.red : Colors.amber.shade700,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (outOfStock > 0)
                  Text(
                    '$outOfStock products out of stock!',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                if (lowStock > 0)
                  Text(
                    '$lowStock products running low',
                    style: TextStyle(color: Colors.amber.shade800),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: TextField(
        onChanged: _filterInventory,
        decoration: const InputDecoration(
          icon: Icon(Icons.search, color: Colors.grey),
          hintText: 'Search products...',
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildInventoryList() {
    if (_filteredInventory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No products found',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredInventory.length,
      itemBuilder:
          (ctx, index) => _InventoryCard(
            item: _filteredInventory[index],
            onTap: () => _showUpdateDialog(_filteredInventory[index]),
          ),
    );
  }

  void _showAddProductDialog() {
    final nameController = TextEditingController();
    final stockController = TextEditingController();
    final priceController = TextEditingController();
    String category = 'Electronics';

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Add New Product'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Product Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: category,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                    items:
                        [
                              'Electronics',
                              'Furniture',
                              'Stationery',
                              'Clothing',
                              'Food',
                              'Other',
                            ]
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
                            .toList(),
                    onChanged: (val) => category = val ?? 'Electronics',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: stockController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Initial Stock',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Price (₹)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.isNotEmpty) {
                    final productId =
                        'prod_${DateTime.now().millisecondsSinceEpoch}';
                    final stock = int.tryParse(stockController.text) ?? 0;

                    // Save to Redis via API
                    final result = await InventoryService.updateStock(
                      warehouseId: widget.warehouseId,
                      productId: productId,
                      newStock: stock,
                    );

                    if (result.containsKey('error')) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('❌ Failed: ${result['error']}'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    // Add to local inventory for immediate display
                    setState(() {
                      _inventory.add({
                        'product_id': productId,
                        'name': nameController.text,
                        'category': category,
                        'stock': stock,
                        'min_stock': 10,
                        'price': int.tryParse(priceController.text) ?? 0,
                      });
                      _filterInventory(_searchQuery);
                    });
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ Product added & saved to Redis!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text('Add', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
    );
  }
}

class _QuickAdjustButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isAdd;

  const _QuickAdjustButton({
    required this.label,
    required this.onTap,
    this.isAdd = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isAdd ? Colors.green.shade50 : Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isAdd ? Colors.green : Colors.red,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _InventoryCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  const _InventoryCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final stock = item['stock'] as int;
    final minStock = item['min_stock'] as int;
    final isOutOfStock = stock == 0;
    final isLowStock = stock > 0 && stock < minStock;

    Color statusColor = Colors.green;
    String statusText = 'In Stock';
    if (isOutOfStock) {
      statusColor = Colors.red;
      statusText = 'Out of Stock';
    } else if (isLowStock) {
      statusColor = Colors.amber.shade700;
      statusText = 'Low Stock';
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border:
              isOutOfStock
                  ? Border.all(color: Colors.red.shade200)
                  : isLowStock
                  ? Border.all(color: Colors.amber.shade200)
                  : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _getCategoryColor(
                  item['category'],
                ).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getCategoryIcon(item['category']),
                color: _getCategoryColor(item['category']),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['name'] ?? 'Unknown Product',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    item['category'] ?? 'Uncategorized',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '₹${item['price']}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$stock',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
                Text(
                  'in stock',
                  style: TextStyle(color: Colors.grey[600], fontSize: 10),
                ),
              ],
            ),
            const SizedBox(width: 8),
            const Icon(Icons.edit, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  Color _getCategoryColor(String? category) {
    switch (category) {
      case 'Electronics':
        return Colors.blue;
      case 'Furniture':
        return Colors.brown;
      case 'Stationery':
        return Colors.purple;
      case 'Clothing':
        return Colors.pink;
      case 'Food':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String? category) {
    switch (category) {
      case 'Electronics':
        return Icons.devices;
      case 'Furniture':
        return Icons.chair;
      case 'Stationery':
        return Icons.edit_note;
      case 'Clothing':
        return Icons.checkroom;
      case 'Food':
        return Icons.restaurant;
      default:
        return Icons.category;
    }
  }
}
