// The tutorials, step by step. Each runs on a pretend card (see
// tutorial_mock.dart); none of them can touch real data.

import 'package:namer_app/services/coach_service.dart';
import 'package:namer_app/ui/tutorials/tutorial_mock.dart';
import 'package:namer_app/ui/tutorials/tutorial_player.dart';

const _wrap = MockFood('Falafel wrap', '1 wrap', 'Lunch', 380,
    protein: 14, carbs: 50, fat: 14);
const _apple = MockFood('Apple', '1 medium', 'Lunch', 72,
    protein: 0.4, carbs: 19, fat: 0.2);
const _tofu = MockFood('Scrambled tofu', '100g', 'Breakfast', 156,
    protein: 14, carbs: 3, fat: 10);
const _toast = MockFood('Wholemeal toast with vegan spread', '1 slice', 'Breakfast',
    128, protein: 4, carbs: 14, fat: 6);
// A mix of branded and plain foods, as people really type them.
const _biscoff = MockFood('Lotus Biscoff', '1 biscuit', 'Lunch', 30,
    protein: 0.3, carbs: 4.5, fat: 1.2);
const _latte = MockFood('Oat latte', '1 regular', 'Lunch', 120,
    protein: 3, carbs: 16, fat: 5);
const _pizza = MockFood('Vegan margherita pizza', '1/2 large', 'Dinner', 900,
    protein: 36, carbs: 110, fat: 32);
const _brownie = MockFood('Chocolate brownie', '1 slice', 'Dinner', 518,
    protein: 6, carbs: 62, fat: 28);
const _curry = MockFood('Chickpea curry with rice', '1 plate', 'Dinner', 920,
    protein: 28, carbs: 140, fat: 26);
// UK labels: Tofoo Naked (145 kcal/100g), Blue Dragon Satay Stir Fry
// sauce (164 kcal/100g).
const _ingredients = [
  MockFood('Tofoo tofu', '280g', 'Recipe', 406,
      protein: 46.2, carbs: 3.1, fat: 21.8),
  MockFood('Red onion', '1 medium', 'Recipe', 44,
      protein: 1.2, carbs: 10.3, fat: 0.1),
  MockFood('Courgette', '1 medium', 'Recipe', 33,
      protein: 2.4, carbs: 6.1, fat: 0.6),
  MockFood('Blue Dragon satay sauce', '120g', 'Recipe', 197,
      protein: 3.5, carbs: 24, fat: 8.3),
  MockFood('Rice noodles', '150g cooked', 'Recipe', 162,
      protein: 2.7, carbs: 36, fat: 0.3),
];

// Recipe import: a screenshot from another app. The tofu there is a lighter
// brand than ours, so the two lookups differ a little.
const _importLines = [
  MockImportLine('400.0 g firm tofu', '400g firm tofu', 480,
      MockFood('Firm tofu', '400g', 'Recipe', 580,
          protein: 60.4, carbs: 4.4, fat: 31.6)),
  MockImportLine('coco 400.0 ml', '400ml coconut milk', 680,
      MockFood('Coconut milk', '400ml', 'Recipe', 696,
          protein: 6.4, carbs: 9.6, fat: 72),
      unclear: true),
  MockImportLine('1.0 medium red onion', '1 medium red onion', 44,
      MockFood('Red onion', '1 medium', 'Recipe', 44,
          protein: 1.2, carbs: 10.3, fat: 0.1)),
  MockImportLine('2.0 tbsp curry paste', '2 tbsp curry paste', 60,
      MockFood('Curry paste', '2 tbsp', 'Recipe', 52,
          protein: 1, carbs: 6, fat: 2.6)),
  MockImportLine('250.0 g spinach', '250g spinach', 58,
      MockFood('Spinach', '250g', 'Recipe', 58,
          protein: 7.2, carbs: 9, fat: 1)),
];

final _finished = TStep(
  title: "That's it!",
  body: 'Tap Finish to go back to your real card. You can replay any '
      'tutorial from the headphones button.',
);

final List<Tutorial> tutorials = [
  // ------------------------------------------------------------ add food
  Tutorial(
    id: 'add_food',
    emoji: '🍽️',
    title: 'Add food',
    subtitle: 'Log a meal and watch your card update',
    steps: [
      const TStep(
        title: 'This is a practice card',
        body: "Everything here is pretend, so just watch. Your real card "
            "and diary aren't touched.",
        target: 'card',
      ),
      const TStep(
        title: 'Your meals',
        body: 'Your day is split into Breakfast, Lunch, Dinner and Snacks, '
            'each with what you had and its own Add button.',
        target: 'section_Lunch',
      ),
      TStep(
        title: 'Add food',
        body: 'Tap "Add to Lunch" to open the food search.',
        target: 'add_Lunch',
        act: TAct.tap,
        apply: (s) {
          s.meal = 'Lunch';
          s.screen = MockScreen.addFood;
        },
      ),
      TStep(
        title: 'Type what you had',
        body: "Write it how you'd say it. Grams and brands make it more "
            'accurate, and commas split it into separate foods.',
        target: 'input',
        act: TAct.type,
        text: '1 falafel wrap, 1 apple, 1 Lotus Biscoff',
        onType: (s, t) => s.typed = t,
        focus: 'mainBtn',
      ),
      TStep(
        title: 'Look it up',
        body: 'We find the calories, protein, carbs and fat for each food.',
        target: 'mainBtn',
        act: TAct.tap,
        apply: (s) => s.found
          ..clear()
          ..addAll([_wrap, _apple, _biscoff]),
        focus: 'mainBtn',
      ),
      TStep(
        title: 'Add them to your card',
        body: 'Check the numbers look right, then add them.',
        target: 'mainBtn',
        act: TAct.tap,
        apply: (s) {
          s.foods.addAll(s.found.map((f) => f.inMeal('Lunch')));
          s.found.clear();
          s.typed = '';
          s.screen = MockScreen.home;
          s.toast = 'Added 3 items to Lunch';
        },
        then: (s) => s.toast = null,
        focus: 'section_Lunch',
      ),
      const TStep(
        title: 'Your card updates',
        body: 'The 482 kcal came straight off your balance, just like '
            'spending on a bank card. Your macros went down too.',
        target: 'card',
      ),
      TStep(
        title: 'Flip for macros',
        body: 'Tap the card to see the protein, carbs and fat you\'ve had '
            'against your goals, like "120 / 150g".',
        target: 'card',
        act: TAct.tap,
        apply: (s) => s.cardFlipped = true,
        then: (s) => s.cardFlipped = false,
        thenAfter: const Duration(milliseconds: 2200),
        focus: 'card',
      ),
      TStep(
        title: 'Made a mistake?',
        body: 'Swipe a food to the left to remove it. The calories go '
            'straight back on your card.',
        target: 'food_Apple',
        act: TAct.swipe,
        apply: (s) {
          s.foods.removeWhere((f) => f.name == 'Apple');
          s.toast = 'Removed Apple';
        },
        then: (s) => s.toast = null,
        focus: 'card',
      ),
      _finished,
    ],
  ),

  // ------------------------------------------------------------- by voice
  Tutorial(
    id: 'voice',
    emoji: '🎤',
    title: 'Add food by voice',
    subtitle: 'Say what you ate, with "and" between foods',
    steps: [
      TStep(
        title: 'Open Add food',
        body: 'Tap "Add to Lunch", as you would to type.',
        target: 'add_Lunch',
        act: TAct.tap,
        apply: (s) {
          s.meal = 'Lunch';
          s.screen = MockScreen.addFood;
        },
        focus: 'mic',
      ),
      TStep(
        title: 'Tap the mic',
        body: 'It sits in the food box. The first time, your browser asks '
            'to use the microphone: tap Allow. Works in Chrome, Edge and '
            'Safari.',
        target: 'mic',
        act: TAct.tap,
        apply: (s) => s.listening = true,
        focus: 'input',
      ),
      TStep(
        title: 'Say "and" between foods',
        body: 'Talk like you would to a friend, with "and" between each '
            'food: "falafel wrap and an apple and an oat latte". Amounts '
            'work too: "50g of oats and 200ml of oat milk".',
        target: 'input',
        act: TAct.type,
        text: 'falafel wrap and an apple and an oat latte',
        onType: (s, t) => s.typed = t,
        focus: 'mic',
      ),
      TStep(
        title: 'Tap stop when you\'re done',
        body: "It keeps listening while you think, so take your time. "
            'Tap stop and every food becomes its own item.',
        target: 'mic',
        act: TAct.tap,
        apply: (s) {
          s.listening = false;
          s.typed = '';
          s.chips
            ..clear()
            ..addAll(['falafel wrap', 'an apple', 'an oat latte']);
        },
        focus: 'chips',
      ),
      const TStep(
        title: 'Check what it heard',
        body: 'Tap ✕ to remove anything it misheard, or type a fix. If two '
            'foods end up stuck together, it\'s because there was no "and" '
            'between them: say it next time.',
        target: 'chips',
      ),
      TStep(
        title: 'Look them up',
        body: 'Each food is worked out separately.',
        target: 'mainBtn',
        act: TAct.tap,
        apply: (s) {
          s.chips.clear();
          s.found
            ..clear()
            ..addAll([_wrap, _apple, _latte]);
        },
        focus: 'mainBtn',
      ),
      TStep(
        title: 'Add them to your card',
        body: 'Same as typing from here: check the numbers, then add.',
        target: 'mainBtn',
        act: TAct.tap,
        apply: (s) {
          s.foods.addAll(s.found.map((f) => f.inMeal('Lunch')));
          s.found.clear();
          s.screen = MockScreen.home;
          s.toast = 'Added 3 items to Lunch';
        },
        then: (s) => s.toast = null,
        focus: 'section_Lunch',
      ),
      _finished,
    ],
  ),

  // ------------------------------------------------------- coach adds food
  Tutorial(
    id: 'coach_food',
    emoji: '✨',
    title: 'Add food with Coach',
    subtitle: 'Just tell Coach what you ate',
    steps: [
      const TStep(
        title: 'Meet Coach',
        body: 'The round button in the middle is Calorie Coach, your '
            'friendly AI helper.',
        target: 'orb',
      ),
      TStep(
        title: 'Open Coach',
        body: 'Tap it any time for meal ideas, a pep talk, or to add food '
            'for you.',
        target: 'orb',
        act: TAct.tap,
        apply: (s) => s.screen = MockScreen.coach,
        focus: 'coachInput',
      ),
      TStep(
        title: 'Just say it',
        body: 'Tell Coach what you had, in your own words.',
        target: 'coachInput',
        act: TAct.type,
        text: 'add scrambled tofu and toast to breakfast',
        onType: (s, t) => s.coachTyped = t,
        focus: 'coachSend',
      ),
      TStep(
        title: 'Coach works it out',
        body: 'While Coach thinks, its spark turns into waves. Then it looks '
            'up the real numbers for you.',
        target: 'coachSend',
        act: TAct.tap,
        apply: (s) {
          s.coach.add(MockMessage(true, s.coachTyped));
          s.coachTyped = '';
          s.coachThinking = true;
        },
        then: (s) {
          s.coachThinking = false;
          s.coach.add(const MockMessage(
              false, "Here you go, tap Add and it's on your card. 🍳"));
          s.proposal = [_tofu, _toast];
          s.proposalMeal = 'Breakfast';
          s.proposalStatus = ProposalStatus.ready;
        },
        thenAfter: const Duration(milliseconds: 2000),
        focus: 'proposalAdd',
      ),
      const TStep(
        title: 'Nothing changes until you say so',
        body: "Coach shows exactly what it will add. Tap “Not this” if it's "
            'not right.',
        target: 'proposalAdd',
      ),
      TStep(
        title: 'Accept it',
        body: 'Tap Add and it goes straight into your diary.',
        target: 'proposalAdd',
        act: TAct.tap,
        apply: (s) {
          s.proposalStatus = ProposalStatus.done;
          s.foods.addAll(s.proposal.map((f) => f.inMeal('Breakfast')));
        },
      ),
      TStep(
        title: 'Back on your card',
        body: 'Breakfast now has the tofu and toast, and your balance is up '
            'to date.',
        target: 'nav_card',
        act: TAct.tap,
        apply: (s) => s.screen = MockScreen.home,
        focus: 'section_Breakfast',
      ),
      const TStep(
        title: "You're all set",
        body: 'You can also ask Coach to remove something or save a recipe. '
            'It always asks before changing anything.',
      ),
    ],
  ),

  // ------------------------------------------------------------- recipes
  Tutorial(
    id: 'recipe',
    emoji: '📖',
    title: 'Add a recipe',
    subtitle: 'Save a meal once, log it in one tap',
    steps: [
      TStep(
        title: 'Your recipes',
        body: 'Recipes are meals you make often. Save them once and log '
            'them in a tap.',
        target: 'nav_recipes',
        act: TAct.tap,
        apply: (s) => s.screen = MockScreen.recipes,
        focus: 'newRecipe',
      ),
      TStep(
        title: 'Start a new one',
        body: 'Tap "New recipe".',
        target: 'newRecipe',
        act: TAct.tap,
        apply: (s) => s.screen = MockScreen.recipeEditor,
        focus: 'recipeName',
      ),
      TStep(
        title: 'Name it',
        body: "Call it whatever you'll recognise.",
        target: 'recipeName',
        act: TAct.type,
        text: 'Satay tofu stir-fry',
        onType: (s, t) => s.draftName = t,
      ),
      TStep(
        title: 'Add the ingredients',
        body: 'Type everything in the whole recipe, with amounts. Brands '
            'make it more accurate: tofu and sauces vary a lot.',
        target: 'ingInput',
        act: TAct.type,
        text: '280g Tofoo tofu, 1 red onion, 1 courgette, 120g Blue Dragon '
            'satay sauce, 150g rice noodles',
        onType: (s, t) => s.draftTyped = t,
        focus: 'recipeMain',
      ),
      TStep(
        title: 'Work out the calories',
        body: 'We look up every ingredient and add it up, per serving too.',
        target: 'recipeMain',
        act: TAct.tap,
        apply: (s) {
          s.draftIngredients
            ..clear()
            ..addAll(_ingredients);
          s.draftTyped = '';
        },
        focus: 'recipeMain',
      ),
      TStep(
        title: 'Save it',
        body: "It's in your recipes, ready for next time.",
        target: 'recipeMain',
        act: TAct.tap,
        apply: (s) {
          s.recipes.add(MockRecipe(
              s.draftName, 2, List<MockFood>.of(s.draftIngredients)));
          s.screen = MockScreen.recipes;
          s.toast = 'Saved to My recipes';
        },
        then: (s) => s.toast = null,
        focus: 'recipe_Satay tofu stir-fry',
      ),
      TStep(
        title: 'Back to your card',
        body: "Now log it. It's dinner time.",
        target: 'nav_card',
        act: TAct.tap,
        apply: (s) => s.screen = MockScreen.home,
        focus: 'recipeBtn_Dinner',
      ),
      TStep(
        title: 'Add a recipe',
        body: 'Tap Recipe on Dinner and pick one of your saved ones.',
        target: 'recipeBtn_Dinner',
        act: TAct.tap,
        apply: (s) {
          s.meal = 'Dinner';
          s.showPicker = true;
        },
        focus: 'pickAdd',
      ),
      TStep(
        title: 'One tap',
        body: 'One serving goes on Dinner and comes off your card.',
        target: 'pickAdd',
        act: TAct.tap,
        apply: (s) {
          s.showPicker = false;
          s.foods.add(s.recipes.last.serving('Dinner'));
          s.toast = 'Added Satay tofu stir-fry to Dinner';
        },
        then: (s) => s.toast = null,
        focus: 'section_Dinner',
      ),
      _finished,
    ],
  ),

  // ------------------------------------------------------- recipe import
  Tutorial(
    id: 'recipe_import',
    emoji: '📸',
    title: 'Import a recipe',
    subtitle: 'From a screenshot, and match its calories',
    setup: (s) => s.screen = MockScreen.recipeEditor,
    steps: [
      TStep(
        title: 'Got a recipe somewhere else?',
        body: 'Screenshot it in another app or on a website, or snap a '
            'cookbook page. Then tap "Import from a screenshot or photo". '
            "It's part of Premium.",
        target: 'importBtn',
        act: TAct.tap,
        apply: (s) {
          s.screen = MockScreen.recipeImport;
          s.importStage = ImportStage.pick;
        },
        focus: 'shot',
      ),
      TStep(
        title: 'Pick your screenshot',
        body: 'Choose up to 3 if the list is long. We only read the foods '
            'and amounts.',
        target: 'shot',
        act: TAct.tap,
        apply: (s) => s.importStage = ImportStage.reading,
        then: (s) {
          s.importLines
            ..clear()
            ..addAll(_importLines);
          s.importTitle = 'Coconut tofu curry';
          s.importServings = 4;
          s.importStage = ImportStage.review;
        },
        thenAfter: const Duration(milliseconds: 1800),
        focus: 'importLines',
      ),
      const TStep(
        title: 'Check what we read',
        body: '"coco" was cut off, so we guessed coconut milk and flagged '
            "it. Fix anything that's wrong. Adding a brand makes it more "
            'accurate.',
        target: 'importLines',
      ),
      TStep(
        title: 'Look them up',
        body: "Every ingredient goes through our own lookup, not the "
            "screenshot's numbers.",
        target: 'importMain',
        act: TAct.tap,
        apply: (s) => s.importStage = ImportStage.compare,
        focus: 'importTotals',
      ),
      const TStep(
        title: 'Ours vs the screenshot',
        body: 'Our lookup says 1,430 kcal and the screenshot says 1,322. '
            'Each ingredient shows how close the two are.',
        target: 'importTotals',
      ),
      const TStep(
        title: 'Why they differ',
        body: 'Brands vary. The screenshot used a lighter tofu than ours, so '
            "its number is lower. That's normal, and it's why you get to "
            'choose.',
        target: 'importRow_0',
      ),
      TStep(
        title: 'Match the screenshot',
        body: 'Trust the screenshot? Tap "Match all to screenshot". The '
            'calories then match it exactly, with our protein, carbs and fat '
            'scaled to fit. You can switch single ingredients too.',
        target: 'matchAll',
        act: TAct.tap,
        apply: (s) => s.importMatched = true,
        focus: 'importTotals',
      ),
      TStep(
        title: 'Add them to your recipe',
        body: 'The name and servings come from the screenshot too.',
        target: 'importMain',
        act: TAct.tap,
        apply: (s) {
          s.draftIngredients
            ..clear()
            ..addAll(s.importChosen);
          s.draftName = s.importTitle;
          s.draftServings = s.importServings;
          s.screen = MockScreen.recipeEditor;
          s.toast = 'Added 5 ingredients';
        },
        then: (s) => s.toast = null,
        focus: 'recipeMain',
      ),
      TStep(
        title: 'Save it',
        body: 'It\'s in your recipes at 1,322 kcal, exactly as the '
            'screenshot said, ready to log in a tap.',
        target: 'recipeMain',
        act: TAct.tap,
        apply: (s) {
          s.recipes.add(MockRecipe(s.draftName, s.draftServings,
              List<MockFood>.of(s.draftIngredients)));
          s.screen = MockScreen.recipes;
          s.toast = 'Saved to My recipes';
        },
        then: (s) => s.toast = null,
        focus: 'recipe_Coconut tofu curry',
      ),
      _finished,
    ],
  ),

  // ------------------------------------------------------------- friends
  Tutorial(
    id: 'friends',
    emoji: '👋',
    title: 'Add friends',
    subtitle: "Find friends and see each other's day",
    steps: [
      TStep(
        title: 'Friends',
        body: "See how each other's day is going, cheer each other on and "
            'compete on the high scores.',
        target: 'nav_friends',
        act: TAct.tap,
        apply: (s) => s.screen = MockScreen.friends,
        focus: 'addFriend',
      ),
      TStep(
        title: 'Add a friend',
        body: 'Tap Add friend.',
        target: 'addFriend',
        act: TAct.tap,
        apply: (s) => s.showAddFriend = true,
        focus: 'friendEmail',
      ),
      TStep(
        title: 'Use their email',
        body: 'Type the email they signed up with.',
        target: 'friendEmail',
        act: TAct.type,
        text: 'jess@example.com',
        onType: (s, t) => s.friendEmail = t,
        focus: 'sendRequest',
      ),
      TStep(
        title: 'Send the request',
        body: "They'll get a request to accept.",
        target: 'sendRequest',
        act: TAct.tap,
        apply: (s) {
          s.showAddFriend = false;
          s.requestsSent.add('Jess');
          s.toast = 'Request sent';
        },
        then: (s) => s.toast = null,
      ),
      TStep(
        title: 'When they accept',
        body: "Once Jess says yes, she's in your friends.",
        apply: (s) {
          s.requestsSent.clear();
          s.friends.insert(0, const MockFriend('Jess', '1,240 kcal left · on budget'));
          s.toast = "You're now friends with Jess";
        },
        then: (s) => s.toast = null,
        focus: 'friend_Jess',
      ),
      const TStep(
        title: 'See their day',
        body: "Each friend shows how today's going. Tap one to see their "
            'card.',
        target: 'friend_Jess',
      ),
      const TStep(
        title: 'High scores',
        body: "See who's most on budget this month, and start a challenge.",
        target: 'hiscores',
      ),
      _finished,
    ],
  ),

  // ---------------------------------------------------------------- chat
  Tutorial(
    id: 'chat',
    emoji: '💬',
    title: 'Chat with friends',
    subtitle: 'Message friends and groups',
    steps: [
      TStep(
        title: 'Go to Friends',
        body: 'Chats live with your friends.',
        target: 'nav_friends',
        act: TAct.tap,
        apply: (s) => s.screen = MockScreen.friends,
        focus: 'chatIcon',
      ),
      TStep(
        title: 'Open your messages',
        body: 'Tap the speech bubble at the top. A red dot means something '
            'new.',
        target: 'chatIcon',
        act: TAct.tap,
        apply: (s) => s.screen = MockScreen.messages,
        focus: 'conv_Marcus',
      ),
      TStep(
        title: 'Open a chat',
        body: 'Tap a conversation.',
        target: 'conv_Marcus',
        act: TAct.tap,
        apply: (s) => s.screen = MockScreen.chat,
        focus: 'chatInput',
      ),
      TStep(
        title: 'Write a message',
        body: 'Say whatever you like.',
        target: 'chatInput',
        act: TAct.type,
        text: 'Smashed it! Fancy a walk at 6?',
        onType: (s, t) => s.chatTyped = t,
        focus: 'chatSend',
      ),
      TStep(
        title: 'Send it',
        body: 'Messages arrive straight away.',
        target: 'chatSend',
        act: TAct.tap,
        apply: (s) {
          s.chat.add(MockMessage(true, s.chatTyped));
          s.chatTyped = '';
        },
        then: (s) => s.chat.add(const MockMessage(false, 'Yes! See you then 👟')),
      ),
      const TStep(
        title: 'More ways to chat',
        body: "Make a group from Friends to chat together, or send a quick "
            "cheer from a friend's menu.",
      ),
      _finished,
    ],
  ),

  // -------------------------------------------------- guess the calories
  Tutorial(
    id: 'calorie_game',
    emoji: '🎯',
    title: 'Guess the Calories',
    subtitle: 'Challenge a friend: who knows their food best?',
    steps: [
      TStep(
        title: 'Go to Friends',
        body: 'Every friend has a game button next to their name.',
        target: 'nav_friends',
        act: TAct.tap,
        apply: (s) => s.screen = MockScreen.friends,
        focus: 'game_Marcus',
      ),
      TStep(
        title: 'Challenge a friend',
        body: 'Tap the game controller next to Marcus.',
        target: 'game_Marcus',
        act: TAct.tap,
        apply: (s) => s.showGameConfirm = true,
        focus: 'gameConfirm',
      ),
      TStep(
        title: 'Pick a game',
        body: 'Mystery foods: you both guess the calories in the same 5 '
            'foods. Or Higher or Lower: the same 10 pairs, pick the one with '
            "more. Tap Start, and Marcus hears it's his turn.",
        target: 'gameConfirm',
        act: TAct.tap,
        apply: (s) {
          s.showGameConfirm = false;
          s.screen = MockScreen.game;
        },
        focus: 'gameGuess',
      ),
      TStep(
        title: 'Make your guess',
        body: 'You both get the same 5 foods. How many calories in 40g of '
            'dark chocolate?',
        target: 'gameGuess',
        act: TAct.type,
        text: '250',
        onType: (s, t) => s.gameTyped = t,
        focus: 'gameLockIn',
      ),
      TStep(
        title: 'Lock it in',
        body: 'You see the real answer straight away. The closer you are, '
            'the more points, up to 100 a food.',
        target: 'gameLockIn',
        act: TAct.tap,
        apply: (s) {
          s.gameRevealed = true;
          s.gameMine = 1;
        },
        focus: 'gameReveal',
      ),
      TStep(
        title: 'No peeking',
        body: "Marcus can't see your guesses, and you can't see his. Here "
            "you've played all 5 and he's on his third.",
        apply: (s) {
          s.gameRevealed = false;
          s.gameMine = 5;
          s.gameTheirs = 3;
        },
        focus: 'gameProgress',
      ),
      TStep(
        title: 'The big reveal',
        body: "The winner's revealed once you've both finished. If you're "
            'playing at the same time, it pops up the moment the last guess '
            'goes in.',
        apply: (s) {
          s.gameTheirs = 5;
          s.gameOver = true;
        },
        focus: 'gameResult',
      ),
      const TStep(
        title: 'Rematch?',
        body: 'Go again in one tap. All your games, and your record against '
            'each friend, are under Friends → Games, along with the Daily '
            'Calorie Quiz and more. Every game earns XP towards your level.',
        target: 'gameRematch',
      ),
      _finished,
    ],
  ),

  // ------------------------------------------------------- going over
  Tutorial(
    id: 'over',
    emoji: '🫶',
    title: 'When you go over',
    subtitle: 'How Coach helps you even it out',
    setup: (s) {
      s.foods.addAll([_wrap, _pizza]);
      s.meal = 'Dinner';
    },
    steps: [
      const TStep(
        title: 'A big day',
        body: "You've got 198 kcal left, and dessert is calling.",
        target: 'card',
      ),
      TStep(
        title: 'Dessert happens',
        body: "Now you're 320 kcal over. Your card turns red, and that's "
            'completely fine.',
        target: 'add_Dinner',
        act: TAct.tap,
        apply: (s) {
          s.foods.add(_brownie);
          s.toast = 'Added Chocolate brownie to Dinner';
        },
        then: (s) => s.toast = null,
        focus: 'card',
      ),
      const TStep(
        title: 'A friendly nudge',
        body: 'A note appears under your card with a gentle plan to even it '
            'out over the rest of the week.',
        target: 'nudge',
      ),
      TStep(
        title: 'Ask Coach',
        body: 'Tap it and Coach talks it through with you.',
        target: 'nudge',
        act: TAct.tap,
        apply: (s) {
          s.screen = MockScreen.coach;
          s.coach.add(const MockMessage(true,
              "I've gone over by 320 kcal today. Can you help me even it out?"));
          s.coachThinking = true;
        },
        then: (s) {
          final plan = OffsetPlan.compute(
              overBy: 320, goal: 2000, today: DateTime.now());
          s.coachThinking = false;
          s.coach.add(MockMessage(
            false,
            "That's okay, one day never undoes your progress. 💜 "
            'Try about ${plan.perDay} kcal less a day ${plan.when}: an '
            'Americano instead of an oat latte, or fruit instead of biscuits. '
            'Or simply get back to normal tomorrow.',
          ));
        },
        thenAfter: const Duration(milliseconds: 2000),
      ),
      const TStep(
        title: 'Be kind to yourself',
        body: 'Coach never suggests skipping meals. A few small swaps are '
            'all it takes.',
      ),
      _finished,
    ],
  ),

  // ------------------------------------------------------- close the day
  Tutorial(
    id: 'close_day',
    emoji: '✅',
    title: 'Close your day',
    subtitle: 'Finish the day and save leftovers in your Pot',
    setup: (s) {
      s.foods.addAll([_wrap, _curry]);
      s.meal = 'Dinner';
    },
    steps: [
      const TStep(
        title: 'End of the day',
        body: "You've got 178 kcal left. Nicely done.",
        target: 'card',
      ),
      TStep(
        title: 'Swipe your card',
        body: "When you've finished eating, swipe your card sideways.",
        target: 'card',
        act: TAct.swipe,
        apply: (s) => s.showCloseDialog = true,
        focus: 'closeDay',
      ),
      TStep(
        title: 'Close the day',
        body: 'It counts towards your streak. With Pots on, up to 150 kcal '
            "of what's left is saved for a treat later in the week.",
        target: 'closeDay',
        act: TAct.tap,
        apply: (s) {
          s.showCloseDialog = false;
          s.dayClosed = true;
          s.pot = 150;
        },
        focus: 'closed',
      ),
      const TStep(
        title: 'Changed your mind?',
        body: 'Tap Reopen under your card to add more.',
        target: 'closed',
      ),
      _finished,
    ],
  ),
];
