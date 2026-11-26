/// Agreements ke liye built-in territory catalogue. Region membership sirf
/// selection ke liye hai; PDF mein selected display names print hote hain.
class AgreementTerritoryService {
  AgreementTerritoryService._();

  static const Map<String, List<String>> regions = {
    'Asia': [
      'Afghanistan','Armenia','Azerbaijan','Bahrain','Bangladesh','Bhutan','Brunei','Cambodia','China','Cyprus','Georgia','India','Indonesia','Iran','Iraq','Israel','Japan','Jordan','Kazakhstan','Kuwait','Kyrgyzstan','Laos','Lebanon','Malaysia','Maldives','Mongolia','Myanmar','Nepal','North Korea','Oman','Pakistan','Palestine','Philippines','Qatar','Saudi Arabia','Singapore','South Korea','Sri Lanka','Syria','Taiwan','Tajikistan','Thailand','Timor-Leste','Turkey','Turkmenistan','United Arab Emirates','Uzbekistan','Vietnam','Yemen'
    ],
    'Europe': [
      'Albania','Andorra','Austria','Belarus','Belgium','Bosnia and Herzegovina','Bulgaria','Croatia','Czechia','Denmark','Estonia','Finland','France','Germany','Greece','Hungary','Iceland','Ireland','Italy','Kosovo','Latvia','Liechtenstein','Lithuania','Luxembourg','Malta','Moldova','Monaco','Montenegro','Netherlands','North Macedonia','Norway','Poland','Portugal','Romania','Russia','San Marino','Serbia','Slovakia','Slovenia','Spain','Sweden','Switzerland','Ukraine','United Kingdom','Vatican City'
    ],
    'Africa': [
      'Algeria','Angola','Benin','Botswana','Burkina Faso','Burundi','Cabo Verde','Cameroon','Central African Republic','Chad','Comoros','Democratic Republic of the Congo','Djibouti','Egypt','Equatorial Guinea','Eritrea','Eswatini','Ethiopia','Gabon','Gambia','Ghana','Guinea','Guinea-Bissau','Ivory Coast','Kenya','Lesotho','Liberia','Libya','Madagascar','Malawi','Mali','Mauritania','Mauritius','Morocco','Mozambique','Namibia','Niger','Nigeria','Republic of the Congo','Rwanda','Sao Tome and Principe','Senegal','Seychelles','Sierra Leone','Somalia','South Africa','South Sudan','Sudan','Tanzania','Togo','Tunisia','Uganda','Zambia','Zimbabwe'
    ],
    'North America': [
      'Antigua and Barbuda','Bahamas','Barbados','Belize','Canada','Costa Rica','Cuba','Dominica','Dominican Republic','El Salvador','Grenada','Guatemala','Haiti','Honduras','Jamaica','Mexico','Nicaragua','Panama','Saint Kitts and Nevis','Saint Lucia','Saint Vincent and the Grenadines','Trinidad and Tobago','United States'
    ],
    'South America': [
      'Argentina','Bolivia','Brazil','Chile','Colombia','Ecuador','Guyana','Paraguay','Peru','Suriname','Uruguay','Venezuela'
    ],
    'Oceania': [
      'Australia','Fiji','Kiribati','Marshall Islands','Micronesia','Nauru','New Zealand','Palau','Papua New Guinea','Samoa','Solomon Islands','Tonga','Tuvalu','Vanuatu'
    ],
    'South Asia': ['Afghanistan','Bangladesh','Bhutan','India','Maldives','Nepal','Pakistan','Sri Lanka'],
    'East Asia': ['China','Japan','Mongolia','North Korea','South Korea','Taiwan'],
    'Southeast Asia': ['Brunei','Cambodia','Indonesia','Laos','Malaysia','Myanmar','Philippines','Singapore','Thailand','Timor-Leste','Vietnam'],
    'Central Asia': ['Kazakhstan','Kyrgyzstan','Tajikistan','Turkmenistan','Uzbekistan'],
    'Middle East': ['Bahrain','Cyprus','Iran','Iraq','Israel','Jordan','Kuwait','Lebanon','Oman','Palestine','Qatar','Saudi Arabia','Syria','Turkey','United Arab Emirates','Yemen'],
    'Western Europe': ['Austria','Belgium','France','Germany','Liechtenstein','Luxembourg','Monaco','Netherlands','Switzerland'],
    'Eastern Europe': ['Belarus','Bulgaria','Czechia','Hungary','Moldova','Poland','Romania','Russia','Slovakia','Ukraine'],
    'Northern Europe': ['Denmark','Estonia','Finland','Iceland','Ireland','Latvia','Lithuania','Norway','Sweden','United Kingdom'],
    'Southern Europe': ['Albania','Andorra','Bosnia and Herzegovina','Croatia','Greece','Italy','Kosovo','Malta','Montenegro','North Macedonia','Portugal','San Marino','Serbia','Slovenia','Spain','Vatican City'],
    'North Africa': ['Algeria','Egypt','Libya','Morocco','Sudan','Tunisia'],
    'West Africa': ['Benin','Burkina Faso','Cabo Verde','Ivory Coast','Gambia','Ghana','Guinea','Guinea-Bissau','Liberia','Mali','Mauritania','Niger','Nigeria','Senegal','Sierra Leone','Togo'],
    'East Africa': ['Burundi','Comoros','Djibouti','Eritrea','Ethiopia','Kenya','Madagascar','Malawi','Mauritius','Mozambique','Rwanda','Seychelles','Somalia','South Sudan','Tanzania','Uganda','Zambia','Zimbabwe'],
    'Central Africa': ['Angola','Cameroon','Central African Republic','Chad','Democratic Republic of the Congo','Equatorial Guinea','Gabon','Republic of the Congo','Sao Tome and Principe'],
    'Southern Africa': ['Botswana','Eswatini','Lesotho','Namibia','South Africa'],
    'Central America': ['Belize','Costa Rica','El Salvador','Guatemala','Honduras','Mexico','Nicaragua','Panama'],
    'Caribbean': ['Antigua and Barbuda','Bahamas','Barbados','Cuba','Dominica','Dominican Republic','Grenada','Haiti','Jamaica','Saint Kitts and Nevis','Saint Lucia','Saint Vincent and the Grenadines','Trinidad and Tobago'],
    'Pacific Islands': ['Fiji','Kiribati','Marshall Islands','Micronesia','Nauru','Palau','Papua New Guinea','Samoa','Solomon Islands','Tonga','Tuvalu','Vanuatu']
  };

  static List<String> get countries {
    final all = <String>{};
    for (final list in regions.values.take(6)) { all.addAll(list); }
    final result = all.toList()..sort();
    return result;
  }

  static List<String> get selectableNames {
    final names = <String>{'Worldwide', ...regions.keys, ...countries}.toList();
    names.remove('Worldwide');
    names.sort();
    return ['Worldwide', ...names];
  }

  static String normalizeForPdf(Iterable<String> values) {
    final selected = values.map((v) => v.trim()).where((v) => v.isNotEmpty).toSet();
    if (selected.contains('Worldwide') || selected.isEmpty) return 'Worldwide';
    final names = selected.toList()..sort();
    return names.join(', ');
  }
}
