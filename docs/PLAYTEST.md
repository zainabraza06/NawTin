# Naw Tin - playtest guide

Give testers the build and **nothing else**. Do not explain the rules, the
buttons or the calls: the point is to see what the game fails to teach. Watch
over their shoulder (or screen-record) and take notes; do not help.

## Setup (for you)

- Use a release-like build on a real phone. Note the phone model.
- Start each tester on a fresh install (or Settings > Stats > Reset).
- Ask them to think aloud. Five to ten testers, a mix of board-game players and
  people who never play them.
- Session length: 20-30 minutes. One vs-AI game, one two-player game with a
  friend, then the questions below.

## What to watch for (do not say this out loud)

**First minute**
- [ ] Do they find Play vs AI / Play with a Friend without help?
- [ ] Do they open How to Play on their own? Do they finish it?
- [ ] Do they understand the goal ("make three, eat one") from the screen alone?

**Placement**
- [ ] Do they understand they place two tokens on the first turn?
- [ ] Do they notice the glowing target points?
- [ ] When they make a line, do they find the "eat a token" step and understand
      why some tokens are dimmed (protected)?

**Calls**
- [ ] Do they understand **PHUTAS**? Do they press it, and when? Do they
      realise it is optional?
- [ ] Do they notice the **MACHYAS / BEGI / TREGHI** banners? Can they say what
      each one meant afterwards?
- [ ] Does anyone try to swing a token to build a begi on purpose?

**Movement**
- [ ] Do they work out that tokens only slide along the drawn lines?
- [ ] Do they get stuck when a token is blocked?

**Difficulty**
- [ ] Try Easy, then Medium, then Hard. Do the levels *feel* different? Does
      Easy feel beatable and Hard feel fair?
- [ ] Does the AI's think time (about half a second to a few seconds) feel right?

**Timer, hints, rewind**
- [ ] Do they notice the countdown ring? What happens at the warning?
- [ ] If they run out of time: do they understand the notice ("one more timeout
      and you lose")?
- [ ] Do they find Hint and Rewind? Do they understand the ad cost *before*
      tapping?
- [ ] Is **3 ads for a rewind** acceptable, too much, or too little? Is **1 ad /
      2 ads** for a hint fair?
- [ ] Did any ad fail to load or feel broken?

**Feel**
- [ ] Is anything too slow, too flashy, too loud? (Ask them to try the
      Reduce-motion and Low-power switches.)
- [ ] Any sound they liked or hated? Any moment where they wanted sound and
      there was none?
- [ ] Anything hard to read (text size, contrast)? Anything too small to tap?

**Two-player fairness** (run this one at least 10 times across testers)
- [ ] Record who moved first and who won.
- [ ] Ask the loser: "did the opening or the ending feel unfair?"
- [ ] After 10+ games compare wins for seat 1 and seat 2. If one seat wins about
      two thirds or more, consider switching to the symmetric opening (one line
      in `lib/main.dart`, see the README).

## Questions to ask at the end

1. In one sentence, how would you explain this game to a friend?
2. What was the most confusing moment?
3. What was the best moment?
4. Would you pay (remove ads), watch ads for hints, or neither? Why?
5. Would you play again tomorrow? What would make you?

## What to record per tester

| Tester | Device | Board games? | Finished How to Play? | Understood Phutas? | Levels differ? | Ads OK? | Top issue |
|---|---|---|---|---|---|---|---|
| | | | | | | | |

Crashes, freezes, wrong rules, anything unfair: write the exact steps and, if
you can, the position. The rules engine and AI are covered by about 200
automated tests, so any rules bug a human finds is worth adding as a new test.
