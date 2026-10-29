import '../../engine/assets/text_table.dart';

import 'class_table.dart';

/// Only source-confirmed categories have semantic names. Other tables remain
/// available by their original id through [tables], without invented schemas.
class GameCatalog {
  GameCatalog(this.tables);
  final GameClassTables tables;

  List<CatalogItem> get animals => _items(0, 9);
  List<CatalogItem> get products => _items(1, null);
  List<CropDefinition> get crops =>
      List<CropDefinition>.unmodifiable(tables[2].rows.map(CropDefinition._));
  List<CatalogItem> get buildings => _items(3, 12);
  List<CatalogItem> get decorations => _items(4, 8);
  List<MissionDefinition> get missions => List<MissionDefinition>.unmodifiable(
    tables[6].rows.map(MissionDefinition._),
  );
  List<RecipeDefinition> get recipes => List<RecipeDefinition>.unmodifiable(
    tables[7].rows.map(RecipeDefinition._),
  );
  List<CatalogItem> get feedRecipes => _items(22, 4);

  List<CatalogItem> _items(int tableId, int? unlockColumn) =>
      List<CatalogItem>.unmodifiable(
        tables[tableId].rows.map(
          (row) => CatalogItem._(tableId, row, unlockColumn),
        ),
      );

  CropDefinition cropById(int id) => crops.firstWhere(
    (crop) => crop.id == id,
    orElse: () => throw RangeError('Unknown original crop id $id'),
  );
}

/// Reference to original table fields; values stay signed and sentinels (-1)
/// are preserved. A null unlockLevel means this column has not been mapped.
class CatalogItem {
  CatalogItem._(this.tableId, this.rawFields, this._unlockColumn);
  final int tableId;
  final List<int> rawFields;
  final int? _unlockColumn;
  int get index => rawFields[0];
  int get id => rawFields[1];
  int get nameTextId => rawFields[2];
  int? get unlockLevel =>
      _unlockColumn == null ? null : rawFields[_unlockColumn];

  String? localizedName(GameTextCatalog texts) {
    if (nameTextId < 0) return null;
    return originalText(texts, nameTextId);
  }
}

class CropDefinition extends CatalogItem {
  CropDefinition._(List<int> row) : super._(2, row, 19);

  /// cGame actor construction copies column 22 to s1.T2, the growth timer
  /// before the original z9(itemId) percentage modifier is applied.
  int get baseGrowthTimer => rawFields[22];

  /// cGame copies column 24 to s1.A2 (m_resourceGenerated).
  int get generatedProductIndex => rawFields[24];
}

class RecipeDefinition extends CatalogItem {
  RecipeDefinition._(List<int> row) : super._(7, row, 5);

  /// cGame.Bb assigns column 17 to Sk, the output row in product table 1.
  int get outputProductIndex => rawFields[17];

  /// cGame.Bb uses column 14 * 60 for its recipe countdown.
  int get durationSeconds => rawFields[14] * 60;
  int get firstIngredientProductIndex => rawFields[6];
  int get secondIngredientProductIndex => rawFields[9];
}

/// Mission records are table 6. Individual objective/reward columns remain
/// indexed until their handling routines are ported; no quest rules are guessed.
class MissionDefinition {
  MissionDefinition._(this.rawFields);
  final List<int> rawFields;
  int get index => rawFields[0];
  int get id => rawFields[1];
}

/// p.O is 10; GLLib.y7 splits a string id into group and low ten bits.
String originalText(GameTextCatalog texts, int id) {
  if (id < 0) throw RangeError.value(id, 'id');
  return texts.get(id >>> 10, id & 1023);
}
