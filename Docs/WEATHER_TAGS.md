# Weather tags (for package authors)

A scene opts into weather-based switching by listing **one** tag in its manifest:

```json
"weatherTags": ["day-rainy"]
```

Tags are lowercase and come from a fixed list. Unknown tags never match (the app logs a warning at launch).

## Conditions

| Condition | Covers |
|---|---|
| `sunny`  | clear, mainly clear |
| `cloudy` | partly cloudy, overcast, and anything unrecognised |
| `foggy`  | fog, rime fog |
| `rainy`  | any rain: drizzle, rain, freezing rain, rain showers |
| `snowy`  | any snow: snowfall, snow grains, snow showers |
| `stormy` | thunderstorms (including hail) |

## Valid tags (19)

- `day-<condition>` and `night-<condition>`: exact, e.g. `night-snowy` (12 tags)
- `<condition>`: that weather at any time of day, e.g. `rainy` (6 tags)
- `any`: catch-all, used only when nothing more specific matches

## How a scene is chosen

The app builds a list from the current weather, most specific first. In rain during the day:
`day-rainy`, then `rainy`, then `any`. The first tag that at least one installed scene uses wins.
If several scenes use that tag, one is chosen **at random**. A specific scene always beats a general one.
If the current scene already uses the winning tag, it stays. If nothing matches, the current scene stays.

Tip: ship at least one scene tagged `any` so there is always an answer.
