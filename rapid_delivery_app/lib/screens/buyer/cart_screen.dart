import 'package:flutter/material.dart';
import '../../models.dart';
import '../../api_service.dart';

class CartScreen extends StatefulWidget {
  final Map<String, int> cart;
  final List<Product> products;
  final List<WarehouseInfo> nearbyWarehouses;
  final String userEmail;
  final String userName;
  final VoidCallback onOrderPlaced;

  const CartScreen({
    super.key,
    required this.cart,
    required this.products,
    required this.nearbyWarehouses,
    required this.userEmail,
    required this.userName,
    required this.onOrderPlaced,
  });

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _isPlacingOrder = false;
  // ignore: unused_field
  String? _deliveryInstructions;

  /// Cart items grouped by warehouse after consolidation
  late Map<String, List<Map<String, dynamic>>> _warehouseGroups;

  /// Whether consolidation moved items to reduce warehouses
  bool _hasConsolidation = false;

  @override
  void initState() {
    super.initState();
    _optimizeCart();
  }

  /// Run the consolidation algorithm
  void _optimizeCart() {
    _warehouseGroups = ApiService.optimizeCartSources(
      cart: widget.cart,
      products: widget.products,
    );

    // Check if consolidation happened:
    // If any item was assigned to a warehouse that ISN'T its closest source
    _hasConsolidation = false;
    for (var whId in _warehouseGroups.keys) {
      for (var item in _warehouseGroups[whId]!) {
        final product = item['product'] as Product;
        if (product.sources.isNotEmpty) {
          final closestSource = product.sources.first; // Already sorted by distance
          if (closestSource.warehouseId != whId) {
            _hasConsolidation = true;
          }
        }
      }
    }
  }

  /// Get warehouse display name
  String _getWarehouseName(String warehouseId) {
    final wh = widget.nearbyWarehouses
        .where((w) => w.id == warehouseId)
        .firstOrNull;
    return wh?.city ?? warehouseId;
  }

  /// Get warehouse info
  WarehouseInfo? _getWarehouseInfo(String warehouseId) {
    return widget.nearbyWarehouses
        .where((w) => w.id == warehouseId)
        .firstOrNull;
  }

  double get _subtotal {
    double total = 0;
    for (var entry in widget.cart.entries) {
      final product = widget.products.firstWhere(
        (p) => p.id == entry.key,
        orElse: () => Product(id: '', name: '', unit: '', imageEmoji: '', price: 0),
      );
      total += product.price * entry.value;
    }
    return total;
  }

  /// Calculate delivery fee based on warehouses involved
  double get _deliveryFee {
    if (_subtotal > 499) return 0; // Free delivery above ₹499

    double totalFee = 0;
    bool isMultiWarehouse = _warehouseGroups.length > 1;

    for (var whId in _warehouseGroups.keys) {
      final wh = _getWarehouseInfo(whId);
      if (wh != null) {
        totalFee += ApiService.calculateDeliveryFee(
          wh.distanceKm,
          isConsolidation: isMultiWarehouse,
        );
      }
    }
    return totalFee;
  }

  double get _total => _subtotal + _deliveryFee;

  /// Max ETA across all warehouses involved
  int get _maxEta {
    int maxEta = 10;
    for (var whId in _warehouseGroups.keys) {
      final wh = _getWarehouseInfo(whId);
      if (wh != null && wh.etaMinutes > maxEta) {
        maxEta = wh.etaMinutes;
      }
    }
    return maxEta;
  }

  Future<void> _placeOrder() async {
    setState(() => _isPlacingOrder = true);

    // Prepare order items with warehouse assignments from consolidation
    List<Map<String, dynamic>> items = [];
    for (var whId in _warehouseGroups.keys) {
      for (var item in _warehouseGroups[whId]!) {
        items.add({
          'item_id': item['item_id'],
          'warehouse_id': whId,
          'quantity': item['quantity'],
        });
      }
    }

    final result = await ApiService.placeOrder(widget.userEmail, items);

    setState(() => _isPlacingOrder = false);

    if (result.containsKey('error')) {
      _showError(result['error']);
    } else {
      _showOrderSuccess(result);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showOrderSuccess(Map<String, dynamic> result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'Order Placed!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Order #${result['order_id'] ?? 'N/A'}',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.delivery_dining, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _warehouseGroups.length > 1
                              ? 'Items from ${_warehouseGroups.length} warehouses • Est. $_maxEta min'
                              : 'Your order will arrive in ~$_maxEta minutes',
                          style: const TextStyle(color: Colors.green),
                        ),
                      ),
                    ],
                  ),
                ),
                if (result['notification_sent'] == true) ...[
                  const SizedBox(height: 12),
                  Text(
                    '📧 Confirmation sent to ${widget.userEmail}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ],
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                    widget.onOrderPlaced();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0C831F),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Continue Shopping',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Your Cart',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Cart Items GROUPED BY WAREHOUSE
                ..._warehouseGroups.entries.map((entry) {
                  final whId = entry.key;
                  final items = entry.value;
                  final whInfo = _getWarehouseInfo(whId);

                  return _WarehouseGroupCard(
                    warehouseId: whId,
                    warehouseName: _getWarehouseName(whId),
                    distanceKm: whInfo?.distanceKm ?? 0,
                    etaMinutes: whInfo?.etaMinutes ?? 10,
                    items: items,
                    products: widget.products,
                  );
                }),

                // Consolidation info
                if (_hasConsolidation) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.auto_fix_high,
                          color: Colors.blue.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Smart Consolidation',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade800,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Some items were moved to a warehouse that already has exclusive items, reducing the number of delivery trips.',
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Delivery Instructions
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Delivery Instructions (Optional)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        onChanged: (value) => _deliveryInstructions = value,
                        decoration: InputDecoration(
                          hintText: 'E.g., Leave at door, call on arrival',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Bill Summary
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Bill Summary',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _BillRow(
                        label: 'Item Total',
                        value: '₹${_subtotal.toStringAsFixed(2)}',
                      ),
                      _BillRow(
                        label: _warehouseGroups.length > 1
                            ? 'Delivery (${_warehouseGroups.length} warehouses)'
                            : 'Delivery Fee',
                        value:
                            _deliveryFee == 0
                                ? 'FREE'
                                : '₹${_deliveryFee.toStringAsFixed(2)}',
                        valueColor: _deliveryFee == 0 ? Colors.green : null,
                      ),
                      if (_deliveryFee == 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Free delivery on orders above ₹499',
                            style: TextStyle(
                              color: Colors.green[600],
                              fontSize: 12,
                            ),
                          ),
                        ),
                      _BillRow(
                        label: 'Estimated Time',
                        value: '~$_maxEta min',
                        valueColor: Colors.orange,
                      ),
                      const Divider(height: 24),
                      _BillRow(
                        label: 'Total',
                        value: '₹${_total.toStringAsFixed(2)}',
                        isBold: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bottom Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isPlacingOrder ? null : _placeOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0C831F),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child:
                      _isPlacingOrder
                          ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : Text(
                            'Place Order • ₹${_total.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// WAREHOUSE GROUP CARD — Shows items from one warehouse
// =====================================================
class _WarehouseGroupCard extends StatelessWidget {
  final String warehouseId;
  final String warehouseName;
  final double distanceKm;
  final int etaMinutes;
  final List<Map<String, dynamic>> items;
  final List<Product> products;

  const _WarehouseGroupCard({
    required this.warehouseId,
    required this.warehouseName,
    required this.distanceKm,
    required this.etaMinutes,
    required this.items,
    required this.products,
  });

  Color get _tierColor {
    if (etaMinutes <= 15) return Colors.green;
    if (etaMinutes <= 30) return Colors.amber.shade700;
    return Colors.orange;
  }

  String get _etaLabel {
    if (etaMinutes <= 15) return '⚡ $etaMinutes min';
    if (etaMinutes <= 30) return '🕐 $etaMinutes min';
    return '📦 $etaMinutes min';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _tierColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Warehouse header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _tierColor.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(11),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.warehouse, color: _tierColor, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    warehouseName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _tierColor,
                      fontSize: 13,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _tierColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$_etaLabel • ${distanceKm.toStringAsFixed(1)} km',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _tierColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Items from this warehouse
          ...items.map((item) {
            final product = item['product'] as Product;
            final qty = item['quantity'] as int;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        product.imageEmoji,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '${product.unit} × $qty',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '₹${(product.price * qty).toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// =====================================================
// BILL ROW
// =====================================================
class _BillRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool isBold;

  const _BillRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: isBold ? 16 : 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: isBold ? 16 : 14,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
