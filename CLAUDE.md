# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GoldRoll is a World of Warcraft addon for group gambling. Players wager gold, everyone `/roll`s, and the highest roll wins the difference from the lowest roll. Built for WoW: Midnight (Interface 120001).

## Architecture

The addon uses the Ace3 framework (AceAddon, AceDB, AceConsole, AceEvent) and follows a host/client model synced via addon messages (`C_ChatInfo.SendAddonMessage`).

**File structure and load order** (defined in `GoldRoll.toc`):
1. `libs.xml` — loads Ace3 libraries and LibStub from `Libs/`
2. `GoldRoll.lua` — addon entry point: initialization, slash commands (`/gr`), utility functions (gold formatting, chat output), alt-linking system, stats/leaderboard persistence
3. `core/Game.lua` — game state machine (IDLE → REGISTERING → ROLLING), player management, roll recording, result resolution with tiebreaker logic
4. `core/Events.lua` — WoW event handlers: chat message listeners for join/leave ("1"/"-1"), `CHAT_MSG_SYSTEM` parsing for `/roll` results, addon message protocol (`Broadcast`/`OnAddonMessage`) for cross-client sync

**Key design patterns:**
- Single global `GoldRoll` object (AceAddon singleton) — all modules hang methods off it
- Game state lives in `self.game` (transient) vs `self.db.global` (persisted via SavedVariables `GoldRollDB`)
- Host broadcasts state changes to non-host clients; only the host listens for `CHAT_MSG_SYSTEM` roll results
- GUI (`core/GUI.lua`) is not loaded via TOC — it's called from `GoldRoll:OnInitialize()` via `self:BuildUI()`. The GUI uses raw WoW frame API (no AceGUI), with pre-allocated row pools for the player list and leaderboard

## Release Process

Releases are automated via GitHub Actions (`.github/workflows/release.yml`). Push a git tag to trigger the BigWigsMods/packager, which publishes to CurseForge, Wago, and GitHub Releases. Requires `CF_API_KEY` and `WAGO_API_TOKEN` secrets.

The `@project-version@` token in `GoldRoll.toc` is replaced by the packager at build time. The `<!--@no-lib-strip@-->` blocks in `libs.xml` are stripped by the packager to use externally provided libraries.

## Development Notes

- No build step, test framework, or linter — this is a pure Lua WoW addon loaded directly by the game client
- To test: copy/symlink the repo into `World of Warcraft/_retail_/Interface/AddOns/GoldRoll/` and `/reload` in-game
- `Libs/` contains vendored Ace3 libraries — do not modify these files
- `.pkgmeta` controls what the BigWigsMods packager includes; `README.md`, `.github/`, `.gitignore` are excluded from releases