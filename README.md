<div align="center">

<img src="assets/icon.png" alt="Cooldown" width="150">

# Cooldown

**See how much Claude and Codex you have left, and start the 5-hour cooldown
before you sit down to work.**

</div>

---

## What it looks like

It sits in the menu bar as a ring that drains as the tightest 5-hour window runs down.

<p align="center">
  <img src="assets/menu-bar.png" alt="The right end of the macOS menu bar, with the Cooldown ring beside the Wi-Fi, battery and clock" width="560">
</p>

Click it for every window, how long until each one comes back, and one button that
starts the 5-hour cooldown early so it is already running when you get to work. The
button is live only while the 5-hour window is still full, since there is nothing to
start once the clock is running.

<p align="center">
  <img src="assets/panel-rings.png" alt="The Cooldown panel in the Rings layout: a big ring for the Codex 5-hour window, today's 5-hour timelines, and the weekly quota left for Claude and Codex" width="352">
</p>

There is also a Classic layout, a card of bars for each provider, and six themes.

<p align="center">
  <img src="assets/panel-classic.png" alt="The Cooldown panel in the Classic layout and the Midnight theme, with a card of bars for Claude and another for Codex" width="352">
</p>

<p align="center">
  <img src="assets/settings.png" alt="The Appearance pane of Cooldown's settings: six theme tiles, the dark mode and tint switches, and the Rings and Classic layout tiles" width="620">
</p>

---

## Install

macOS 14 or later, and the Xcode command line tools (`xcode-select --install`).

```bash
git clone https://github.com/arunsabaratnam/cooldown.git
cd cooldown
./scripts/build-app.sh
open build/Cooldown.app
```

To keep it, drag it into Applications:

```bash
cp -R build/Cooldown.app /Applications/
```
