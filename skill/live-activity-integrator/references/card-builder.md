# Card builder

Turn a brief ("4 festive cards, gold and red, 30-minute timers") into `live_activity_config`.

## 1. Shape the config
- Shared settings at the top level: `brandName`, `imageStyle` (usually `"large"`),
  `showStages: false`, `titlePosition`, `showTimer`, `timerMinutes`, `accentColor`,
  `rotation` (`"random"` or `"sequential"`), `cron: { "startEnabled": true, "dismissAfterSeconds": 900 }`.
- One object per card in `contents`. **Set `titlePosition` and `showTimer` on every card**, even when
  they match the top level: inherited values surprised us once (a card inherited `"overlay"`).
- Text: titles about 32 characters max; subtitle one short line. Empty title and subtitle = the image
  fills the whole card.
- Timers: `timerMinutes` per card; `showTimer: false` for cards without a countdown. Live Activities
  last at most 8 hours (480 minutes).
- Colours: one accent per card that suits its image; avoid very dark accents (the clock icon sits on a
  dark pill).
- Leave out `stages` unless the user wants stages (`showStages: true`).

## 2. Find images
- Use images the user owns, or free-licence stock (Unsplash: free to use, no attribution required).
  Don't hotlink shop or Shutterstock images.
- Unsplash URLs crop on the fly. For each photo ID:
  - `imageUrl`: `https://images.unsplash.com/photo-<id>?w=240&h=240&fit=crop`
  - `bannerImageUrl`: `https://images.unsplash.com/photo-<id>?w=1100&h=360&fit=crop`
  - add `&crop=entropy` if the subject sits off-centre.
- Download each banner once and look at it (Read the image) before using it: the subject must survive
  a 3:1 crop, and must not be mostly empty space.

## 3. Check, preview, publish
1. `python3 scripts/validate_config.py live_activity_config.json --repeat-minutes <n>`
2. Launch the app on the simulator with `-LiveActivityPreview <n>` for each card, lock the screen,
   screenshot, and send all previews to the user together.
3. Publish only after the user approves: `scripts/publish_config.py ... --yes`.
4. Remind the user: a new image reaches a phone only after the app has been opened once.
