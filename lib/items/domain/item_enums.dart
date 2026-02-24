enum ItemStatus { pending, keep, returnItem, expired }

enum ItemSource { manual, gmailSync }

enum StoreType { amazon, shein, other }

extension ItemStatusX on ItemStatus {
  String get label {
    return switch (this) {
      ItemStatus.pending => 'Pending',
      ItemStatus.keep => 'Keep',
      ItemStatus.returnItem => 'Return',
      ItemStatus.expired => 'Expired',
    };
  }
}

extension ItemSourceX on ItemSource {
  String get label {
    return switch (this) {
      ItemSource.manual => 'Manual',
      ItemSource.gmailSync => 'Gmail sync',
    };
  }
}

extension StoreTypeX on StoreType {
  String get label {
    return switch (this) {
      StoreType.amazon => 'Amazon',
      StoreType.shein => 'SHEIN',
      StoreType.other => 'Other',
    };
  }
}
