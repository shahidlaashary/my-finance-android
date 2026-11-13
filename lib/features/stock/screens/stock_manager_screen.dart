import 'package:flutter/material.dart';
import 'package:my_finance/features/stock/services/stock_service.dart';

class StockManagerScreen extends StatefulWidget {
  const StockManagerScreen({super.key});
  @override State<StockManagerScreen> createState()=>_StockManagerScreenState();
}
class _StockManagerScreenState extends State<StockManagerScreen>{
  List<StockItem> _items=[]; bool _loading=true; bool _lowOnly=false; String _search='';
  @override void initState(){super.initState();_load();}
  Future<void> _load() async {try{final v=await StockService.getItems();if(mounted)setState(()=>_items=v);}catch(e){_msg('Unable to load stock: $e');}finally{if(mounted)setState(()=>_loading=false);}}
  void _msg(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  String _qty(double n)=>n==n.roundToDouble()?n.toStringAsFixed(0):n.toStringAsFixed(2);
  Future<void> _edit([StockItem? item]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StockItemFormScreen(item: item),
      ),
    );
    if (saved == true && mounted) {
      await _load();
      _msg(item == null ? 'Stock item added.' : 'Stock item updated.');
    }
  }

  Future<void> _movement(StockItem item,String type) async {
    final qty=TextEditingController(),price=TextEditingController(text:type=='IN'?item.purchasePrice.toString():item.salePrice.toString()),note=TextEditingController();
    DateTime date=DateTime.now();
    String fmt(DateTime d)=>'${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
      title:Text(type=='IN'?'Stock In • ${item.name}':'Stock Out • ${item.name}'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        Text('Available: ${_qty(item.quantity)} ${item.unit}'),
        TextField(controller:qty,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:'Quantity *')),
        TextField(controller:price,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:type=='IN'?'Purchase Price per Unit':'Sale Price per Unit')),
        ListTile(contentPadding:EdgeInsets.zero,title:const Text('Date'),subtitle:Text(fmt(date)),trailing:const Icon(Icons.calendar_month),onTap:()async{final d=await showDatePicker(context:ctx,initialDate:date,firstDate:DateTime(2000),lastDate:DateTime(2100));if(d!=null)setD(()=>date=d);}),
        TextField(controller:note,decoration:const InputDecoration(labelText:'Note')),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(type=='IN'?'Add Stock':'Remove Stock'))],
    )));
    if(ok==true){final q=double.tryParse(qty.text),p=double.tryParse(price.text);if(q==null||p==null||q<=0||p<0){_msg('Enter a valid quantity and price.');}else{try{await StockService.adjustStock(itemId:item.id!,type:type,quantity:q,unitPrice:p,date:fmt(date),note:note.text);await _load();_msg(type=='IN'?'Stock added.':'Stock removed.');}catch(e){_msg('Stock update failed: $e');}}}
    qty.dispose();price.dispose();note.dispose();
  }
  Future<void> _history(StockItem item) async {
    await showDialog<void>(context:context,builder:(ctx)=>Dialog(child:SizedBox(width:480,child:Padding(padding:const EdgeInsets.all(16),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Row(children:[Expanded(child:Text('${item.name} • Movement History',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold))),IconButton(onPressed:()=>Navigator.pop(ctx),icon:const Icon(Icons.close))]),
      Flexible(child:FutureBuilder<List<StockMovement>>(future:StockService.getMovements(item.id!),builder:(context,s){if(s.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());if(s.hasError)return Text('Error: ${s.error}');final rows=s.data??[];if(rows.isEmpty)return const Padding(padding:EdgeInsets.all(20),child:Text('No stock movements yet.'));return ListView(shrinkWrap:true,children:rows.map((m)=>ListTile(leading:Icon(m.type=='IN'?Icons.south_west:Icons.north_east,color:m.type=='IN'?Colors.green:Colors.orange),title:Text('${m.type=='IN'?'Stock In':'Stock Out'} • ${_qty(m.quantity)} ${item.unit}'),subtitle:Text('${m.date} • ${m.note}'),trailing:Text(m.unitPrice.toStringAsFixed(2)))).toList());})),
    ])))));
  }
  @override Widget build(BuildContext context){
    final query=_search.trim().toLowerCase();
    final visible=_items.where((i)=>(!_lowOnly||i.isLowStock)&&(query.isEmpty||i.name.toLowerCase().contains(query)||i.sku.toLowerCase().contains(query)||i.category.toLowerCase().contains(query))).toList();
    final lowCount=_items.where((i)=>i.isLowStock).length;
    return Scaffold(appBar:AppBar(title:const Text('Stock Manager',style:TextStyle(fontWeight:FontWeight.w800)),actions:[IconButton(onPressed:_load,icon:const Icon(Icons.refresh))]),
      floatingActionButton:FloatingActionButton.extended(onPressed:()=>_edit(),icon:const Icon(Icons.add),label:const Text('Add Item')),
      body:_loading?const Center(child:CircularProgressIndicator()):RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.fromLTRB(14,12,14,100),children:[
        Row(children:[Expanded(child:_summary('Total Items','${_items.length}',Icons.inventory_2_outlined)),const SizedBox(width:10),Expanded(child:_summary('Low Stock','$lowCount',Icons.warning_amber_rounded,color:lowCount>0?Colors.orange:null))]),
        const SizedBox(height:12),
        TextField(onChanged:(v)=>setState(()=>_search=v),decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Search item, SKU or category',border:OutlineInputBorder())),
        const SizedBox(height:10),
        SwitchListTile(contentPadding:const EdgeInsets.symmetric(horizontal:12),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),tileColor:Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha:.45),title:const Text('Show low-stock items only'),value:_lowOnly,onChanged:(v)=>setState(()=>_lowOnly=v)),
        const SizedBox(height:8),
        if(visible.isEmpty)Padding(padding:const EdgeInsets.all(28),child:Center(child:Text(_items.isEmpty?'No stock items yet. Add your first item.':query.isNotEmpty?'No matching stock items.':_lowOnly?'No low-stock items. Everything is above its alert level.':'No stock items to show.'))),
        ...visible.map((i)=>Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[Expanded(child:Text(i.name,style:const TextStyle(fontSize:16,fontWeight:FontWeight.w800))),if(i.isLowStock)const Chip(label:Text('Low Stock'),backgroundColor:Color(0xFFFFE0B2))]),
          Text('${i.category} • ${i.sku.isEmpty?'No SKU':i.sku}'),
          const SizedBox(height:8),
          Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text('Available: ${_qty(i.quantity)} ${i.unit}',style:const TextStyle(fontWeight:FontWeight.w700)),Text('Alert at: ${_qty(i.lowStockAt)} ${i.unit}')]),
          if(i.lowStockAt>0)Padding(padding:const EdgeInsets.only(top:6),child:LinearProgressIndicator(value:(i.quantity/i.lowStockAt).clamp(0,1).toDouble(),color:i.isLowStock?Colors.orange:null)),
          Wrap(spacing:2,children:[
            TextButton.icon(onPressed:()=>_movement(i,'IN'),icon:const Icon(Icons.add_circle_outline),label:const Text('Stock In')),
            TextButton.icon(onPressed:()=>_movement(i,'OUT'),icon:const Icon(Icons.remove_circle_outline),label:const Text('Stock Out')),
            IconButton(tooltip:'History',onPressed:()=>_history(i),icon:const Icon(Icons.history)),
            IconButton(tooltip:'Edit',onPressed:()=>_edit(i),icon:const Icon(Icons.edit_outlined)),
            IconButton(tooltip:'Delete',onPressed:()async{final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Delete item?'),content:const Text('This also deletes its stock movement history.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Delete'))]));if(ok==true){await StockService.deleteItem(i.id!);await _load();}},icon:const Icon(Icons.delete_outline,color:Colors.red)),
          ]),
        ])))),
      ])));
  }
  Widget _summary(String title,String value,IconData icon,{Color? color})=>Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,color:color??Theme.of(context).colorScheme.primary),const SizedBox(height:8),Text(value,style:const TextStyle(fontSize:23,fontWeight:FontWeight.w800)),Text(title,style:Theme.of(context).textTheme.bodySmall)])));
}

class StockItemFormScreen extends StatefulWidget {
  final StockItem? item;

  const StockItemFormScreen({super.key, this.item});

  @override
  State<StockItemFormScreen> createState() => _StockItemFormScreenState();
}

class _StockItemFormScreenState extends State<StockItemFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _category;
  late final TextEditingController _unit;
  late final TextEditingController _quantity;
  late final TextEditingController _lowStock;
  late final TextEditingController _purchasePrice;
  late final TextEditingController _salePrice;
  late final TextEditingController _notes;
  bool _saving = false;

  bool get _isEditing => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _name = TextEditingController(text: item?.name ?? '');
    _sku = TextEditingController(text: item?.sku ?? '');
    _category = TextEditingController(text: item?.category ?? 'General');
    _unit = TextEditingController(text: item?.unit ?? 'pcs');
    _quantity = TextEditingController(text: item?.quantity.toString() ?? '0');
    _lowStock = TextEditingController(text: item?.lowStockAt.toString() ?? '0');
    _purchasePrice = TextEditingController(text: item?.purchasePrice.toString() ?? '0');
    _salePrice = TextEditingController(text: item?.salePrice.toString() ?? '0');
    _notes = TextEditingController(text: item?.notes ?? '');
  }

  @override
  void dispose() {
    for (final controller in [
      _name, _sku, _category, _unit, _quantity, _lowStock,
      _purchasePrice, _salePrice, _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  InputDecoration _decoration(String label, IconData icon, {String? helper}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      helperText: helper,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 13),
    );
  }

  String? _requiredName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Item name is required.';
    return null;
  }

  String? _nonNegativeNumber(String? value, {bool mustBePositive = false}) {
    final number = double.tryParse(value?.trim() ?? '');
    if (number == null || !number.isFinite ||
        (mustBePositive ? number <= 0 : number < 0)) {
      return mustBePositive ? 'Enter a quantity greater than zero.' : 'Enter a valid number (0 or more).';
    }
    return null;
  }

  Widget _numberField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool enabled = true,
    String? helper,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      decoration: _decoration(label, icon, helper: helper),
      validator: (value) => _nonNegativeNumber(value),
    );
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final original = widget.item;
      await StockService.saveItem(
        StockItem(
          id: original?.id,
          name: _name.text.trim(),
          sku: _sku.text.trim(),
          category: _category.text.trim(),
          unit: _unit.text.trim(),
          // Existing quantity is intentionally immutable here. All changes
          // must go through Stock In / Stock Out to retain movement history.
          quantity: original?.quantity ?? double.parse(_quantity.text.trim()),
          lowStockAt: double.parse(_lowStock.text.trim()),
          purchasePrice: double.parse(_purchasePrice.text.trim()),
          salePrice: double.parse(_salePrice.text.trim()),
          notes: _notes.text.trim(),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save item: $error')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Stock Item' : 'Add Stock Item',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEditing ? 'Update item details' : 'Enter the details of your inventory item',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: _decoration('Item Name *', Icons.inventory_2_outlined),
                validator: _requiredName,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _sku,
                      textInputAction: TextInputAction.next,
                      decoration: _decoration('SKU / Barcode', Icons.qr_code_2_rounded),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _category,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: _decoration('Category', Icons.category_outlined),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _unit,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: _decoration('Unit', Icons.straighten_rounded),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _numberField(
                      _quantity,
                      _isEditing ? 'Current Quantity' : 'Opening Quantity',
                      Icons.numbers_rounded,
                      enabled: !_isEditing,
                      helper: _isEditing ? 'Change via Stock In / Out' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _numberField(
                      _lowStock,
                      'Low Stock Alert At',
                      Icons.warning_amber_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _numberField(
                      _purchasePrice,
                      'Purchase Price / Unit',
                      Icons.shopping_cart_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _numberField(
                _salePrice,
                'Sale Price per Unit',
                Icons.sell_outlined,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                textCapitalization: TextCapitalization.sentences,
                minLines: 2,
                maxLines: 4,
                decoration: _decoration('Notes (Optional)', Icons.notes_rounded),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isEditing ? 'Save Changes' : 'Add Stock Item'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
