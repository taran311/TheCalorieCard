// The tutorials, step by step. Each runs on a pretend card (see
// tutorial_mock.dart); none of them can touch real data.

import 'package:namer_app/services/coach_service.dart';
import 'package:namer_app/ui/tutorials/tutorial_mock.dart';
import 'package:namer_app/ui/tutorials/tutorial_player.dart';

const _wrap = MockFood('Chicken wrap', '1 wrap', 'Lunch', 380,
    protein: 24, carbs: 40, fat: 12);
const _apple = MockFood('Apple', '1 medium', 'Lunch', 72,
    protein: 0.4, carbs: 19, fat: 0.2);
const _eggs = MockFood('Scrambled eggs', '2 large', 'Brekkie', 156,
    protein: 13, carbs: 1, fat: 10);
const _toast = MockFood('Wholemeal toast with butter', '1 slice', 'Brekkie',
    128, protein: 4, carbs: 14, fat: 6);
const _pizza = MockFood('Margherita pizza', '1/2 large', 'Dinner', 900,
    protein: 36, carbs: 110, fat: 32);
const _brownie = MockFood('Chocolate brownie', '1 slice', 'Dinner', 518,
    protein: 6, carbs: 62, fat: 28);
const _curry = MockFood('Chicken curry with rice', '1 plate', 'Dinner', 920,
    protein: 48, carbs: 105, fat: 30);
const _ingredients = [
  MockFood('Chicken breast', '300g', 'Recipe', 330,
      protein: 69, carbs: 0, fat: 6),
  MockFood('Red pepper', '1', 'Recipe', 31, protein: 1, carbs: 6, fat: 0.3),
  MockFood('Egg noodles', '150g', 'Recipe', 207,
      protein: 7, carbs: 40, fat: 2),
  MockFood('Soy sauce', '1 tbsp', 'Recipe', 9, protein: 1, carbs: 1, fat: 0),
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
      TStep(
        title: 'Pick a meal',
        body: "Tap the meal you're adding to. Each tab shows what you've "
            'had so far.',
        target: 'tabs#1/4',
        act: TAct.tap,
        apply: (s) => s.meal = 'Lunch',
        focus: 'add',
      ),
      TStep(
        title: 'Add food',
        body: 'Tap "Add to Lunch" to open the food search.',
        target: 'add',
        act: TAct.tap,
        apply: (s) => s.screen = MockScreen.addFood,
      ),
      TStep(
        title: 'Type what you had',
        body: "Write it how you'd say it. Commas split it into separate "
            'foods.',
        target: 'input',
        act: TAct.type,
        text: 'chicken wrap, apple',
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
          ..addAll([_wrap, _apple]),
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
          s.toast = 'Added 2 items to Lunch';
        },
        then: (s) => s.toast = null,
        focus: 'card',
      ),
      const TStep(
        title: 'Your card updates',
        body: 'The 452 kcal came straight off your balance, just like '
            'spending on a bank card. Your macros went down too.',
        target: 'card',
      ),
      TStep(
        title: 'Flip for macros',
        body: 'Tap the card to see how much protein, carbs and fat you '
            'have left today.',
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
        text: 'add 2 eggs and toast to brekkie',
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
          s.proposal = [_eggs, _toast];
          s.proposalMeal = 'Brekkie';
          s.proposalStatus = ProposalStatus.ready;
        },
        thenAfter: const Duration(milliseconds: 2000),
        focus: 'proposalAdd',
      ),
      const TStep(
        title: 'Nothing changes until you say so',
        body: "Coach shows exactly what it will add. Tap Reject if it's "
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
          s.foods.addAll(s.proposal.map((f) => f.inMeal('Brekkie')));
        },
      ),
      TStep(
        title: 'Back on your card',
        body: 'Brekkie now has the eggs and toast, and your balance is up '
            'to date.',
        target: 'nav_card',
        act: TAct.tap,
        apply: (s) {
          s.screen = MockScreen.home;
          s.meal = 'Brekkie';
        },
        focus: 'card',
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
        text: 'Chicken stir fry',
        onType: (s, t) => s.draftName = t,
      ),
      TStep(
        title: 'Add the ingredients',
        body: 'Type everything in the whole recipe, with amounts.',
        target: 'ingInput',
        act: TAct.type,
        text: '300g chicken, 1 pepper, 150g noodles, 1 tbsp soy sauce',
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
        focus: 'recipe_Chicken stir fry',
      ),
      TStep(
        title: 'Back to your card',
        body: 'Now log it to a meal.',
        target: 'nav_card',
        act: TAct.tap,
        apply: (s) => s.screen = MockScreen.home,
      ),
      TStep(
        title: 'Pick the meal',
        body: "It's dinner time.",
        target: 'tabs#2/4',
        act: TAct.tap,
        apply: (s) => s.meal = 'Dinner',
        focus: 'recipeBtn',
      ),
      TStep(
        title: 'Add a recipe',
        body: 'Tap Recipe and pick one of your saved ones.',
        target: 'recipeBtn',
        act: TAct.tap,
        apply: (s) => s.showPicker = true,
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
          s.toast = 'Added Chicken stir fry to Dinner';
        },
        then: (s) => s.toast = null,
        focus: 'card',
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
            'compete on the hiscores.',
        target: 'nav_friends',
        act: TAct.tap,
        apply: (s) => s.screen = MockScreen.friends,
        focus: 'addFriend',
      ),
      TStep(
        title: 'Add a friend',
        body: 'Tap the + button.',
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
        title: 'Hiscores',
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
        target: 'add',
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
            'Americano instead of a latte, or fruit instead of biscuits. '
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
