# Dino Trail Companion

A Lua gameplay companion UI for Ride a Dino, built with the Luna Interface Suite.

## Features

- Grip/stamina controls, including an optional client-side Grip override and automatic training requests.
- Zone navigation based on the game client’s loaded track configuration.
- Local graphics options to reduce visual effects and hide streamed herd/player models.
- Optional automatic dummy and pen upgrade requests.
- Quality-of-life gift and offline income claim controls.
- An ESP rarity chooser for Common, Uncommon, Rare, Epic, Legendary, Mythic, Secret, or all rarities. It uses streamed model attributes and the loaded dinosaur config when available.
- Safety helpers including lane-edge warnings and camera lock during supported leaps.

## Requirements

- Roblox with the Ride a Dino client modules available.
- A compatible environment capable of running the script’s Lua and loading the Luna UI library.
- The relevant game modules and remotes must be available to the client. Game-side validation and updates can change or disable features.

## Use

Run `DinoTrailCompanion.lua` in your supported environment while Ride a Dino is loaded. Review the script before running it and enable optional automation only when you want it active.

## Notes

This project is an unofficial client-side companion. Some options modify local client state; they are not guaranteed, may stop working after game updates, and do not grant server permissions. Keep the source readable so it can be inspected and maintained.


