# Dino Trail Companion

A Ride a Dino gameplay companion using the WindUI interface (currently in beta).

## Features

- Stamina and Grip controls, including optional client-side Grip maintenance and automatic training requests.
- Searchable zone selector populated from the game's loaded track configuration.
- Local graphics optimization with recorded-value restoration, plus herd/player visibility controls.
- Optional all-in-one auto progression that coordinates Grip training, dummy/pen upgrade requests, and reward claims through normal game modules, with server-side affordability and unlock checks.
- Gift and offline-income claim controls.
- A searchable multi-select dinosaur finder: choose any rarity tier (including Eternal and Divine), mutation, and species from the live roster.
- Highlight colors, optional species/rarity/mutation labels, and adjustable ESP range.
- Default-on fall save with an adjustable search radius, lane-edge warnings, and supported camera lock.
- Right Control window toggle and a draggable mobile open button.

## Requirements

- Roblox with Ride a Dino client modules available.
- A compatible environment that can load the WindUI library and run the script.
- Required game modules must be available to the client. WindUI is in beta, and game updates or server validation may change or disable individual features.

## Use

Run `DinoTrailCompanion.lua` while Ride a Dino is loaded. Review the script and enable optional automation only when you want it active.

## Notes

This is an unofficial client-side companion. Local changes are not guaranteed to replicate, may stop working after updates, and do not grant server permissions.
