# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Core tamagotchi loop: four needs (hunger, thirst, energy, happiness) with real-time decay
- Offline decay — needs change while the app is closed, applied on load
- Mood system (happy / neutral / sad) derived from average need satisfaction
- Actions: Feed, Water, Play, Rest — each with cooldowns and animations
- Tricks: Sit, Shake, Spin, Lie Down, Roll Over, Bear — with energy/hunger costs
- Sprite sheet system — single-sheet grid with per-animation row/col/frame definitions
- Sprite animations: lie_down, roll_over, wink, shake, bear, happy, eat, drink, sleep, play
- Procedural fallback drawing for animations without sprites
- Loop animation support (loop_from / loop_to) for extended trick playback
- Idle behaviour system — weighted random idle animations (wink, shake, lie_down) with configurable frequency and duration
- Sound effects — procedural 8-bit sounds for all actions, tricks, and navigation; real bark.wav for the Bear trick
- Treat Catch mini-game — replaces flat Play button; falling treats, d-pad controls, score-based happiness bonus, difficulty ramp
- Need gates — tricks and play blocked when too tired, hungry, or thirsty; actions blocked when already full (not hungry/thirsty/tired)
- Exhaustion system — "Tired..." label when energy is critical, auto-rest when energy hits 0
- Animation blocking — can't spam actions during user-invoked animations; idle animations don't block
- Resting makes Artemis hungry and thirsty
- Main menu logo
- Credits screen
- Meter bar icons from game-icons.net (hunger, thirst, energy, happiness)
- Toolbar UI with d-pad navigation, cooldown display, and submenu support
- Thought bubbles for action/trick feedback
- CI/CD pipeline via shared love2d4me workflow
- Project website config (site.json) for GitHub Pages deploy

### Changed
- Internal resolution bumped from 240x240 to 320x320 for legible toolbar text
- Toolbar font sizes have minimum floors to stay readable at small resolutions
- Rest animation duration matches its cooldown (10s)

### Removed
- Beg trick (superseded by Bear)
