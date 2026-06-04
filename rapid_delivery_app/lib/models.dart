// =====================================================
// DATA MODELS - Rapid Delivery App
// =====================================================

/// Product category for filtering
class ProductCategory {
  final String id;
  final String name;
  final String icon;
  final String color;

  const ProductCategory({
    required this.id,
    required this.name,
    required this.icon,
    this.color = '#0C831F',
  });
}

/// Info about a warehouse serving the user's area
class WarehouseInfo {
  final String id;
  final String city;
  final double distanceKm;
  final int etaMinutes;

  WarehouseInfo({
    required this.id,
    required this.city,
    required this.distanceKm,
    required this.etaMinutes,
  });

  factory WarehouseInfo.fromJson(Map<String, dynamic> json) {
    return WarehouseInfo(
      id: json['id'] ?? '',
      city: json['city'] ?? '',
      distanceKm: (json['distance_km'] ?? 0).toDouble(),
      etaMinutes: json['eta_minutes'] ?? 30,
    );
  }

  /// Delivery tier label for UI
  String get etaLabel {
    if (etaMinutes <= 15) return '⚡ $etaMinutes min';
    if (etaMinutes <= 30) return '🕐 $etaMinutes min';
    return '📦 $etaMinutes min';
  }
}

/// Which warehouse has stock of a particular product
class WarehouseSource {
  final String warehouseId;
  final int stock;
  final double distanceKm;
  final int etaMinutes;

  WarehouseSource({
    required this.warehouseId,
    required this.stock,
    required this.distanceKm,
    required this.etaMinutes,
  });

  factory WarehouseSource.fromJson(Map<String, dynamic> json) {
    return WarehouseSource(
      warehouseId: json['warehouse_id'] ?? '',
      stock: json['stock'] ?? 0,
      distanceKm: (json['distance_km'] ?? 0).toDouble(),
      etaMinutes: json['eta_minutes'] ?? 30,
    );
  }
}

/// Product model with multi-warehouse source info
class Product {
  final String id;
  final String name;
  final String unit;
  final String imageEmoji;
  final String? imageUrl; // For real product images
  final double price;
  final double? originalPrice; // For showing discounts
  final String categoryId;
  final String? description;
  final bool isBestSeller;
  final double? rating;

  /// Multi-warehouse fields
  final int totalStock; // Aggregated stock across all warehouses
  final String bestWarehouseId; // Closest warehouse with stock
  final int bestEtaMinutes; // Fastest delivery time
  final List<WarehouseSource> sources; // Per-warehouse breakdown

  Product({
    required this.id,
    required this.name,
    required this.unit,
    required this.imageEmoji,
    this.imageUrl,
    required this.price,
    this.originalPrice,
    this.categoryId = 'all',
    this.description,
    this.isBestSeller = false,
    this.rating,
    this.totalStock = 0,
    this.bestWarehouseId = '',
    this.bestEtaMinutes = 10,
    this.sources = const [],
  });

  int get discountPercent {
    if (originalPrice == null || originalPrice! <= price) return 0;
    return (((originalPrice! - price) / originalPrice!) * 100).round();
  }

  /// Delivery tier label based on fastest ETA
  String get etaLabel {
    if (bestEtaMinutes <= 15) return '⚡ $bestEtaMinutes min';
    if (bestEtaMinutes <= 30) return '🕐 $bestEtaMinutes min';
    return '📦 $bestEtaMinutes min';
  }

  /// Number of warehouses that have this product
  int get warehouseCount => sources.length;
}

/// User location model
class UserLocation {
  final String name;
  final String address; 
  final double lat;
  final double lon;
  final bool isSaved;

  UserLocation({
    required this.name,
    required this.address,
    required this.lat,
    required this.lon,
    this.isSaved = false,
  });
}

/// Saved address model
class SavedAddress {
  final String id;
  final String label; // "Home", "Work", "Other"
  final String fullAddress;
  final String? landmark;
  final double lat;
  final double lon;
  final bool isDefault;

  SavedAddress({
    required this.id,
    required this.label,
    required this.fullAddress,
    this.landmark,
    required this.lat,
    required this.lon,
    this.isDefault = false,
  });
}

/// Banner model for promotions
class PromoBanner {
  final String id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String backgroundColor;
  final String? actionUrl;

  const PromoBanner({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    this.backgroundColor = '#FFE4B5',
    this.actionUrl,
  });
}

/// Order status for tracking
enum OrderStatus {
  pending,
  confirmed,
  preparing,
  outForDelivery,
  delivered,
  cancelled,
}

/// Order tracking model
class OrderTracking {
  final String orderId;
  final OrderStatus status;
  final DateTime? estimatedDelivery;
  final String? deliveryPartner;
  final double? currentLat;
  final double? currentLon;
  final List<TrackingStep> steps;

  OrderTracking({
    required this.orderId,
    required this.status,
    this.estimatedDelivery,
    this.deliveryPartner,
    this.currentLat,
    this.currentLon,
    this.steps = const [],
  });
}

/// Individual tracking step
class TrackingStep {
  final String title;
  final String? subtitle;
  final DateTime? time;
  final bool isCompleted;

  TrackingStep({
    required this.title,
    this.subtitle,
    this.time,
    this.isCompleted = false,
  });
}
