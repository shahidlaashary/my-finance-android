import 'package:flutter/material.dart';
import 'package:my_finance/features/stock/services/stock_service.dart';

class StockManagerScreen extends StatefulWidget {
  const StockManagerScreen({super.key});
  @override State<StockManagerScreen> createState()=>_StockManagerScreenState();
}
class _StockManagerScreenState extends State<StockManagerScreen>{
  List<StockItem> _items=[]; bool _loading=true; bool _lowOnly=false;
  @override void initState(){super.initState();_load();}
  Future<void> _load() async {try{final v=await StockService.getItems();if(mounted)setState(()=>_items=v);}catch(e){_msg('Unable to load stock: $e');}finally{if(mounted)setState(()=>_loading=false);}}
  void _msg(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  String _qty(double n)=>n==n.roundToDouble()?n.toStringAsFixed(0):n.toStringAsFixed(2);
  Future<void> _edit([StockItem? item]) async {
    final name=TextEditingController(text:item?.name??'');
    final sku=TextEditingController(text:item?.sku??'');
    final category=TextEditingController(text:item?.category??'General');
    final unit=TextEditingController(text:item?.unit??'pcs');
    final quantity=TextEditingController(text:item?.quantity.toString()??'0');
    final low=TextEditingController(text:item?.lowStockAt.toString()??'0');
    final buy=TextEditingController(text:item?.purchasePrice.toString()??'0');
    final sell=TextEditingController(text:item?.salePrice.toString()??'0');
    final notes=TextEditingController(text:item?.notes??'');
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:Text(item==null?'Add Stock Item':'Edit Stock Item'),
      content:SizedBox(width:440,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:name,decoration:const InputDecoration(labelText:'Item Name *')),
        TextField(controller:sku,decoration:const InputDecoration(labelText:'SKU / Barcode')),
        TextField(controller:category,decoration:const InputDecoration(labelText:'Category')),
        TextField(controller:unit,decoration:const InputDecoration(labelText:'Unit (pcs, kg, litre...)')),
        TextField(controller:quantity,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Opening Quantity')),
        TextField(controller:low,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Low Stock Alert At')),
        TextField(controller:buy,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Purchase Price per Unit')),
        TextField(controller:sell,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Sale Price per Unit')),
        TextField(controller:notes,maxLines:2,decoration:const InputDecoration(labelText:'Notes')),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save'))],
    ));
    if(ok==true){
      final q=double.tryParse(quantity.text), l=double.tryParse(low.text), b=double.tryParse(buy.text), s=double.tryParse(sell.text);
      if(name.text.trim().isEmpty||q==null||l==null||b==null||s==null||q<0||l<0||b<0||s<0){_msg('Please enter valid item details.');}
      else{try{await StockService.saveItem(StockItem(id:item?.id,name:name.text,sku:sku.text,category:category.text,unit:unit.text,quantity:q,lowStockAt:l,purchasePrice:b,salePrice:s,notes:notes.text));await _load();_msg('Stock item saved.');}catch(e){_msg('Could not save item: $e');}}
    }
    for(final c in [name,sku,category,unit,quantity,low,buy,sell,notes]){c.dispose();}
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
    final visible=_items.where((i)=>!_lowOnly||i.isLowStock).toList();
    final lowCount=_items.where((i)=>i.isLowStock).length;
    return Scaffold(appBar:AppBar(title:const Text('Stock Manager',style:TextStyle(fontWeight:FontWeight.w800)),actions:[IconButton(onPressed:_load,icon:const Icon(Icons.refresh))]),
      floatingActionButton:FloatingActionButton.extended(onPressed:()=>_edit(),icon:const Icon(Icons.add),label:const Text('Add Item')),
      body:_loading?const Center(child:CircularProgressIndicator()):RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.fromLTRB(14,12,14,100),children:[
        Row(children:[Expanded(child:_summary('Total Items','${_items.length}',Icons.inventory_2_outlined)),const SizedBox(width:10),Expanded(child:_summary('Low Stock','$lowCount',Icons.warning_amber_rounded,color:lowCount>0?Colors.orange:null))]),
        const SizedBox(height:12),
        SwitchListTile(contentPadding:const EdgeInsets.symmetric(horizontal:12),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),tileColor:Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha:.45),title:const Text('Show low-stock items only'),value:_lowOnly,onChanged:(v)=>setState(()=>_lowOnly=v)),
        const SizedBox(height:8),
        if(visible.isEmpty)Padding(padding:const EdgeInsets.all(28),child:Center(child:Text(_items.isEmpty?'No stock items yet. Add your first item.':'No low-stock items. Everything is above its alert level.'))),
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
