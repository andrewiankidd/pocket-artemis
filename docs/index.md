# Pocket Artemis

A tamagotchi game built with Lua and LOVE2D via the love2d4me framework.

## Architecture

The game is a single-screen pet sim. All gameplay lives in `pet.lua` — meters, actions, tricks, drawing, and save/load.

### Needs System

Four meters decay in real time (including while the app is closed):

| Need | Direction | Rate |
|------|-----------|------|
| Hunger | Rises (bad) | 1.0/min |
| Thirst | Rises (bad) | 1.5/min |
| Energy | Falls (bad) | 0.8/min |
| Happiness | Falls (bad) | 0.5/min |

On load, elapsed time since last save is applied as bulk decay.

### Mood

Derived from average satisfaction across all four needs:
- **Happy** — average > 66%
- **Neutral** — average 33–66%
- **Sad** — average < 33%

Mood determines the idle sprite (idle_happy, idle_neutral, idle_sad) and visual details like tail wagging.

### Actions

| Action | Effect | Cooldown | Animation |
|--------|--------|----------|-----------|
| Feed | Hunger -30 | 5s | eat |
| Water | Thirst -30 | 5s | drink |
| Play | Happiness +25, Energy -10 | 8s | play |
| Rest | Energy +30 | 10s | sleep |

### Tricks

Tricks give happiness and play an animation. Available tricks: Sit, Shake, Spin, Beg, Lie Down, Roll Over, Bear.

Bear is special — it plays a 4-frame intro (frames 0-3), then loops frames 1-3 for the full 3.5s duration.

### Sprite System

All sprites live on a single sheet (`sprites/artemis.png`) — a 5-column, 7-row grid of 200x250px cells. `sprites/sprites.json` maps animation keys to grid positions:

```json
{
    "sheet": "artemis.png",
    "cell_w": 200,
    "cell_h": 250,
    "cols": 5,
    "animations": {
        "idle_happy": { "row": 0, "col": 0, "frames": 1 },
        "play":       { "row": 1, "col": 0, "frames": 5, "fps": 6 },
        "bear":       { "row": 6, "col": 0, "frames": 4, "fps": 4, "loop_from": 1, "loop_to": 3 }
    }
}
```

**Fields:**
- `row`, `col` — top-left cell of the animation
- `frames` — number of cells (left to right from col)
- `fps` — playback speed (default 1)
- `loop_from`, `loop_to` — after the first full play, loop only this frame range

Animations without sprites fall back to procedural drawing (shape primitives).

### Skins

The game renders inside a handheld shell provided by the [love2d4me](https://github.com/andrewiankidd/love2d4me) framework. Skin selection is set via `default_skin` in `config.json`. See the love2d4me docs for skin authoring.

### Save System

Saves to `user://save.json` via love2d4me's Storage module. Auto-saves every 30 seconds. Stores all meter values plus a timestamp for offline decay calculation.

## Controls

D-pad navigates the toolbar. Confirm activates, Cancel goes back from the tricks submenu.
