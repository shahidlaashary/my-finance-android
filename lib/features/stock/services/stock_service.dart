import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/features/recycle_bin/services/recycle_bin_service.dart';

class StockItem {
  final int? id;
  final String name, sku, category, unit, notes;
  final double quantity, lowStockAt, purchasePrice, salePrice;
  const StockItem({this.id, required this.name, this.sku='', this.category='General', this.unit='pcs', required this.quantity, this.lowStockAt=0, this.purchasePrice=0, this.salePrice=0, this.notes=''});

  factory StockItem.fromMap(Map<String,dynamic> m)=>StockItem(
    id:(m['id'] as num).toInt(), name:m['name']?.toString()??'', sku:m['sku']?.toString()??'',
    category:m['category']?.toString()??'General', unit:m['unit']?.toString()??'pcs',
    quantity:(m['quantity'] as num).toDouble(), lowStockAt:(m['low_stock_at'] as num).toDouble(),
    purchasePrice:(m['purchase_price'] as num).toDouble(), salePrice:(m['sale_price'] as num).toDouble(), notes:m['notes']?.toString()??'',
  );
  bool get isLowStock=>quantity<=lowStockAt;
}

class StockMovement {
  final int? id, itemId;
  final String type, date, note;
  final double quantity, unitPrice;
  const StockMovement({this.id, required this.itemId, required this.type, required this.quantity, this.unitPrice=0, required this.date, this.note=''});
  factory StockMovement.fromMap(Map<String,dynamic> m)=>StockMovement(
    id:(m['id'] as num).toInt(), itemId:(m['item_id'] as num).toInt(), type:m['type']?.toString()??'IN',
    quantity:(m['quantity'] as num).toDouble(), unitPrice:(m['unit_price'] as num).toDouble(),
    date:m['movement_date']?.toString()??'', note:m['note']?.toString()??'',
  );
}

class StockService {
  static Future<void> _ensureTables() async {
    final db=FinanceDB.instance.db;
    await db.execute('''CREATE TABLE IF NOT EXISTS stock_items(
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, sku TEXT NOT NULL DEFAULT '',
      category TEXT NOT NULL DEFAULT 'General', unit TEXT NOT NULL DEFAULT 'pcs',
      quantity REAL NOT NULL DEFAULT 0, low_stock_at REAL NOT NULL DEFAULT 0,
      purchase_price REAL NOT NULL DEFAULT 0, sale_price REAL NOT NULL DEFAULT 0,
      notes TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS stock_movements(
      id INTEGER PRIMARY KEY AUTOINCREMENT, item_id INTEGER NOT NULL, type TEXT NOT NULL,
      quantity REAL NOT NULL, unit_price REAL NOT NULL DEFAULT 0, movement_date TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT '', FOREIGN KEY(item_id) REFERENCES stock_items(id))''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_movements_item ON stock_movements(item_id, movement_date DESC)');
  }
  static Future<List<StockItem>> getItems() async {
    await _ensureTables();
    final rows=await FinanceDB.instance.db.query('stock_items',orderBy:'name COLLATE NOCASE ASC');
    return rows.map(StockItem.fromMap).toList();
  }
  static Future<int> saveItem(StockItem item) async {
    await _ensureTables();
    if(item.name.trim().isEmpty) throw Exception('Item name is required.');
    if(!item.quantity.isFinite||item.quantity<0||!item.lowStockAt.isFinite||item.lowStockAt<0||!item.purchasePrice.isFinite||item.purchasePrice<0||!item.salePrice.isFinite||item.salePrice<0) throw Exception('Enter valid stock values.');
    final values={'name':item.name.trim(),'sku':item.sku.trim(),'category':item.category.trim().isEmpty?'General':item.category.trim(),'unit':item.unit.trim().isEmpty?'pcs':item.unit.trim(),'quantity':item.quantity,'low_stock_at':item.lowStockAt,'purchase_price':item.purchasePrice,'sale_price':item.salePrice,'notes':item.notes.trim()};
    final db=FinanceDB.instance.db;
    int id;
    if(item.id==null){id=await db.insert('stock_items',{...values,'created_at':DateTime.now().toIso8601String()});}
    else {final editable=Map<String,dynamic>.from(values)..remove('quantity');await db.update('stock_items',editable,where:'id=?',whereArgs:[item.id]);id=item.id!;}
    AppRefreshController.notifyChanged(); return id;
  }
  static Future<void> adjustStock({required int itemId,required String type,required double quantity,required double unitPrice,required String date,String note=''}) async {
    await _ensureTables();
    if(!quantity.isFinite||quantity<=0||!unitPrice.isFinite||unitPrice<0) throw Exception('Enter a valid quantity and price.');
    if(type!='IN'&&type!='OUT') throw Exception('Invalid stock movement.');
    final db=FinanceDB.instance.db;
    await db.transaction((txn) async {
      final rows=await txn.query('stock_items',where:'id=?',whereArgs:[itemId],limit:1);
      if(rows.isEmpty) throw Exception('Stock item not found.');
      final current=(rows.first['quantity'] as num).toDouble();
      if(type=='OUT'&&quantity>current) throw Exception('Stock out quantity exceeds available stock.');
      final next=type=='IN'?current+quantity:current-quantity;
      await txn.update('stock_items',{'quantity':next},where:'id=?',whereArgs:[itemId]);
      await txn.insert('stock_movements',{'item_id':itemId,'type':type,'quantity':quantity,'unit_price':unitPrice,'movement_date':date,'note':note.trim()});
    });
    AppRefreshController.notifyChanged();
  }
  static Future<List<StockMovement>> getMovements(int itemId) async {
    await _ensureTables();
    final rows=await FinanceDB.instance.db.query('stock_movements',where:'item_id=?',whereArgs:[itemId],orderBy:'movement_date DESC,id DESC');
    return rows.map(StockMovement.fromMap).toList();
  }
  static Future<void> deleteItem(int id) async {
    await _ensureTables();
    final db = FinanceDB.instance.db;
    final rows = await db.query('stock_items', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    final movements = await db.query('stock_movements', where: 'item_id = ?', whereArgs: [id]);
    await RecycleBinService.archive(
      type: 'Stock Item', title: rows.first['name']?.toString() ?? 'Stock Item',
      table: 'stock_items', id: id, record: rows.first, related: movements,
    );
    await db.transaction((txn) async {
      await txn.delete('stock_movements', where: 'item_id = ?', whereArgs: [id]);
      await txn.delete('stock_items', where: 'id = ?', whereArgs: [id]);
    });
    AppRefreshController.notifyChanged();
  }}
