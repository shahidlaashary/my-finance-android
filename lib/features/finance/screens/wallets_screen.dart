import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';
import 'package:intl/intl.dart';

import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/core/theme/app_colors.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/shared/widgets/shared_app_bar_actions.dart';

// Wallet ke options
// ============================================================

const List<String> walletTypes = [
  'Cash',
  'Bank',
  'Savings',
  'Current',
  'Credit Card',
  'Debit Card',
  'Digital Wallet',
  'Investment',
  'Other',
  'Custom',
];

const List<String> walletCurrencies = [
  'PKR',
  'USD',
  'GBP',
  'EUR',
  'AED',
  'SAR',
  'INR',
];

const List<IconData> walletIcons = [
  Icons.account_balance_wallet_outlined,
  Icons.account_balance_outlined,
  Icons.savings_outlined,
  Icons.credit_card_outlined,
  Icons.money_outlined,
  Icons.phone_android_outlined,
  Icons.trending_up_outlined,
  Icons.attach_money,
  Icons.payments_outlined,
  Icons.wallet_outlined,
  Icons.business_center_outlined,
  Icons.shopping_bag_outlined,
  Icons.currency_exchange_outlined,
  Icons.home_work_outlined,
  Icons.storefront_outlined,
  Icons.local_atm_outlined,
];

// ============================================================
// Wallets ka safha
// ============================================================

class _WalletWavePainter extends CustomPainter {
  final Color color;
  const _WalletWavePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    Path wave(double offset) => Path()
      ..moveTo(0, size.height * 0.30 + offset)
      ..quadraticBezierTo(size.width * 0.28, -size.height * 0.08 - offset, size.width * 0.52, size.height * 0.38)
      ..quadraticBezierTo(size.width * 0.78, size.height * 0.88 + offset, size.width, size.height * 0.20)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(wave(2), Paint()..color = color.withValues(alpha: 0.22));
    canvas.drawPath(wave(0), Paint()..color = color.withValues(alpha: 0.55));
    canvas.drawPath(wave(-2), Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _WalletWavePainter oldDelegate) => oldDelegate.color != color;
}

class WalletsPage extends StatefulWidget {
  const WalletsPage({super.key});

  @override
  State<WalletsPage> createState() => _WalletsPageState();
}

class _WalletsPageState extends State<WalletsPage> {
  List<Map<String, dynamic>> wallets = [];
  bool loading = true;
  bool hideBalances = false;
  String numberFormat = '1,234.56';

  @override
  void initState() {
    super.initState();
    GeneralPreferences.instance.revision.addListener(_onPreferencesChanged);
    loadWallets();
  }

  void _onPreferencesChanged() {
    if (mounted) loadWallets();
  }

  @override
  void dispose() {
    GeneralPreferences.instance.revision.removeListener(_onPreferencesChanged);
    super.dispose();
  }

  Future<void> loadWallets() async {
    setState(() => loading = true);

    final hide = await GeneralPreferences.instance.hideBalances;
    final format = await GeneralPreferences.instance.numberFormat;
    final result = await FinanceDB.instance.getWallets();

    if (!mounted) return;

    setState(() {
      wallets = result;
      hideBalances = hide;
      numberFormat = format;
      loading = false;
    });
  }

  String formatMoney(double amount, String currency) {
    if (hideBalances) return '$currency ••••••';
    final locale = numberFormat == '1.234,56' ? 'de_DE' : 'en_US';
    return '$currency ${NumberFormat('#,##0.00', locale).format(amount)}';
  }

  Future<void> openWalletForm([
    Map<String, dynamic>? wallet,
  ]) async {
    // Wallet ka form aik behtar bottom sheet mein kholta hai.
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WalletFormDialog(wallet: wallet),
    );

    if (saved == true) {
      await loadWallets();
    }
  }

  Future<void> deleteWallet(Map<String, dynamic> wallet) async {
    final requireConfirmation = await GeneralPreferences.instance.deleteConfirmation;
    final confirmed = requireConfirmation ? await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(appText(context, 'Delete Wallet?', 'والٹ حذف کریں؟')),
        content: Text(
          'Kya aap "${wallet['name']}" wallet delete karna chahte hain?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) : true;

    if (confirmed != true) return;

    try {
      await FinanceDB.instance.deleteWallet(wallet['id'] as int);
      if (await GeneralPreferences.instance.hapticFeedback) {
        await HapticFeedback.selectionClick();
      }
      await loadWallets();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.text,
        elevation: 0,
        titleSpacing: 16,
        toolbarHeight: 56,
        title: const Text(
          'My Wallets',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text),
        ),
        actions: buildMainSectionAppBarActions(context),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openWalletForm(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(appText(context, 'Add Wallet', 'والٹ شامل کریں')),
      ),
      body: loading
          ? Center(child: CircularProgressIndicator())
          : wallets.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 58,
                        color: AppColors.primary,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'No wallets added yet',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: loadWallets,
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1.92,
                    ),
                    itemCount: wallets.length,
                    itemBuilder: (context, index) {
                      final wallet = wallets[index];
                      final balance = (wallet['balance'] as num).toDouble();
                      final currency = wallet['currency'] as String;
                      final iconCode = wallet['icon_code'] as int;
                      final walletType = (wallet['type'] as String?) ?? 'Wallet';
                      final excluded = (wallet['exclude_total'] as int) == 1;

                      return Card(
                        color: Colors.white,
                        elevation: 0,
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: Color(0xFFE5ECE8)),
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              left: 0, right: 0, bottom: 0, height: 52,
                              child: CustomPaint(
                                painter: _WalletWavePainter(AppColors.primary),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 6, 4, 7),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 29, height: 29,
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(9),
                                        ),
                                        child: Icon(IconData(iconCode, fontFamily: 'MaterialIcons'),
                                            color: AppColors.primary, size: 17),
                                      ),
                                      SizedBox(width: 5),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(wallet['name'] as String,
                                              maxLines: 1, overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 10.5,
                                                fontWeight: FontWeight.w800, color: AppColors.text)),
                                            SizedBox(height: 2),
                                            Text(walletType, maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 9,
                                                fontWeight: FontWeight.w700, color: AppColors.primary)),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        width: 22,
                                        child: PopupMenuButton<String>(
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(minWidth: 145),
                                          icon: const Icon(Icons.more_vert_rounded),
                                          iconSize: 17,
                                        onSelected: (value) {
                                          if (value == 'edit') openWalletForm(wallet);
                                          else if (value == 'delete') deleteWallet(wallet);
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(value: 'edit', child: Row(children: [
                                            Icon(Icons.edit_outlined, size: 18), SizedBox(width: 9), Text(appText(context, 'Edit Wallet', 'والٹ میں ترمیم کریں'))])),
                                          PopupMenuItem(value: 'delete', child: Row(children: [
                                            Icon(Icons.delete_outline, size: 18, color: AppColors.expense),
                                            SizedBox(width: 9), Text(appText(context, 'Delete Wallet', 'والٹ حذف کریں'))])),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 47,
                                        child: Text('BALANCE', textAlign: TextAlign.left,
                                          style: TextStyle(fontSize: 8,
                                            fontWeight: FontWeight.w800, color: Colors.white)),
                                      ),
                                      Expanded(
                                        child: Text(formatMoney(balance, currency),
                                          maxLines: 1, textAlign: TextAlign.end,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12,
                                            fontWeight: FontWeight.w900, color: Colors.white,
                                            letterSpacing: -0.3)),
                                      ),
                                      if (excluded) ...[
                                        SizedBox(width: 3),
                                        const Icon(Icons.visibility_off_outlined,
                                          size: 11, color: Colors.white),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ============================================================
// Wallet add ya edit karne ka form
// ============================================================

class WalletFormDialog extends StatefulWidget {
  final Map<String, dynamic>? wallet;

  const WalletFormDialog({
    super.key,
    this.wallet,
  });

  @override
  State<WalletFormDialog> createState() => _WalletFormDialogState();
}

class _WalletFormDialogState extends State<WalletFormDialog> {
  final formKey = GlobalKey<FormState>();

  late final TextEditingController nameController;
  late final TextEditingController customTypeController;
  late final TextEditingController openingController;
  late final TextEditingController currentController;
  late final TextEditingController numberController;

  late String selectedType;
  late String selectedCurrency;
  late int selectedIcon;
  late bool excludeTotal;

  bool saving = false;

  bool get isEditing => widget.wallet != null;

  @override
  void initState() {
    super.initState();

    final wallet = widget.wallet;
        nameController = TextEditingController(
      text: wallet?['name'] as String? ?? '',
    );
    customTypeController = TextEditingController(
      text: wallet?['custom_type'] as String? ?? '',
    );
    openingController = TextEditingController(
      text: (wallet?['opening_balance'] ?? 0).toString(),
    );
    currentController = TextEditingController(
      text: (wallet?['balance'] ?? 0).toString(),
    );
    numberController = TextEditingController(
      text: wallet?['wallet_number'] as String? ?? '',
    );

    selectedType = wallet?['type'] as String? ?? 'Cash';
    selectedCurrency = wallet?['currency'] as String? ?? 'PKR';

    if (!walletTypes.contains(selectedType)) selectedType = 'Other';
    if (!walletCurrencies.contains(selectedCurrency)) {
      selectedCurrency = 'PKR';
    }

    selectedIcon =
        wallet?['icon_code'] as int? ?? walletIcons.first.codePoint;
    excludeTotal = (wallet?['exclude_total'] as int? ?? 0) == 1;
  }

  @override
  void dispose() {
    nameController.dispose();
    customTypeController.dispose();
    openingController.dispose();
    currentController.dispose();
    numberController.dispose();
    super.dispose();
  }

  double readAmount(TextEditingController controller) {
    return double.tryParse(controller.text.trim()) ?? 0;
  }

  Future<void> saveWallet() async {
    if (!formKey.currentState!.validate()) return;

    setState(() => saving = true);

    try {
      if (isEditing) {
        await FinanceDB.instance.updateWallet(
          id: widget.wallet!['id'] as int,
          name: nameController.text,
          type: selectedType,
          customType: selectedType == 'Custom'
              ? customTypeController.text.trim()
              : null,
          currency: selectedCurrency,
          requestedCurrentBalance: readAmount(currentController),
          walletNumber: numberController.text.trim().isEmpty
              ? null
              : numberController.text.trim(),
          iconCode: selectedIcon,
          excludeTotal: excludeTotal,
        );
      } else {
        await FinanceDB.instance.addWallet(
          name: nameController.text,
          type: selectedType,
          customType: selectedType == 'Custom'
              ? customTypeController.text.trim()
              : null,
          currency: selectedCurrency,
          openingBalance: readAmount(openingController),
          walletNumber: numberController.text.trim().isEmpty
              ? null
              : numberController.text.trim(),
          iconCode: selectedIcon,
          excludeTotal: excludeTotal,
        );
      }

      if (await GeneralPreferences.instance.hapticFeedback) {
        await HapticFeedback.selectionClick();
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
      setState(() => saving = false);
    }
  }

  InputDecoration _fieldDecoration(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon, size: 19),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E9E5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E9E5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 13),
      isDense: true,
    );
  }

  Widget _buildIconPicker() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 16 icons ko 8 columns mein rakh kar 2 rows banata hai.
        const spacing = 6.0;
        final itemWidth = (constraints.maxWidth - spacing * 7) / 8;

        return Wrap(
          spacing: spacing,
          runSpacing: 6,
          children: walletIcons.map((icon) {
            final selected = selectedIcon == icon.codePoint;

            return InkWell(
              onTap: () => setState(() => selectedIcon = icon.codePoint),
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: itemWidth,
                height: 37,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : const Color(0xFFF4F7F5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : const Color(0xFFE8EEEA),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: selected ? AppColors.primary : AppColors.muted,
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardIsOpen = keyboardHeight > 0;
    final maxSheetHeight = keyboardIsOpen
        ? (screenHeight - keyboardHeight).clamp(0.0, screenHeight) * 0.95
        : screenHeight * 0.72;

    // Keyboard khulne par bottom sheet uski jagah ke mutabiq narmi se upar jati hai.
    // Keyboard band hone par sheet apni pehli jagah par wapas aa jati hai.
    return AnimatedPadding(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxSheetHeight),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
              child: Form(
                key: formKey,
                // Sheet ko scroll karne ke bajaye keyboard khulne par upar le jana.
                child: SingleChildScrollView(
                  primary: false,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sheet ko kheenchne ke liye chhota handle.
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD9E0DC),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              isEditing ? 'Edit Wallet' : 'Add Wallet',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AppColors.text,
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: saving
                                ? null
                                : () => Navigator.pop(context, false),
                            icon: const Icon(Icons.close_rounded),
                            color: AppColors.muted,
                          ),
                        ],
                      ),
                      SizedBox(height: 10),

                      // Pehli row mein wallet ka naam aur qisam.
                      Row(
                        children: [
                          Expanded(
                            flex: 6,
                            child: TextFormField(
                              controller: nameController,
                              decoration: _fieldDecoration(
                                'Wallet Name',
                                icon: Icons.account_balance_wallet_outlined,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Name required';
                                }
                                return null;
                              },
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              value: selectedType,
                              isExpanded: true,
                              decoration: _fieldDecoration('Wallet Type'),
                              items: walletTypes.map((type) {
                                return DropdownMenuItem(
                                  value: type,
                                  child: Text(
                                    type,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => selectedType = value);
                                }
                              },
                            ),
                          ),
                        ],
                      ),

                      if (selectedType == 'Custom') ...[
                        SizedBox(height: 9),
                        TextFormField(
                          controller: customTypeController,
                          decoration: _fieldDecoration('Custom Wallet Type'),
                          validator: (value) {
                            if (selectedType == 'Custom' &&
                                (value == null || value.trim().isEmpty)) {
                              return 'Custom type required';
                            }
                            return null;
                          },
                        ),
                      ],

                      SizedBox(height: 8),
                      const Text(
                        'Wallet Icon',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      SizedBox(height: 5),
                      _buildIconPicker(),

                      SizedBox(height: 8),

                      // Currency aur amount aik hi row mein.
                      Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: DropdownButtonFormField<String>(
                              value: selectedCurrency,
                              isExpanded: true,
                              decoration: _fieldDecoration('Currency'),
                              items: walletCurrencies.map((currency) {
                                return DropdownMenuItem(
                                  value: currency,
                                  child: Text(
                                    currency,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => selectedCurrency = value);
                                }
                              },
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            flex: 5,
                            child: TextFormField(
                              controller: isEditing
                                  ? currentController
                                  : openingController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: true,
                              ),
                              decoration: _fieldDecoration(
                                isEditing
                                    ? 'Current Balance'
                                    : 'Opening Balance',
                              ),
                              validator: (value) {
                                if (value == null ||
                                    double.tryParse(value.trim()) == null) {
                                  return 'Enter valid amount';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: 7),
                      TextFormField(
                        controller: numberController,
                        decoration: _fieldDecoration(
                          'Wallet Number (Optional)',
                          icon: Icons.numbers_outlined,
                        ),
                      ),

                      SizedBox(height: 3),
                      // Label aur standard toggle aik hi seedhi line mein.
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Exclude from Total Balance',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text,
                              ),
                            ),
                          ),
                          Switch.adaptive(
                            value: excludeTotal,
                            activeTrackColor: AppColors.primary,
                            onChanged: (value) {
                              setState(() => excludeTotal = value);
                            },
                          ),
                        ],
                      ),

                      SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: saving
                                  ? null
                                  : () => Navigator.pop(context, false),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                foregroundColor: AppColors.text,
                                side: const BorderSide(
                                  color: Color(0xFFDDE5E0),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13),
                                ),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: saving ? null : saveWallet,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13),
                                ),
                              ),
                              child: saving
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'Save Wallet',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
