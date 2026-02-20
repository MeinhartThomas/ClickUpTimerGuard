# ClickUpTimerGuard

<p align="center">
  <img src="ClickUpTimerGuard/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" alt="ClickUpTimerGuard icon" width="180" />
</p>

A lightweight macOS menu bar app that helps you stay aware when your ClickUp timer is not running while you are actively working.

## What It Does

- Monitors your active app and recent keyboard/mouse activity.
- Checks ClickUp timer state on an interval.
- Shows quick status in the menu bar.
- Supports snoozing reminders for focused sessions.
- Includes a settings window for API token, detection options, and work app bundle IDs.

## Quick Start

1. Open `ClickUpTimerGuard.xcodeproj` in Xcode.
2. Build and run the `ClickUpTimerGuard` target.
3. Open **Settings** from the menu bar icon.
4. Add your ClickUp Personal API token.
5. (Optional) Set Team ID/User ID and adjust detection options.

## Project Structure

- `ClickUpTimerGuard/App` - Menu bar and settings UI.
- `ClickUpTimerGuard/Core` - Timer checks, reminders, app/activity monitoring, API client.
- `ClickUpTimerGuard/Config` - User-configurable settings and defaults.

## Notes

- This app is currently macOS-only.
- Secrets (like API tokens) are stored locally and should not be committed.
