import 'package:my_finance/core/database/database_manager.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:sqflite/sqflite.dart';

/// Property Manager ka tamam local data aik shared database connection mein rakhta hai.
class PropertyManagerService {
  static Database get _db => DatabaseManager.instance.database;

  static Future<void> ensureTables() async {
    await _db.execute('''CREATE TABLE IF NOT EXISTS properties (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL, type TEXT NOT NULL, address TEXT NOT NULL DEFAULT '',
      ownership TEXT NOT NULL DEFAULT 'Owned', area TEXT NOT NULL DEFAULT '',
      purchase_price REAL NOT NULL DEFAULT 0, purchase_date TEXT,
      current_value REAL NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'Active',
      notes TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL)''');
    await _db.execute('''CREATE TABLE IF NOT EXISTS property_documents (
      id INTEGER PRIMARY KEY AUTOINCREMENT, property_id INTEGER NOT NULL,
      title TEXT NOT NULL, file_name TEXT NOT NULL, file_path TEXT NOT NULL,
      mime_type TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL)''');
    await _db.execute('''CREATE TABLE IF NOT EXISTS property_tenants (
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT NOT NULL DEFAULT '',
      email TEXT NOT NULL DEFAULT '', identity_number TEXT NOT NULL DEFAULT '',
      notes TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL)''');
    await _db.execute('''CREATE TABLE IF NOT EXISTS property_contracts (
      id INTEGER PRIMARY KEY AUTOINCREMENT, property_id INTEGER NOT NULL,
      tenant_id INTEGER NOT NULL, contract_type TEXT NOT NULL DEFAULT 'Rental',
      start_date TEXT NOT NULL, end_date TEXT, rent REAL NOT NULL DEFAULT 0,
      frequency TEXT NOT NULL DEFAULT 'Monthly', deposit REAL NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'Active', notes TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL)''');
  }

  static Future<List<Map<String, dynamic>>> properties() async {
    await ensureTables();
    return _db.query('properties', orderBy: 'created_at DESC');
  }
  static Future<List<Map<String, dynamic>>> tenants() async {
    await ensureTables();
    return _db.query('property_tenants', orderBy: 'name COLLATE NOCASE');
  }
  static Future<List<Map<String, dynamic>>> contracts() async {
    await ensureTables();
    return _db.rawQuery('''SELECT c.*, p.name AS property_name, t.name AS tenant_name
      FROM property_contracts c
      LEFT JOIN properties p ON p.id=c.property_id
      LEFT JOIN property_tenants t ON t.id=c.tenant_id
      ORDER BY c.created_at DESC''');
  }
  static Future<List<Map<String, dynamic>>> documents(int propertyId) async {
    await ensureTables();
    return _db.query('property_documents', where: 'property_id=?',
      whereArgs: [propertyId], orderBy: 'id DESC');
  }

  static Future<int> saveProperty({int? id, required String name, required String type,
    required String address, required String ownership, required String area,
    required double purchasePrice, required String purchaseDate,
    required double currentValue, required String status, required String notes}) async {
    await ensureTables();
    if (name.trim().isEmpty || !purchasePrice.isFinite || purchasePrice < 0 ||
        !currentValue.isFinite || currentValue < 0) {
      throw ArgumentError('Enter valid property details.');
    }
    final values = {'name':name.trim(),'type':type,'address':address.trim(),
      'ownership':ownership,'area':area.trim(),'purchase_price':purchasePrice,
      'purchase_date':purchaseDate.isEmpty ? null : purchaseDate,
      'current_value':currentValue,'status':status,'notes':notes.trim()};
    final result = id == null
      ? await _db.insert('properties', {...values,'created_at':DateTime.now().toIso8601String()})
      : await _db.update('properties', values, where:'id=?', whereArgs:[id]);
    AppRefreshController.notifyChanged();
    return id ?? result;
  }
  static Future<void> deleteProperty(int id) async {
    await ensureTables();
    await _db.transaction((txn) async {
      await txn.delete('property_documents', where:'property_id=?', whereArgs:[id]);
      await txn.delete('property_contracts', where:'property_id=?', whereArgs:[id]);
      await txn.delete('properties', where:'id=?', whereArgs:[id]);
    });
    AppRefreshController.notifyChanged();
  }
  static Future<int> saveTenant({int? id, required String name, required String phone,
    required String email, required String identityNumber, required String notes}) async {
    await ensureTables();
    if(name.trim().isEmpty) throw ArgumentError('Tenant name is required.');
    final values={'name':name.trim(),'phone':phone.trim(),'email':email.trim(),
      'identity_number':identityNumber.trim(),'notes':notes.trim()};
    final result=id==null
      ? await _db.insert('property_tenants',{...values,'created_at':DateTime.now().toIso8601String()})
      : await _db.update('property_tenants',values,where:'id=?',whereArgs:[id]);
    AppRefreshController.notifyChanged();
    return id ?? result;
  }
  static Future<void> deleteTenant(int id) async {
    await ensureTables();
    final linked=await _db.query('property_contracts',where:'tenant_id=? AND status=?',whereArgs:[id,'Active'],limit:1);
    if(linked.isNotEmpty) throw StateError('End or remove the active contract before deleting this tenant.');
    await _db.delete('property_contracts',where:'tenant_id=?',whereArgs:[id]);
    await _db.delete('property_tenants',where:'id=?',whereArgs:[id]);
    AppRefreshController.notifyChanged();
  }
  static Future<int> saveContract({int? id, required int propertyId, required int tenantId,
    required String contractType, required String startDate, required String endDate,
    required double rent, required String frequency, required double deposit,
    required String status, required String notes}) async {
    await ensureTables();
    if(!rent.isFinite || rent<0 || !deposit.isFinite || deposit<0 || startDate.isEmpty) {
      throw ArgumentError('Enter valid contract details.');
    }
    final values={'property_id':propertyId,'tenant_id':tenantId,'contract_type':contractType,
      'start_date':startDate,'end_date':endDate.isEmpty?null:endDate,'rent':rent,
      'frequency':frequency,'deposit':deposit,'status':status,'notes':notes.trim()};
    final result=id==null
      ? await _db.insert('property_contracts',{...values,'created_at':DateTime.now().toIso8601String()})
      : await _db.update('property_contracts',values,where:'id=?',whereArgs:[id]);
    AppRefreshController.notifyChanged();
    return id ?? result;
  }
  static Future<void> deleteContract(int id) async {
    await ensureTables();
    await _db.delete('property_contracts',where:'id=?',whereArgs:[id]);
    AppRefreshController.notifyChanged();
  }
  static Future<int> addDocument({required int propertyId, required String title,
    required String fileName, required String filePath, required String mimeType}) async {
    await ensureTables();
    final id=await _db.insert('property_documents',{'property_id':propertyId,
      'title':title.trim().isEmpty?fileName:title.trim(),'file_name':fileName,
      'file_path':filePath,'mime_type':mimeType,'created_at':DateTime.now().toIso8601String()});
    AppRefreshController.notifyChanged();
    return id;
  }
  static Future<void> updateDocument(int id,{required String title, String? fileName,
    String? filePath, String? mimeType}) async {
    await ensureTables();
    final values=<String,Object?>{'title':title.trim()};
    if(fileName!=null) values['file_name']=fileName;
    if(filePath!=null) values['file_path']=filePath;
    if(mimeType!=null) values['mime_type']=mimeType;
    await _db.update('property_documents',values,where:'id=?',whereArgs:[id]);
    AppRefreshController.notifyChanged();
  }
  static Future<void> deleteDocument(int id) async {
    await ensureTables();
    await _db.delete('property_documents',where:'id=?',whereArgs:[id]);
    AppRefreshController.notifyChanged();
  }
}
