import 'package:my_finance/core/database/database_manager.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';

/// Property, tenant, contract aur property-document records manage karta hai.
class PropertyService {
  PropertyService._();

  static Future<void> ensureTables() async {
    final db = DatabaseManager.instance.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS properties (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'House',
        address TEXT NOT NULL DEFAULT '',
        ownership TEXT NOT NULL DEFAULT 'Owned',
        area TEXT NOT NULL DEFAULT '',
        purchase_price REAL NOT NULL DEFAULT 0,
        purchase_date TEXT NOT NULL DEFAULT '',
        current_value REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'Active',
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS property_tenants (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT NOT NULL DEFAULT '',
        email TEXT NOT NULL DEFAULT '',
        identity_number TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS property_contracts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        property_id INTEGER NOT NULL,
        tenant_id INTEGER NOT NULL,
        contract_type TEXT NOT NULL DEFAULT 'Rental',
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL DEFAULT '',
        rent REAL NOT NULL DEFAULT 0,
        frequency TEXT NOT NULL DEFAULT 'Monthly',
        deposit REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'Draft',
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS property_documents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        property_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        mime_type TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_property_contracts_property ON property_contracts(property_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_property_contracts_tenant ON property_contracts(tenant_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_property_documents_property ON property_documents(property_id)');
  }

  static Future<List<Map<String, dynamic>>> properties() async {
    await ensureTables();
    return DatabaseManager.instance.database.query('properties', orderBy: 'name COLLATE NOCASE');
  }

  static Future<List<Map<String, dynamic>>> tenants() async {
    await ensureTables();
    return DatabaseManager.instance.database.query('property_tenants', orderBy: 'name COLLATE NOCASE');
  }

  static Future<List<Map<String, dynamic>>> contracts() async {
    await ensureTables();
    return DatabaseManager.instance.database.rawQuery('''
      SELECT c.*, p.name AS property_name, t.name AS tenant_name
      FROM property_contracts c
      LEFT JOIN properties p ON p.id = c.property_id
      LEFT JOIN property_tenants t ON t.id = c.tenant_id
      ORDER BY c.start_date DESC, c.id DESC
    ''');
  }

  static Future<List<Map<String, dynamic>>> documents(int propertyId) async {
    await ensureTables();
    return DatabaseManager.instance.database.query(
      'property_documents',
      where: 'property_id = ?',
      whereArgs: [propertyId],
      orderBy: 'created_at DESC, id DESC',
    );
  }

  static Future<int> saveProperty({
    int? id,
    required String name,
    required String type,
    required String address,
    required String ownership,
    required String area,
    required double purchasePrice,
    required String purchaseDate,
    required double currentValue,
    required String status,
    required String notes,
  }) async {
    await ensureTables();
    if (name.trim().isEmpty || !purchasePrice.isFinite || purchasePrice < 0 ||
        !currentValue.isFinite || currentValue < 0) {
      throw ArgumentError('Enter valid property details.');
    }
    final values = <String, Object?>{
      'name': name.trim(), 'type': type, 'address': address.trim(),
      'ownership': ownership, 'area': area.trim(),
      'purchase_price': purchasePrice, 'purchase_date': purchaseDate,
      'current_value': currentValue, 'status': status, 'notes': notes.trim(),
    };
    final db = DatabaseManager.instance.database;
    final result = id == null
        ? await db.insert('properties', {...values, 'created_at': DateTime.now().toIso8601String()})
        : await db.update('properties', values, where: 'id = ?', whereArgs: [id]);
    if (id != null && result == 0) throw StateError('Property not found.');
    AppRefreshController.notifyChanged();
    return id ?? result;
  }

  static Future<int> saveTenant({
    int? id,
    required String name,
    required String phone,
    required String email,
    required String identityNumber,
    required String notes,
  }) async {
    await ensureTables();
    if (name.trim().isEmpty) throw ArgumentError('Tenant name is required.');
    final values = <String, Object?>{
      'name': name.trim(), 'phone': phone.trim(), 'email': email.trim(),
      'identity_number': identityNumber.trim(), 'notes': notes.trim(),
    };
    final db = DatabaseManager.instance.database;
    final result = id == null
        ? await db.insert('property_tenants', {...values, 'created_at': DateTime.now().toIso8601String()})
        : await db.update('property_tenants', values, where: 'id = ?', whereArgs: [id]);
    if (id != null && result == 0) throw StateError('Tenant not found.');
    AppRefreshController.notifyChanged();
    return id ?? result;
  }

  static Future<int> saveContract({
    required int propertyId,
    required int tenantId,
    required String contractType,
    required String startDate,
    required String endDate,
    required double rent,
    required String frequency,
    required double deposit,
    required String status,
    required String notes,
  }) async {
    await ensureTables();
    if (!rent.isFinite || rent < 0 || !deposit.isFinite || deposit < 0) {
      throw ArgumentError('Enter valid contract amounts.');
    }
    final db = DatabaseManager.instance.database;
    final property = await db.query('properties', columns: ['id'], where: 'id = ?', whereArgs: [propertyId], limit: 1);
    final tenant = await db.query('property_tenants', columns: ['id'], where: 'id = ?', whereArgs: [tenantId], limit: 1);
    if (property.isEmpty || tenant.isEmpty) throw StateError('Select a valid property and tenant.');
    final id = await db.insert('property_contracts', {
      'property_id': propertyId, 'tenant_id': tenantId,
      'contract_type': contractType, 'start_date': startDate,
      'end_date': endDate, 'rent': rent, 'frequency': frequency,
      'deposit': deposit, 'status': status, 'notes': notes.trim(),
      'created_at': DateTime.now().toIso8601String(),
    });
    AppRefreshController.notifyChanged();
    return id;
  }

  static Future<int> addDocument({
    required int propertyId,
    required String title,
    required String fileName,
    required String filePath,
    required String mimeType,
  }) async {
    await ensureTables();
    final id = await DatabaseManager.instance.database.insert('property_documents', {
      'property_id': propertyId, 'title': title.trim(), 'file_name': fileName,
      'file_path': filePath, 'mime_type': mimeType,
      'created_at': DateTime.now().toIso8601String(),
    });
    AppRefreshController.notifyChanged();
    return id;
  }

  static Future<void> updateDocument(
    int id, {
    String? title,
    String? fileName,
    String? filePath,
    String? mimeType,
  }) async {
    await ensureTables();
    final values = <String, Object?>{};
    if (title != null) values['title'] = title.trim();
    if (fileName != null) values['file_name'] = fileName;
    if (filePath != null) values['file_path'] = filePath;
    if (mimeType != null) values['mime_type'] = mimeType;
    if (values.isEmpty) return;
    final changed = await DatabaseManager.instance.database.update(
      'property_documents', values, where: 'id = ?', whereArgs: [id],
    );
    if (changed == 0) throw StateError('Property document not found.');
    AppRefreshController.notifyChanged();
  }

  static Future<void> deleteDocument(int id) async {
    await ensureTables();
    await DatabaseManager.instance.database.delete('property_documents', where: 'id = ?', whereArgs: [id]);
    AppRefreshController.notifyChanged();
  }

  static Future<void> deleteTenant(int id) async {
    await ensureTables();
    final db = DatabaseManager.instance.database;
    final linked = await db.query('property_contracts', columns: ['id'], where: 'tenant_id = ?', whereArgs: [id], limit: 1);
    if (linked.isNotEmpty) throw StateError('Remove this tenant\'s contracts before deleting the tenant.');
    await db.delete('property_tenants', where: 'id = ?', whereArgs: [id]);
    AppRefreshController.notifyChanged();
  }

  static Future<void> deleteContract(int id) async {
    await ensureTables();
    await DatabaseManager.instance.database.delete('property_contracts', where: 'id = ?', whereArgs: [id]);
    AppRefreshController.notifyChanged();
  }
}
