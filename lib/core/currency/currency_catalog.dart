/// Shared currency catalog used by Base Currency, Wallets and Exchange Rates.
class CurrencyCatalog {
  CurrencyCatalog._();

  static const List<String> supported = [
    'AED', 'AUD', 'BHD', 'CAD', 'CHF', 'CNY', 'EUR', 'GBP', 'HKD',
    'IDR', 'INR', 'JPY', 'KRW', 'KWD', 'MYR', 'NZD', 'OMR', 'PKR',
    'QAR', 'SAR', 'SGD', 'THB', 'TRY', 'USD', 'ZAR',
  ];
}
