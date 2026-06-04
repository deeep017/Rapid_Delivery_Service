import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'models.dart';
import 'aws_config.dart';

class ApiService {
  // =====================================================
  // CONFIGURATION
  // =====================================================

  /// Set to TRUE when deploying to AWS
  /// Set to FALSE for local Docker testing
  static const bool useAwsBackend = false;

  // =====================================================
  // BASE URLs - Automatically switches between AWS/Local
  // =====================================================
  static String get availabilityBaseUrl {
    if (useAwsBackend) {
      return AwsConfig.availabilityUrl;
    }
    // Local development
    if (kIsWeb) return "http://localhost:8000";
    return "http://10.0.2.2:8000"; // Android emulator
  }

  static String get orderBaseUrl {
    if (useAwsBackend) {
      return AwsConfig.orderUrl;
    }
    // Local development
    if (kIsWeb) return "http://localhost:8001";
    return "http://10.0.2.2:8001"; // Android emulator
  }

  // =====================================================
  // 1. Check Stock for a single item (existing endpoint)
  // =====================================================
  static Future<Map<String, dynamic>> checkStock(
    String itemId,
    double lat,
    double lon,
  ) async {
    final url = Uri.parse(
      "$availabilityBaseUrl/availability"
      "?item_id=$itemId&lat=$lat&lon=$lon",
    );

    try {
      final response = await http
          .get(url)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {"available": false, "error": "Status ${response.statusCode}"};
      }
    } catch (e) {
      print("Backend Error: $e");
      return {"available": false, "error": e.toString()};
    }
  }

  // =====================================================
  // 2. AGGREGATED AVAILABILITY — Multi-Warehouse
  //    Returns ALL products from up to 3 nearest warehouses
  // =====================================================
  static Future<Map<String, dynamic>> getAggregatedAvailability(
    double lat,
    double lon, {
    double maxDistance = 30.0,
    int maxWarehouses = 3,
  }) async {
    final url = Uri.parse(
      "$availabilityBaseUrl/availability/aggregated"
      "?lat=$lat&lon=$lon&max_distance=$maxDistance&max_warehouses=$maxWarehouses",
    );

    try {
      final response = await http
          .get(url)
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print("Aggregated Availability Error: $e");
    }

    return {"warehouses": [], "products": []};
  }

  /// Parse aggregated response into Product list with source info
  static List<Product> parseAggregatedProducts(Map<String, dynamic> data) {
    final List<dynamic> rawProducts = data['products'] ?? [];

    return rawProducts.map((p) {
      final List<dynamic> rawSources = p['sources'] ?? [];
      final sources = rawSources
          .map((s) => WarehouseSource.fromJson(s as Map<String, dynamic>))
          .toList();

      return Product(
        id: p['id'] ?? '',
        name: p['name'] ?? '',
        unit: p['unit'] ?? '1 unit',
        imageEmoji: p['imageEmoji'] ?? '📦',
        price: (p['price'] ?? 100).toDouble(),
        categoryId: p['categoryId'] ?? 'grocery',
        totalStock: p['total_stock'] ?? 0,
        bestWarehouseId: p['best_warehouse'] ?? '',
        bestEtaMinutes: p['best_eta'] ?? 10,
        sources: sources,
      );
    }).toList();
  }

  /// Parse warehouse info from aggregated response
  static List<WarehouseInfo> parseWarehouseInfo(Map<String, dynamic> data) {
    final List<dynamic> rawWarehouses = data['warehouses'] ?? [];
    return rawWarehouses
        .map((w) => WarehouseInfo.fromJson(w as Map<String, dynamic>))
        .toList();
  }

  // =====================================================
  // 3. Place Order (supports multi-warehouse)
  // =====================================================
  static Future<Map<String, dynamic>> placeOrder(
    String userId,
    List<Map<String, dynamic>> items,
  ) async {
    final url = Uri.parse("$orderBaseUrl/orders");

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({"customer_id": userId, "items": items}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        return {"error": "Server error: ${response.statusCode}"};
      }
    } catch (e) {
      return {"error": "Connection failed: $e"};
    }
  }

  // =====================================================
  // 4. OpenStreetMap: Search Locations
  // =====================================================
  static Future<List<dynamic>> searchLocations(String query) async {
    if (query.length < 3) return [];

    try {
      final url = Uri.parse(
        "https://nominatim.openstreetmap.org/search"
        "?q=$query&format=json&addressdetails=1&limit=5",
      );

      final response = await http.get(
        url,
        headers: {'User-Agent': 'RapidDeliveryApp/1.0'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print("OSM Error: $e");
    }

    return [];
  }

  // =====================================================
  // 5. Fetch Orders
  // =====================================================
  static Future<List<dynamic>> fetchOrders(String userId) async {
    final url = Uri.parse("$orderBaseUrl/orders/$userId");

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print("Order History Error: $e");
    }

    return [];
  }

  // =====================================================
  // 6. Get Order History (for Buyer flow)
  // =====================================================
  static Future<List<Map<String, dynamic>>> getOrderHistory(
    String userId,
  ) async {
    final url = Uri.parse("$orderBaseUrl/orders/$userId");

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((e) => e as Map<String, dynamic>).toList();
      }
    } catch (e) {
      print("Order History Error: $e");
    }

    return [];
  }

  // =====================================================
  // 7. Get Warehouses (for Manager flow)
  //    FIX: Backend returns {"warehouses": [...], "count": N}
  //         not a raw List
  // =====================================================
  static Future<List<Map<String, dynamic>>> getWarehouses() async {
    final url = Uri.parse("$availabilityBaseUrl/warehouses");

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Backend returns {"warehouses": [...]} — extract the list
        if (data is Map<String, dynamic>) {
          final List<dynamic> warehouses = data['warehouses'] ?? [];
          return warehouses.map((e) => e as Map<String, dynamic>).toList();
        }
        // Fallback: if it's already a list (shouldn't happen, but safe)
        if (data is List) {
          return data.map((e) => e as Map<String, dynamic>).toList();
        }
      }
    } catch (e) {
      print("Get Warehouses Error: $e");
    }

    return [];
  }

  // =====================================================
  // 8. Get Warehouse Inventory (for Manager flow)
  //    FIX: Backend returns {"inventory": [...]}
  //         not a raw List
  // =====================================================
  static Future<List<Map<String, dynamic>>> getWarehouseInventory(
    String warehouseId,
  ) async {
    final url = Uri.parse("$availabilityBaseUrl/inventory/$warehouseId");

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Backend returns {"inventory": [...]} — extract the list
        if (data is Map<String, dynamic>) {
          final List<dynamic> inventory = data['inventory'] ?? [];
          return inventory.map((e) => e as Map<String, dynamic>).toList();
        }
        if (data is List) {
          return data.map((e) => e as Map<String, dynamic>).toList();
        }
      }
    } catch (e) {
      print("Get Inventory Error: $e");
    }

    return [];
  }

  // =====================================================
  // 9. Get Warehouse Products (for Buyer flow — single warehouse)
  // =====================================================
  static Future<List<Product>> getWarehouseProducts(String warehouseId) async {
    final url = Uri.parse("$availabilityBaseUrl/products/$warehouseId");

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> products = data['products'] ?? [];

        return products
            .map(
              (p) => Product(
                id: p['id'] ?? '',
                name: p['name'] ?? '',
                unit: p['unit'] ?? '1 unit',
                imageEmoji: p['imageEmoji'] ?? '📦',
                price: (p['price'] ?? 100).toDouble(),
                categoryId: p['categoryId'] ?? 'grocery',
              ),
            )
            .toList();
      }
    } catch (e) {
      print("Get Warehouse Products Error: $e");
    }

    return [];
  }

  // =====================================================
  // 10. Update Stock (for Manager flow)
  // =====================================================
  static Future<Map<String, dynamic>> updateStock({
    required String warehouseId,
    required String productId,
    required int newStock,
  }) async {
    final url = Uri.parse(
      "$availabilityBaseUrl/inventory/$warehouseId/$productId",
    );

    try {
      final response = await http
          .put(
            url,
            headers: {"Content-Type": "application/json"},
            body: json.encode({"stock": newStock}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {"error": "Failed to update stock: ${response.statusCode}"};
      }
    } catch (e) {
      print("Update Stock Error: $e");
      return {"error": "Connection failed: $e"};
    }
  }

  // =====================================================
  // 11. Subscribe to SNS Notifications
  // =====================================================
  static Future<Map<String, dynamic>> subscribeToNotifications({
    required String warehouseId,
    required String email,
  }) async {
    final url = Uri.parse("$orderBaseUrl/subscribe");

    try {
      final response = await http
          .post(
            url,
            headers: {"Content-Type": "application/json"},
            body: json.encode({"warehouse_id": warehouseId, "email": email}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {"error": "Failed to subscribe: ${response.statusCode}"};
      }
    } catch (e) {
      print("Subscribe Error: $e");
      return {"error": "Connection failed: $e"};
    }
  }

  // =====================================================
  // 12. Get Warehouse Orders (for Manager)
  // =====================================================
  static Future<Map<String, dynamic>> getWarehouseOrders(
    String warehouseId,
  ) async {
    final url = Uri.parse("$orderBaseUrl/warehouse/$warehouseId/orders");

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {
          "orders": [],
          "count": 0,
          "error": "Status ${response.statusCode}",
        };
      }
    } catch (e) {
      print("Warehouse Orders Error: $e");
      return {"orders": [], "count": 0, "error": e.toString()};
    }
  }

  // CART CONSOLIDATION ALGORITHM
  // Runs client-side to decide which warehouse serves each item

  /// Given a cart and product source info, assign each cart item
  /// to the optimal warehouse using the consolidation algorithm:
  /// 1. Items only at ONE warehouse → forced assignment
  /// 2. If forced warehouse also has other items → consolidate there
  /// 3. Remaining items → nearest warehouse with stock
  ///
  /// Returns: Map<warehouseId, List<{item_id, qty, product}>>
  static Map<String, List<Map<String, dynamic>>> optimizeCartSources({
    required Map<String, int> cart,
    required List<Product> products,
  }) {
    final Map<String, List<Map<String, dynamic>>> assignment = {};
    final Set<String> assignedItems = {};

    // Build lookup: itemId -> Product
    final Map<String, Product> productMap = {
      for (var p in products) p.id: p,
    };

    // Step 1: Find items available at ONLY one warehouse (forced)
    final Set<String> forcedWarehouses = {};
    for (var entry in cart.entries) {
      final product = productMap[entry.key];
      if (product == null || product.sources.isEmpty) continue;
      if (product.sources.length == 1) {
        forcedWarehouses.add(product.sources.first.warehouseId);
      }
    }

    // Step 2: For each forced warehouse, grab as many items as possible
    for (var whId in forcedWarehouses) {
      assignment[whId] = [];
      for (var entry in cart.entries) {
        if (assignedItems.contains(entry.key)) continue;
        final product = productMap[entry.key];
        if (product == null) continue;

        // Check if this warehouse has this item with enough stock
        final source = product.sources
            .where((s) => s.warehouseId == whId && s.stock >= entry.value)
            .firstOrNull;
        if (source != null) {
          assignment[whId]!.add({
            'item_id': entry.key,
            'quantity': entry.value,
            'warehouse_id': whId,
            'product': product,
          });
          assignedItems.add(entry.key);
        }
      }
    }

    // Step 3: Remaining items → nearest warehouse that has stock
    for (var entry in cart.entries) {
      if (assignedItems.contains(entry.key)) continue;
      final product = productMap[entry.key];
      if (product == null || product.sources.isEmpty) continue;

      // Sort sources by distance, pick closest with enough stock
      final sortedSources = List<WarehouseSource>.from(product.sources)
        ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

      for (var source in sortedSources) {
        if (source.stock >= entry.value) {
          final whId = source.warehouseId;
          assignment.putIfAbsent(whId, () => []);
          assignment[whId]!.add({
            'item_id': entry.key,
            'quantity': entry.value,
            'warehouse_id': whId,
            'product': product,
          });
          assignedItems.add(entry.key);
          break;
        }
      }
    }

    return assignment;
  }

  /// Calculate delivery fee based on distance
  static double calculateDeliveryFee(double distanceKm, {bool isConsolidation = false}) {
    double fee;
    if (distanceKm <= 5) {
      fee = 0; // Free under 5km
    } else if (distanceKm <= 15) {
      fee = 20;
    } else if (distanceKm <= 30) {
      fee = 35;
    } else {
      fee = 50;
    }

    // Consolidation discount
    if (isConsolidation) {
      fee = (fee - 10).clamp(0, double.infinity);
    }

    return fee;
  }

  /// Calculate ETA based on distance
  static int calculateEta(double distanceKm) {
    if (distanceKm <= 5) return 10;
    if (distanceKm <= 15) return 25;
    if (distanceKm <= 30) return 40;
    return 60;
  }
}
