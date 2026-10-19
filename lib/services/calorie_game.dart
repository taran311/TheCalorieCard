import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/calorie_sense.dart';
import 'package:namer_app/services/chat_service.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/services/game_foods_tables.dart';
import 'package:namer_app/services/games_service.dart';
import 'package:namer_app/services/proxy_client.dart';
import 'package:namer_app/services/statement_service.dart';

/// One food in Guess the Calories, with its real calories.
///
/// Values are from the brand's UK label, or USDA / UK reference data for
/// unbranded food, rounded to the nearest calorie.
class GameFood {
  final String emoji;
  final String name;
  final String portion;
  final int kcal;

  const GameFood(this.emoji, this.name, this.portion, this.kcal);

  Map<String, dynamic> toMap() =>
      {'emoji': emoji, 'name': name, 'portion': portion, 'kcal': kcal};

  static GameFood fromMap(dynamic m) {
    final map = m is Map ? m : const {};
    return GameFood(
      '${map['emoji'] ?? '🍽️'}',
      '${map['name'] ?? 'Mystery food'}',
      '${map['portion'] ?? ''}',
      (BalanceService.number(map['kcal']) ?? 0).round(),
    );
  }
}

/// The hand-picked foods, with everyday portions people know ("1 medium",
/// "a handful"). All vegan: the app doesn't feature animal products in its
/// own content. (Guess what I ate uses the foods people logged themselves.)
const List<GameFood> kPickedGameFoods = [
  // Fruit
  GameFood('🍌', 'Banana', '1 medium (118g)', 105),
  GameFood('🍎', 'Apple', '1 medium (182g)', 95),
  GameFood('🍐', 'Pear', '1 medium (178g)', 101),
  GameFood('🍊', 'Orange', '1 medium (131g)', 62),
  GameFood('🍊', 'Satsuma', '1 (70g)', 37),
  GameFood('🍇', 'Grapes', 'A handful (80g)', 53),
  GameFood('🍓', 'Strawberries', 'A handful (80g)', 26),
  GameFood('🫐', 'Blueberries', 'A handful (80g)', 46),
  GameFood('🍓', 'Raspberries', 'A handful (80g)', 42),
  GameFood('🍒', 'Cherries', 'A handful (80g)', 50),
  GameFood('🥭', 'Mango', '1 whole (200g of flesh)', 120),
  GameFood('🍍', 'Pineapple', '80g', 40),
  GameFood('🍉', 'Watermelon', 'A big slice (280g)', 84),
  GameFood('🥝', 'Kiwi', '1 (69g)', 42),
  GameFood('🍑', 'Peach', '1 medium (150g)', 59),
  GameFood('🌴', 'Medjool date', '1 date (24g)', 66),
  GameFood('🍇', 'Raisins', '1 mini box (14g)', 42),
  GameFood('🥑', 'Avocado', 'Half (68g)', 114),
  // Veg
  GameFood('🥕', 'Carrot', '1 medium (61g)', 25),
  GameFood('🥦', 'Broccoli', '80g', 27),
  GameFood('🍅', 'Cherry tomatoes', '80g', 14),
  GameFood('🥒', 'Cucumber', 'A third (100g)', 15),
  GameFood('🫑', 'Red pepper', '1 whole (119g)', 37),
  GameFood('🥬', 'Spinach', 'A big handful (80g)', 18),
  GameFood('🍄', 'Mushrooms', '80g, raw', 18),
  GameFood('🥬', 'Iceberg lettuce', 'A quarter (135g)', 19),
  GameFood('🥬', 'Brussels sprouts', '80g, boiled', 29),
  GameFood('🫛', 'Edamame', '80g, shelled', 97),
  GameFood('🫒', 'Green olives', '30g (about 8)', 44),
  GameFood('🍠', 'Sweet potato', '200g, baked', 180),
  GameFood('🥔', 'Baked potato', '200g, plain', 186),
  // Breakfast and bread
  GameFood('🥣', 'Porridge oats', '40g, made with water', 150),
  GameFood('🥣', 'Weetabix', '2 biscuits', 136),
  GameFood('🍞', 'White bread', '1 medium slice (36g)', 85),
  GameFood('🍞', 'Wholemeal bread', '1 slice (40g)', 91),
  GameFood('🍞', 'Sourdough', '1 large slice (50g)', 120),
  GameFood('🫓', 'Crumpet', '1 (55g)', 88),
  GameFood('🫓', 'White pitta', '1 (60g)', 160),
  GameFood('🌯', 'Large tortilla wrap', '1 (62g)', 190),
  GameFood('🫙', 'Marmite', 'A thin scrape (4g)', 10),
  GameFood('🍓', 'Strawberry jam', '1 tablespoon', 38),
  GameFood('🍁', 'Maple syrup', '1 tablespoon', 52),
  GameFood('🥜', 'Peanut butter', '1 tablespoon (16g)', 94),
  GameFood('🧈', 'Plant butter', '10g (a thin spread)', 71),
  // Staples and protein
  GameFood('🍚', 'White rice', '150g cooked', 195),
  GameFood('🍚', 'Brown rice', '150g cooked', 185),
  GameFood('🍝', 'Spaghetti', '200g cooked', 316),
  GameFood('🍜', 'Rice noodles', '150g cooked', 162),
  GameFood('🥣', 'Couscous', '150g cooked', 168),
  GameFood('🌾', 'Quinoa', '150g cooked', 180),
  GameFood('🧊', 'Firm tofu', '100g', 144),
  GameFood('🟫', 'Tempeh', '100g', 192),
  GameFood('🫘', 'Chickpeas', 'Half a tin (120g drained)', 167),
  GameFood('🫘', 'Kidney beans', 'Half a tin (120g drained)', 125),
  GameFood('🫘', 'Cooked lentils', '150g', 174),
  GameFood('🫘', 'Baked beans', 'Half a can (207g)', 164),
  GameFood('🧆', 'Falafel', '3 (about 50g)', 167),
  GameFood('🫘', 'Hummus', '2 tablespoons (30g)', 90),
  // Nuts, seeds and oils
  GameFood('🌰', 'Almonds', '30g', 174),
  GameFood('🌰', 'Cashews', '30g', 166),
  GameFood('🌰', 'Walnuts', '30g', 196),
  GameFood('🌰', 'Pistachios', '30g, shelled', 168),
  GameFood('🌰', 'Brazil nuts', '3 nuts (15g)', 99),
  GameFood('🥜', 'Salted peanuts', '1 bag (50g)', 305),
  GameFood('🌱', 'Chia seeds', '1 tablespoon (12g)', 58),
  GameFood('🫙', 'Tahini', '1 tablespoon (15g)', 89),
  GameFood('🫒', 'Olive oil', '1 tablespoon', 119),
  // Plant milks and soft drinks
  GameFood('🥛', 'Oat milk', '200ml', 92),
  GameFood('🥛', 'Unsweetened soya milk', '200ml', 66),
  GameFood('🥛', 'Unsweetened almond milk', '200ml', 26),
  GameFood('🥥', 'Coconut water', '330ml', 59),
  GameFood('🍊', 'Orange juice', '200ml', 90),
  GameFood('☕', 'Black coffee', 'A mug (250ml)', 2),
  GameFood('🥤', 'Coca-Cola', '1 can (330ml)', 139),
  GameFood('🥤', 'Diet Coke', '1 can (330ml)', 1),
  GameFood('🥤', 'Fanta Orange', '1 can (330ml)', 63),
  // Snacks and sweets
  GameFood('🍪', 'McVitie\'s Digestive', '1 biscuit', 71),
  GameFood('🍪', 'Lotus Biscoff', '1 biscuit', 30),
  GameFood('🍪', 'Oreo', '1 biscuit', 53),
  GameFood('🍫', 'Dark chocolate (70%)', '4 squares (20g)', 120),
  GameFood('🍬', 'Skittles', '1 bag (45g)', 179),
  GameFood('🥔', 'Walkers Ready Salted', '1 bag (32.5g)', 171),
  GameFood('🥔', 'Pringles Original', 'About 13 crisps (30g)', 160),
  GameFood('🌽', 'Tortilla chips', '30g', 150),
  GameFood('🍅', 'Salsa', '2 tablespoons', 10),
  GameFood('🍘', 'Rice cake', '1 plain', 31),
  GameFood('🍿', 'Popcorn', '20g, air-popped', 77),
  // Out and about
  GameFood('🍔', 'McDonald\'s McPlant', '1 burger', 429),
  GameFood('🍟', 'McDonald\'s fries', '1 medium portion', 337),
  GameFood('🌱', 'Greggs vegan sausage roll', '1 roll', 312),
  // Drinks
  GameFood('🍺', 'Lager (4%)', '1 pint', 182),
  GameFood('🍺', 'Guinness', '1 pint', 210),
  GameFood('🍷', 'Red wine', '1 medium glass (175ml)', 159),
  GameFood('🥂', 'White wine', '1 medium glass (175ml)', 144),
  GameFood('🥂', 'Prosecco', '1 glass (125ml)', 86),
  GameFood('🍸', 'Gin and slimline tonic', '1 single (25ml gin)', 57),
  // More fruit
  GameFood('🍑', 'Apricot', '1 (35g)', 17),
  GameFood('🫐', 'Plum', '1 (66g)', 30),
  GameFood('🍑', 'Nectarine', '1 medium (142g)', 62),
  GameFood('🍊', 'Clementine', '1 (74g)', 35),
  GameFood('🍊', 'Grapefruit', 'Half (123g)', 52),
  GameFood('🍎', 'Pomegranate seeds', 'Half a pot (80g)', 66),
  GameFood('🥭', 'Papaya', 'A slice (140g)', 60),
  GameFood('🍈', 'Cantaloupe melon', 'A slice (160g)', 54),
  GameFood('🍈', 'Honeydew melon', 'A slice (160g)', 58),
  GameFood('🟣', 'Fresh fig', '1 (50g)', 37),
  GameFood('🍑', 'Dried apricots', '5 (35g)', 84),
  GameFood('🟤', 'Prunes', '5 (40g)', 96),
  GameFood('🔴', 'Dried cranberries', '30g', 92),
  GameFood('🍌', 'Banana chips', '30g', 156),
  GameFood('🫐', 'Blackberries', 'A handful (80g)', 34),
  GameFood('⚪', 'Lychees', '10 (100g)', 66),
  GameFood('🟣', 'Passion fruit', '1 (18g of pulp)', 17),
  GameFood('🍐', 'Guava', '1 (55g)', 37),
  GameFood('🥥', 'Fresh coconut', 'A 30g piece', 106),
  GameFood('🥥', 'Desiccated coconut', '15g', 99),
  GameFood('🍌', 'Plantain', 'Half, boiled (100g)', 116),
  GameFood('🫐', 'Blackcurrants', '80g', 50),
  GameFood('🍌', 'Large banana', '1 large (136g)', 121),
  GameFood('🍏', 'Small apple', '1 small (149g)', 77),
  GameFood('⭐', 'Star fruit', '1 (91g)', 28),
  GameFood('🟠', 'Persimmon', '1 (168g)', 118),
  GameFood('🟡', 'Jackfruit', '100g', 95),
  GameFood('🟢', 'Durian', '100g', 147),
  GameFood('🍇', 'Grapes', 'A bunch (150g)', 104),
  GameFood('🍓', 'Strawberries', 'A punnet (227g)', 73),
  GameFood('🍉', 'Watermelon', 'A whole quarter (1kg)', 300),
  // More veg
  GameFood('🥦', 'Cauliflower', '80g', 20),
  GameFood('🥬', 'White cabbage', '80g', 20),
  GameFood('🟣', 'Red cabbage', '80g', 25),
  GameFood('🫛', 'Green beans', '80g', 25),
  GameFood('🟢', 'Garden peas', '80g, boiled', 62),
  GameFood('🌽', 'Sweetcorn', '80g, tinned', 65),
  GameFood('🌽', 'Corn on the cob', '1 cob (100g of kernels)', 96),
  GameFood('🥒', 'Courgette', '1 medium (196g)', 33),
  GameFood('🍆', 'Aubergine', 'Half (150g)', 38),
  GameFood('🌿', 'Asparagus', '5 spears (80g)', 16),
  GameFood('🥬', 'Celery', '2 sticks (80g)', 13),
  GameFood('🟣', 'Beetroot', '80g, cooked', 35),
  GameFood('🎃', 'Butternut squash', '150g, roasted', 60),
  GameFood('🧅', 'Onion', '1 medium (110g)', 44),
  GameFood('🧄', 'Garlic', '1 clove (3g)', 4),
  GameFood('🥬', 'Leek', '1 (89g)', 54),
  GameFood('🥕', 'Parsnip', '80g, boiled', 57),
  GameFood('🥬', 'Rocket', 'A handful (20g)', 5),
  GameFood('🥬', 'Pak choi', '100g', 13),
  GameFood('🌱', 'Beansprouts', '80g', 24),
  GameFood('🍅', 'Tomato', '1 medium (123g)', 22),
  GameFood('🧅', 'Spring onions', '3 (45g)', 14),
  GameFood('🫛', 'Mangetout', '80g', 34),
  GameFood('🫛', 'Sugar snap peas', '80g', 34),
  GameFood('🟢', 'Okra', '80g', 26),
  GameFood('🟣', 'Turnip', '80g', 22),
  GameFood('🥬', 'Watercress', 'A handful (30g)', 3),
  GameFood('🥑', 'Avocado', '1 whole (136g)', 218),
  GameFood('🥔', 'New potatoes', '5 small, boiled (175g)', 150),
  GameFood('🟤', 'Yam', '150g, boiled', 174),
  GameFood('🌿', 'Fennel', 'Half a bulb (115g)', 36),
  GameFood('🔴', 'Radishes', '5 (25g)', 4),
  GameFood('🥬', 'Sauerkraut', '2 tablespoons (30g)', 6),
  GameFood('🫑', 'Green pepper', '1 whole (119g)', 24),
  GameFood('🍄', 'Mushrooms', 'A whole pack (250g)', 55),
  GameFood('🥕', 'Carrot sticks', 'A big bag (300g)', 123),
  // More grains, bread and cereal
  GameFood('🍝', 'Dry spaghetti', '75g (before cooking)', 278),
  GameFood('🍝', 'Penne', '200g cooked', 316),
  GameFood('🍚', 'Basmati rice', '75g (before cooking)', 274),
  GameFood('🍝', 'Wholewheat pasta', '200g cooked', 298),
  GameFood('🌾', 'Bulgur wheat', '150g cooked', 124),
  GameFood('🌾', 'Pearl barley', '150g cooked', 184),
  GameFood('🥣', 'Cornflakes', '30g, dry', 113),
  GameFood('🥣', 'Bran flakes', '30g, dry', 107),
  GameFood('🥣', 'Muesli (no added sugar)', '45g, dry', 161),
  GameFood('🥣', 'Granola', '45g, dry', 202),
  GameFood('🥯', 'Plain bagel', '1 (85g)', 220),
  GameFood('🥖', 'Baguette', 'A 60g piece', 163),
  GameFood('🍘', 'Rye crispbread', '1 (10g)', 35),
  GameFood('🍪', 'Oatcake', '1 (11g)', 48),
  GameFood('🥨', 'Pretzels', '30g', 114),
  GameFood('🥖', 'Breadstick', '1 (5g)', 20),
  GameFood('🍚', 'White rice', 'A big plate (300g cooked)', 390),
  GameFood('🍚', 'Microwave rice pouch', 'A whole pouch (250g)', 350),
  GameFood('🥣', 'Porridge oats', '80g, made with water', 300),
  // More protein
  GameFood('🫘', 'Black beans', 'Half a tin (120g drained)', 158),
  GameFood('🫘', 'Butter beans', 'Half a tin (120g drained)', 92),
  GameFood('🧊', 'Silken tofu', '100g', 55),
  GameFood('🧊', 'Firm tofu', 'A whole block (280g)', 403),
  GameFood('🫘', 'Chickpeas', 'A whole tin (240g drained)', 334),
  GameFood('🫘', 'Baked beans', 'A whole can (415g)', 328),
  GameFood('🫛', 'Edamame', 'A big bowl (200g, shelled)', 242),
  // More nuts and seeds
  GameFood('🌰', 'Hazelnuts', '30g', 188),
  GameFood('🌰', 'Macadamias', '30g', 215),
  GameFood('🌰', 'Pecans', '30g', 207),
  GameFood('🎃', 'Pumpkin seeds', '30g', 168),
  GameFood('🌻', 'Sunflower seeds', '30g', 175),
  GameFood('🌱', 'Ground flaxseed', '1 tablespoon (10g)', 53),
  GameFood('⚪', 'Sesame seeds', '1 tablespoon (9g)', 52),
  GameFood('🥜', 'Almond butter', '1 tablespoon (16g)', 98),
  GameFood('🌰', 'Mixed nuts', '30g', 182),
  GameFood('🌲', 'Pine nuts', '1 tablespoon (10g)', 67),
  GameFood('🌰', 'Almonds', 'A big handful (50g)', 290),
  GameFood('🥜', 'Peanut butter', 'A heaped spoon (30g)', 176),
  // Sauces, spreads and sweeteners
  GameFood('🍅', 'Tomato ketchup', '1 tablespoon (17g)', 17),
  GameFood('🥢', 'Soy sauce', '1 tablespoon (16g)', 8),
  GameFood('🌶️', 'Sweet chilli sauce', '1 tablespoon (15g)', 32),
  GameFood('🔥', 'BBQ sauce', '1 tablespoon (17g)', 29),
  GameFood('🍯', 'Agave syrup', '1 tablespoon (21g)', 65),
  GameFood('🍯', 'Golden syrup', '1 tablespoon (20g)', 65),
  GameFood('🥑', 'Guacamole', '2 tablespoons (30g)', 46),
  GameFood('🥥', 'Coconut milk (tinned)', '100ml', 197),
  GameFood('🫙', 'Balsamic vinegar', '1 tablespoon (16g)', 14),
  GameFood('🍪', 'Biscoff spread', '1 tablespoon (15g)', 88),
  GameFood('🍚', 'Sugar', '1 teaspoon (4g)', 16),
  GameFood('🫒', 'Olive oil', 'A glug (3 tablespoons)', 354),
  // More drinks
  GameFood('🧃', 'Apple juice', '200ml', 92),
  GameFood('⚡', 'Red Bull', '1 can (250ml)', 112),
  GameFood('🍸', 'Vodka and diet cola', '1 single (25ml vodka)', 56),
  GameFood('🥃', 'Whisky', '1 single (25ml)', 56),
  GameFood('🍹', 'Rum and Coke', '25ml rum, 150ml Coke', 119),
  GameFood('🥤', 'Pepsi Max', '1 can (330ml)', 1),
  GameFood('🍵', 'Black tea', 'A mug', 2),
  GameFood('🍵', 'Tea with oat milk', 'A mug, with a splash', 16),
  GameFood('🥛', 'Oat milk', 'A pint (568ml)', 261),
  GameFood('🍷', 'Red wine', 'A large glass (250ml)', 227),
  GameFood('🍷', 'Red wine', 'A whole bottle (750ml)', 680),
  GameFood('🥂', 'Prosecco', 'A whole bottle (750ml)', 516),
  GameFood('🍺', 'Lager (4%)', '4 pints', 728),
  // More snacks and treats
  GameFood('🥨', 'Bombay mix', '30g', 151),
  GameFood('🍫', 'Nakd Cocoa Delight', '1 bar (35g)', 138),
  GameFood('🍪', 'Oreo', 'A row of 5', 265),
  GameFood('🍪', 'Lotus Biscoff', 'A pack of 2', 60),
  GameFood('🍫', 'Dark chocolate (70%)', 'A whole 100g bar', 600),
  GameFood('🥔', 'Pringles Original', 'A whole tube (165g)', 880),
  GameFood('🍿', 'Popcorn', 'A big bowl (60g, air-popped)', 232),
  GameFood('🌽', 'Tortilla chips', 'A whole sharing bag (200g)', 1000),
  // Simple plates
  GameFood('🍞', 'Peanut butter on toast', '1 slice wholemeal, 1 tbsp peanut butter', 185),
  GameFood('🍞', 'Beans on toast', 'Half a can on 1 slice of white', 249),
  GameFood('🥑', 'Avocado on sourdough', 'Half an avocado, 1 large slice', 234),
  GameFood('🥣', 'Porridge with banana', '40g oats (water), 1 medium banana', 255),
  GameFood('🥕', 'Hummus and carrot sticks', '2 tbsp hummus, 1 carrot', 115),
  GameFood('🍓', 'Jam on toast', '1 slice white, 1 tbsp jam', 123),
  GameFood('🫙', 'Marmite on toast', '1 slice white, no butter', 95),
  GameFood('🍎', 'Apple and peanut butter', '1 apple, 1 tbsp peanut butter', 189),
  GameFood('🍚', 'Rice and black beans', '150g rice, half a tin of beans', 353),
  GameFood('🧊', 'Tofu stir-fry', '100g tofu, 80g broccoli, 150g rice noodles', 333),
  GameFood('🍝', 'Spaghetti with tomato sauce', '200g pasta, 150g tomato sauce', 386),
  GameFood('🥣', 'Weetabix with oat milk', '2 biscuits, 150ml oat milk', 205),
];

/// Everything games are dealt from: the hand-picked foods, then every
/// plant food in the UK food tables (generated, see game_foods_tables.dart),
/// so the same foods come round far less often.
const List<GameFood> kGameFoods = [...kPickedGameFoods, ...kTableGameFoods];

enum GameStatus { active, finished }

/// The two kinds of game. A game saved without a `mode` is [classic].
enum GameMode {
  /// "Mystery foods": both players guess the same foods, dealt from
  /// [kGameFoods].
  classic,

  /// "Guess what I ate": each player picks 5 foods they've eaten, and
  /// guesses the other player's. No longer offered for new games (people's
  /// own meals made it awkward), but games already started still play.
  swap,

  /// Higher or Lower: the same pairs for both players; pick the one with
  /// more calories. Saved as `higherLower`.
  higherLower;

  /// The kinds a new game can be.
  static const offered = [GameMode.classic, GameMode.higherLower];

  String get emoji => switch (this) {
        GameMode.classic => '🎲',
        GameMode.swap => '🍽️',
        GameMode.higherLower => '⚖️',
      };

  String get title => switch (this) {
        GameMode.classic => 'Mystery foods',
        GameMode.swap => 'Guess what I ate',
        GameMode.higherLower => 'Higher or Lower',
      };

  static GameMode fromName(Object? name) => switch (name) {
        'swap' => GameMode.swap,
        'higherLower' => GameMode.higherLower,
        _ => GameMode.classic,
      };

  /// "🎲 Mystery foods", for chips and list tiles.
  String get label => '$emoji $title';
}

/// A game of Guess the Calories between two friends, stored in
/// `calorie_games/{id}`:
///   player_ids: [a, b]        names: {a: 'sam', b: 'taz'}
///   mode: 'classic' | 'swap' | 'higherLower'  (missing means classic)
///   foods: [{emoji, name, portion, kcal}, ...]   (classic: the 5 dealt;
///          higherLower: the pairs, two foods each, in order)
///   picks: {a: [5 foods], b: null}               (swap: each player's own)
///   guesses: {a: [250, 90], b: []}     (one per food, in order; in a swap
///                                       game, for the OTHER player's picks;
///                                       higherLower: 0 or 1 per pair, the
///                                       one picked as having more)
///   status: 'active' | 'finished'      winner: uid | 'draw' | null
///   expires_at: 7 days after the last move    expired: true if it ran out
class CalorieGame {
  final String id;
  final List<String> playerIds;
  final Map<String, String> names;
  final String createdBy;
  final GameMode mode;
  final List<GameFood> foods;

  /// Swap games only: each player's 5 foods, null until they've picked.
  final Map<String, List<GameFood>?> picks;
  final Map<String, List<int>> guesses;
  final GameStatus status;
  final String? winner;

  /// Finished because nobody moved for [CalorieGameService.lifetime].
  final bool expired;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? expiresAt;

  /// Players who've had their Games XP for this game (see GamesService).
  final List<String> xpClaimed;

  const CalorieGame({
    required this.id,
    required this.playerIds,
    required this.names,
    required this.createdBy,
    this.mode = GameMode.classic,
    required this.foods,
    this.picks = const {},
    required this.guesses,
    required this.status,
    required this.winner,
    this.expired = false,
    this.createdAt,
    required this.updatedAt,
    this.expiresAt,
    this.xpClaimed = const [],
  });

  /// The same game with some fields changed (after a move is saved).
  CalorieGame _copy({
    Map<String, List<GameFood>?>? picks,
    Map<String, List<int>>? guesses,
    GameStatus? status,
    String? winner,
    bool? expired,
  }) =>
      CalorieGame(
        id: id,
        playerIds: playerIds,
        names: names,
        createdBy: createdBy,
        mode: mode,
        foods: foods,
        picks: picks ?? this.picks,
        guesses: guesses ?? this.guesses,
        status: status ?? this.status,
        winner: winner ?? this.winner,
        expired: expired ?? this.expired,
        createdAt: createdAt,
        updatedAt: updatedAt,
        expiresAt: expiresAt,
        xpClaimed: xpClaimed,
      );

  bool get isFinished => status == GameStatus.finished;
  bool get isDraw => winner == CalorieGameService.draw;
  bool get isSwap => mode == GameMode.swap;
  bool get isHigherLower => mode == GameMode.higherLower;

  /// Higher or Lower: how many pairs, and pair [i].
  int get pairCount => foods.length ~/ 2;
  HlPair pairAt(int i) {
    HlFood side(GameFood f) => HlFood(f.emoji, f.name, f.portion, f.kcal);
    final a = side(foods[2 * i]), b = side(foods[2 * i + 1]);
    return HlPair(a, b, why: GamesService.surpriseWhy(a, b));
  }

  /// Higher or Lower: whether [pick] (0 or 1) is the one with more in
  /// pair [i].
  bool pickRight(int i, int pick) {
    final p = pairAt(i);
    return identical(pick == 0 ? p.a : p.b, p.higher);
  }

  /// Higher or Lower: how many [uid] got right.
  int correctOf(String uid) =>
      roundScoresOf(uid).where((s) => s > 0).length;

  /// The score to show: points, or in Higher or Lower how many right.
  int shownScoreOf(String uid) =>
      isHigherLower ? correctOf(uid) : scoreOf(uid);

  /// The most [shownScoreOf] can be.
  int get shownMax => isHigherLower ? pairCount : maxScore;

  String opponentOf(String uid) =>
      playerIds.firstWhere((p) => p != uid, orElse: () => '');

  String nameOf(String uid) => names[uid] ?? 'Your friend';

  List<int> guessesOf(String uid) => guesses[uid] ?? const [];

  /// The foods [uid] has to guess: the dealt foods in a classic game, the
  /// other player's picks in a swap game (empty until they've picked).
  /// Everything about a player's guesses goes through this.
  List<GameFood> foodsFor(String uid) =>
      isSwap ? (picks[opponentOf(uid)] ?? const []) : foods;

  /// The foods [uid] picked for the other player (swap games).
  List<GameFood> picksOf(String uid) => picks[uid] ?? const [];

  /// Whether [uid] has chosen their foods (always true in a classic game).
  bool hasPicked(String uid) => !isSwap || picks[uid] != null;

  /// A swap game still waiting for [uid] to pick their 5 foods.
  bool needsPickFrom(String uid) => isSwap && picks[uid] == null;

  /// Both players have foods to guess, so guessing can start.
  bool get ready => playerIds.every(hasPicked);

  /// How many foods [uid] guesses in all: 5 in either mode (a classic game
  /// counts its dealt foods, as it always has).
  int totalFor(String uid) => isSwap
      ? CalorieGameService.rounds
      : isHigherLower
          ? pairCount
          : foods.length;

  /// How many foods [uid] has guessed.
  int progressOf(String uid) => min(guessesOf(uid).length, totalFor(uid));

  bool doneBy(String uid) => progressOf(uid) >= totalFor(uid);

  /// The index (into [foodsFor]) of the next food [uid] has to guess, or
  /// null when they're done or can't guess yet (a swap game where someone
  /// hasn't picked).
  int? nextFoodFor(String uid) {
    if (doneBy(uid) || !ready) return null;
    final i = progressOf(uid);
    return i < (isHigherLower ? pairCount : foodsFor(uid).length) ? i : null;
  }

  /// Whether the game is waiting on [uid]: to pick their foods, or to
  /// guess.
  bool isTurnOf(String uid) =>
      !isFinished && (needsPickFrom(uid) || (ready && !doneBy(uid)));

  /// 0-100 for each food [uid] has guessed so far (Higher or Lower: 100
  /// for each pair right, 0 wrong).
  List<int> roundScoresOf(String uid) {
    final g = guessesOf(uid);
    if (isHigherLower) {
      return [
        for (var i = 0; i < min(g.length, pairCount); i++)
          pickRight(i, g[i]) ? 100 : 0
      ];
    }
    final f = foodsFor(uid);
    return [
      for (var i = 0; i < min(g.length, f.length); i++)
        CalorieSense.score(g[i].toDouble(), f[i].kcal.toDouble())
    ];
  }

  int scoreOf(String uid) => roundScoresOf(uid).fold(0, (a, b) => a + b);

  int get maxScore => totalFor('') * 100;

  /// When the game ends if nobody moves: [expiresAt], or for games saved
  /// before that existed, [CalorieGameService.lifetime] after the last
  /// move. Null only while a brand-new game's server time is pending.
  DateTime? get endsAt {
    final saved = expiresAt;
    if (saved != null) return saved;
    final last = updatedAt ?? createdAt;
    return last?.add(CalorieGameService.lifetime);
  }

  /// Still open, but nobody has moved in time: it should be ended
  /// ([CalorieGameService.expireIfStale]).
  bool isStaleAt(DateTime now) {
    final end = endsAt;
    return !isFinished && end != null && now.isAfter(end);
  }

  factory CalorieGame.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final rawNames = d['names'];
    final rawGuesses = d['guesses'];
    final rawPicks = d['picks'];
    final created = d['created_at'];
    final updated = d['updated_at'];
    final expires = d['expires_at'];
    return CalorieGame(
      id: doc.id,
      playerIds: [for (final p in (d['player_ids'] as List? ?? const [])) '$p'],
      names: {
        if (rawNames is Map)
          for (final e in rawNames.entries) '${e.key}': '${e.value}'
      },
      createdBy: '${d['created_by'] ?? ''}',
      mode: GameMode.fromName(d['mode']),
      foods: [
        for (final f in (d['foods'] as List? ?? const [])) GameFood.fromMap(f)
      ],
      picks: {
        if (rawPicks is Map)
          for (final e in rawPicks.entries)
            '${e.key}': e.value is List
                ? [for (final f in e.value as List) GameFood.fromMap(f)]
                : null
      },
      guesses: {
        if (rawGuesses is Map)
          for (final e in rawGuesses.entries)
            '${e.key}': [
              for (final g in (e.value is List ? e.value as List : const []))
                (BalanceService.number(g) ?? 0).round()
            ]
      },
      status: d['status'] == 'finished' ? GameStatus.finished : GameStatus.active,
      winner: d['winner'] as String?,
      expired: d['expired'] == true,
      createdAt: created is Timestamp ? created.toDate() : null,
      updatedAt: updated is Timestamp ? updated.toDate() : null,
      expiresAt: expires is Timestamp ? expires.toDate() : null,
      xpClaimed: [
        for (final p in (d['xp_claimed'] is List ? d['xp_claimed'] as List : const []))
          '$p'
      ],
    );
  }
}

/// Your head-to-head record against one friend.
class GameRecord {
  final int wins;
  final int losses;
  final int draws;

  const GameRecord(this.wins, this.losses, this.draws);

  int get played => wins + losses + draws;
}

class CalorieGameService {
  CalorieGameService._();

  static const rounds = 5;
  static const draw = 'draw';

  /// Pairs in a Higher or Lower game with a friend.
  static const hlPairs = 10;

  /// A Higher or Lower game's foods: [hlPairs] pairs, two foods each.
  static List<GameFood> dealPairs([Random? random]) => [
        for (final p in GamesService.dealHigherLower(
            random: random, pairs: hlPairs)) ...[
          GameFood(p.a.emoji, p.a.name, p.a.detail, p.a.kcal),
          GameFood(p.b.emoji, p.b.name, p.b.detail, p.b.kcal),
        ]
      ];

  /// A game ends this long after the last move, so none waits forever.
  static const lifetime = Duration(days: 7);

  static CollectionReference<Map<String, dynamic>> get _col =>
      BalanceService.db.collection('calorie_games');

  /// A new `expires_at`: [lifetime] from now.
  static Timestamp _expiry() =>
      Timestamp.fromDate(BalanceService.now().add(lifetime));

  /// [rounds] different foods, at random.
  static List<GameFood> deal([Random? random]) {
    final pool = [...kGameFoods]..shuffle(random ?? Random());
    return pool.take(rounds).toList();
  }

  /// Starts a game with [friendId] and lets them know in your chat. A
  /// [GameMode.swap] game needs your [picks] (exactly [rounds] foods) up
  /// front, so a half-made game never exists.
  static Future<String> create({
    required String uid,
    required String myName,
    required String friendId,
    required String friendName,
    GameMode mode = GameMode.classic,
    List<GameFood>? picks,
    Random? random,
    bool notify = true,
  }) async {
    if (friendId.isEmpty || friendId == uid) {
      throw ArgumentError('Pick a friend to play');
    }
    final swap = mode == GameMode.swap;
    final hl = mode == GameMode.higherLower;
    if (swap && (picks == null || picks.length != rounds)) {
      throw ArgumentError('Pick $rounds foods first');
    }
    final ref = await _col.add({
      'mode': mode.name,
      'player_ids': [uid, friendId],
      'names': {uid: myName, friendId: friendName},
      'created_by': uid,
      'foods': swap
          ? <Map<String, dynamic>>[]
          : [for (final f in hl ? dealPairs(random) : deal(random)) f.toMap()],
      if (swap)
        'picks': {
          uid: [for (final f in picks!) f.toMap()],
          friendId: null,
        },
      'guesses': {uid: <int>[], friendId: <int>[]},
      'status': 'active',
      'winner': null,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
      'expires_at': _expiry(),
    });
    if (notify) {
      await _tell(
          uid,
          myName,
          friendId,
          friendName,
          swap
              ? "🍽️ Guess what I ate! Pick 5 foods you've eaten and guess "
                  'mine. Tap to play.'
              : hl
                  ? "⚖️ I've challenged you to Higher or Lower! $hlPairs "
                      'pairs: which has more calories? Tap to play.'
                  : "🎯 I've challenged you to Guess the Calories (mystery "
                      'foods)! Tap to play.',
          gameId: ref.id);
      unawaited(notifyOpponent(ref.id));
    }
    return ref.id;
  }

  /// Live updates for one game.
  static Stream<CalorieGame?> watch(String id) => _col
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? CalorieGame.fromDoc(d) : null);

  /// Your games: ones waiting for you first, then ones waiting for your
  /// friend, then finished ones (newest first).
  static Stream<List<CalorieGame>> forUser(String uid) => _col
      .where('player_ids', arrayContains: uid)
      .snapshots()
      .map((snap) => sortForUser(
          uid, [for (final d in snap.docs) CalorieGame.fromDoc(d)]));

  static List<CalorieGame> sortForUser(String uid, List<CalorieGame> games) {
    final now = BalanceService.now();
    // A stale game counts as finished: it's about to be ended.
    int group(CalorieGame g) => g.isFinished || g.isStaleAt(now)
        ? 2
        : (g.isTurnOf(uid) ? 0 : 1);
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    return [...games]..sort((a, b) {
        final byGroup = group(a).compareTo(group(b));
        if (byGroup != 0) return byGroup;
        return (b.updatedAt ?? epoch).compareTo(a.updatedAt ?? epoch);
      });
  }

  /// Games waiting for [uid] to move (pick their foods or guess).
  static int waitingOn(String uid, List<CalorieGame> games) {
    final now = BalanceService.now();
    return games.where((g) => g.isTurnOf(uid) && !g.isStaleAt(now)).length;
  }

  /// Saves [uid]'s 5 foods in a swap game (the friend's side; the
  /// challenger picks before [create]). Only once: a second pick is
  /// ignored. Returns the updated game.
  static Future<CalorieGame> pick(
    String gameId,
    String uid,
    List<GameFood> foods, {
    bool notify = true,
  }) async {
    if (foods.length != rounds) {
      throw ArgumentError('Pick exactly $rounds foods');
    }
    final ref = _col.doc(gameId);
    late CalorieGame after;
    var picked = false;
    // Why the pick was refused. Thrown after the transaction, so the error
    // arrives as itself rather than wrapped by the Firestore plugin.
    String? refused;
    await BalanceService.db.runTransaction<void>((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        refused = 'This game has ended or was cancelled';
        return;
      }
      final game = CalorieGame.fromDoc(snap);
      if (!game.playerIds.contains(uid)) {
        refused = 'Not your game';
      } else if (!game.isSwap) {
        refused = 'This game uses mystery foods';
      } else if (game.isFinished || game.isStaleAt(BalanceService.now())) {
        refused = 'This game has ended';
      }
      if (refused != null) return;
      if (!game.needsPickFrom(uid)) {
        after = game;
        return;
      }
      after = game._copy(picks: {...game.picks, uid: [...foods]});
      picked = true;
      tx.update(ref, {
        'picks.$uid': [for (final f in foods) f.toMap()],
        'updated_at': FieldValue.serverTimestamp(),
        'expires_at': _expiry(),
      });
    });
    final why = refused;
    if (why != null) throw StateError(why);
    if (notify && picked) unawaited(notifyOpponent(gameId));
    return after;
  }

  /// Saves [uid]'s guess for their next food. When that's the last guess
  /// from both players, the game finishes and the winner is set.
  /// In a swap game both players must have picked first.
  /// Returns the updated game.
  static Future<CalorieGame> guess({
    required String gameId,
    required String uid,
    required int kcal,
    bool notify = true,
  }) async {
    final ref = _col.doc(gameId);
    late CalorieGame after;
    var finishedNow = false;
    var completedNow = false;
    // Why the guess was refused, thrown after the transaction (see [pick]).
    String? refused;
    await BalanceService.db.runTransaction<void>((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        refused = 'This game has been deleted';
        return;
      }
      final game = CalorieGame.fromDoc(snap);
      if (!game.playerIds.contains(uid)) {
        refused = 'Not your game';
        return;
      }
      if (game.isFinished || game.doneBy(uid)) {
        after = game;
        finishedNow = false;
        return;
      }
      if (game.isStaleAt(BalanceService.now())) {
        refused = 'This game has ended';
      } else if (game.needsPickFrom(uid)) {
        refused = 'Pick your foods first';
      } else if (!game.ready) {
        refused = 'Wait for ${game.nameOf(game.opponentOf(uid))} to pick';
      }
      if (refused != null) return;
      final mine = [...game.guessesOf(uid), max(0, kcal)];
      final guesses = {...game.guesses, uid: mine};
      after = game._copy(guesses: guesses);
      completedNow = after.doneBy(uid);
      final everyoneDone = game.playerIds.every(after.doneBy);
      final winner = everyoneDone ? winnerOf(after) : null;
      finishedNow = everyoneDone;
      if (everyoneDone) {
        after = after._copy(status: GameStatus.finished, winner: winner);
      }
      tx.update(ref, {
        'guesses.$uid': mine,
        'updated_at': FieldValue.serverTimestamp(),
        // "7 days since the last move".
        'expires_at': _expiry(),
        if (everyoneDone) ...{
          'status': 'finished',
          'winner': winner,
          'finished_at': FieldValue.serverTimestamp(),
        },
      });
    });
    final why = refused;
    if (why != null) throw StateError(why);

    // You finished it: tell your friend how it went.
    if (notify && finishedNow) {
      final other = after.opponentOf(uid);
      final hl = after.isHigherLower;
      final me = hl ? after.correctOf(uid) : after.scoreOf(uid);
      final them = hl ? after.correctOf(other) : after.scoreOf(other);
      final title = hl ? 'Higher or Lower' : 'Guess the Calories';
      final line = after.isDraw
          ? "🎯 $title: it's a draw, $me each!"
          : after.winner == uid
              ? '🏆 I won $title, $me to $them!'
              : '🏆 You won $title, $them to $me!';
      await _tell(uid, after.nameOf(uid), other, after.nameOf(other), line,
          gameId: after.id);
    }
    // You've guessed all 5 (or finished the game): the other player may
    // now be up, or the result is in.
    if (notify && completedNow) unawaited(notifyOpponent(gameId));
    return after;
  }

  /// The player with the higher total, or [draw].
  static String winnerOf(CalorieGame g) {
    if (g.playerIds.length < 2) return draw;
    final a = g.playerIds[0], b = g.playerIds[1];
    final sa = g.scoreOf(a), sb = g.scoreOf(b);
    if (sa == sb) return draw;
    return sa > sb ? a : b;
  }

  /// Who wins a game that ran out of time: the only player who finished
  /// all their guesses, or [draw] when neither did.
  static String expiredWinnerOf(CalorieGame g) {
    final done = [
      for (final p in g.playerIds)
        if (g.doneBy(p)) p
    ];
    return done.length == 1 ? done.first : draw;
  }

  /// Ends a game nobody has moved in for [lifetime], so no game waits
  /// forever. Either player's app calls this when it shows a stale game;
  /// it does nothing to a game that isn't stale (checked again inside the
  /// transaction). Never throws: returns the game as it now stands.
  static Future<CalorieGame> expireIfStale(CalorieGame game, String uid) async {
    if (!game.playerIds.contains(uid) ||
        !game.isStaleAt(BalanceService.now())) {
      return game;
    }
    final ref = _col.doc(game.id);
    var after = game;
    try {
      await BalanceService.db.runTransaction<void>((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return;
        final fresh = CalorieGame.fromDoc(snap);
        after = fresh;
        if (!fresh.isStaleAt(BalanceService.now())) return;
        final winner = expiredWinnerOf(fresh);
        after = fresh._copy(
            status: GameStatus.finished, winner: winner, expired: true);
        tx.update(ref, {
          'status': 'finished',
          'winner': winner,
          'expired': true,
          'finished_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        });
      });
    } catch (_) {
      return game;
    }
    return after;
  }

  /// Your wins, losses and draws against [friendId] in [games]. A game
  /// that ran out of time with nobody finished doesn't count at all.
  static GameRecord recordAgainst(
      String uid, String friendId, List<CalorieGame> games) {
    var w = 0, l = 0, d = 0;
    for (final g in games) {
      if (!g.isFinished || !g.playerIds.contains(friendId)) continue;
      if (!g.playerIds.contains(uid)) continue;
      if (g.expired && g.isDraw) continue;
      if (g.isDraw) {
        d++;
      } else if (g.winner == uid) {
        w++;
      } else {
        l++;
      }
    }
    return GameRecord(w, l, d);
  }

  /// A friendly "your turn" in your chat with the other player, plus a
  /// push if they've turned game notifications on.
  static Future<void> nudge(CalorieGame g, String uid) async {
    final other = g.opponentOf(uid);
    await _tell(
        uid,
        g.nameOf(uid),
        other,
        g.nameOf(other),
        g.needsPickFrom(other)
            ? '🍽️ Your turn in Guess the Calories: pick 5 foods for me '
                'to guess!'
            : g.isHigherLower
                ? '⚖️ Your turn in Higher or Lower!'
                : '🎯 Your turn in Guess the Calories!',
        gameId: g.id);
    unawaited(notifyOpponent(g.id, nudge: true));
  }

  /// Removes a game that hasn't finished (finished ones stay in the record).
  static Future<void> cancel(CalorieGame g) async {
    if (g.isFinished) return;
    await _col.doc(g.id).delete();
  }

  /// Chat message fields that make a game message a tappable card.
  static Map<String, dynamic> chatFields(String gameId) =>
      {'type': 'game', 'game_id': gameId};

  /// The body of `POST /notify/game`. The server reads the game, works
  /// out who's up and sends at most one push to the other player.
  static Map<String, dynamic> notifyBody(String gameId, {bool nudge = false}) =>
      {'gameId': gameId, 'event': nudge ? 'nudge' : 'update'};

  /// Sends a request to the server. Tests replace it so nothing goes over
  /// the network.
  static Future<void> Function(String path, Map<String, dynamic> body)
      notifier = _post;

  static Future<void> _post(String path, Map<String, dynamic> body) async {
    await ProxyClient.post(path, body).timeout(const Duration(seconds: 20));
  }

  /// Asks the server to tell the other player it's their turn (or that
  /// the result is in). Fire-and-forget: a push is a nice extra, so this
  /// never throws.
  static Future<void> notifyOpponent(String gameId, {bool nudge = false}) async {
    try {
      await notifier('/notify/game', notifyBody(gameId, nudge: nudge));
    } catch (_) {}
  }

  /// How far back "Guess what I ate" looks for your foods.
  static const pickDays = 30;

  /// Your foods from the last [pickDays] days to pick from in a swap game.
  static Future<List<GameFood>> loadPickable(String uid) async {
    final statement = await StatementService.load(uid,
        days: pickDays, withLogs: false);
    return pickableFoods(statement.recent);
  }

  /// Each food once (same name and portion), newest first, leaving out
  /// zero-calorie ones. Recipes show by their own name.
  static List<GameFood> pickableFoods(List<CardTransaction> txs) {
    const recipePrefix = 'Recipe:';
    final seen = <String>{};
    final out = <GameFood>[];
    final sorted = [...txs]..sort((a, b) => b.time.compareTo(a.time));
    for (final tx in sorted) {
      final kcal = tx.calories.round();
      if (kcal <= 0) continue;
      final raw = tx.description.trim();
      final recipe = raw.startsWith(recipePrefix);
      final name = (recipe ? raw.substring(recipePrefix.length) : raw).trim();
      if (name.isEmpty) continue;
      final portion = tx.portion.trim();
      if (!seen.add('${name.toLowerCase()}|${portion.toLowerCase()}')) continue;
      out.add(GameFood(
          recipe ? '📖' : mealEmoji(tx.category), name, portion, kcal));
    }
    return out;
  }

  /// The emoji a picked food gets, from the meal it was logged to.
  static String mealEmoji(String meal) {
    final m = FoodLog.mealOf(meal.trim().isEmpty ? null : meal)
        .trim()
        .toLowerCase();
    if (m == 'breakfast') return '🍳';
    if (m == 'lunch') return '🥪';
    if (m == 'dinner') return '🍝';
    if (m == 'snacks' || m == 'snack') return '🍪';
    return '🍽️';
  }

  /// Chat messages are a nice extra: the game works without them. They
  /// carry the game's id ([chatFields]) so the chat can open the game.
  static Future<void> _tell(String uid, String myName, String friendId,
      String friendName, String text,
      {required String gameId}) async {
    try {
      await ChatService.sendToFriend(
        uid: uid,
        myName: myName,
        friendId: friendId,
        friendName: friendName,
        text: text,
        extra: chatFields(gameId),
      );
    } catch (_) {}
  }
}
