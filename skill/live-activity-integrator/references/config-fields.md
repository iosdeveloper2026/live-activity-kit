# live_activity_config fields

Schema: `schema/live_activity_config.schema.json`. Example: `examples/live_activity_config.json`.
Every field is optional. Cards in `contents` override only the fields they set.

| Field | Values | Effect |
|---|---|---|
| `brandName` | text, `""` hides | Small tag on the image (large style) or label above the title |
| `title` | text, `""` hides | Main line; supports `{name}` and `{order}` |
| `subtitle` | text, `""` hides | Second line; title and subtitle both empty → image fills the card |
| `imageStyle` | `large` · `small` | Full-width image, or square thumbnail beside the text |
| `bannerImageUrl` | HTTPS URL | Image for the large style, about 3:1 (1100×360); falls back to `imageUrl` |
| `imageUrl` | HTTPS URL | Square image for the small style and the Dynamic Island |
| `symbol` | SF Symbol | Shown when no image is available |
| `accentColor` | `#RRGGBB` | Clock icon, labels, progress |
| `titlePosition` | `below` · `overlay` | Large style without stages: text under the image or over it |
| `showTimer` | bool | Countdown pill with clock icon |
| `timerMinutes` | 0–480 | Countdown length from when the card starts; ✓ at zero |
| `showStages` | bool | Stage name, status, progress bar and stage countdown |
| `stages[]` | list | `title`, `status`, `etaMinutes`, `symbol` per stage |
| `recipientName` | text | Fills `{name}` |
| `contents[]` | list | Rotating cards; each can set any field above except `stages` and `recipientName` |
| `rotation` | `sequential` · `random` | Which card each new Live Activity takes |
| `cron.startEnabled` | bool | Off switch: `false` stops new Live Activities |
| `cron.dismissAfterSeconds` | seconds | How long a finished card stays |

Outside the JSON: cron repo variables `REPEAT_EVERY_MINUTES` (how often a fresh card starts; set it
at least to the longest timer), `ATTRIBUTES_TYPE` (`LiveActivityAttributes` for kit apps) and
`APP_BUNDLE_ID` (only this app's devices). Run frequency: the cron-job.org schedule.
