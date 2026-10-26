# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

Native SwiftUI/AppKit menu bar app (MenuBarExtra, `.window` style), macOS 14+. Current systems are macOS 26 (Tahoe) and 27, both Liquid Glass.

## Users

People who lose hours to a few sites and apps (Shorts, Twitch, social feeds, games) and want them closed for a stretch of work or an evening, without changing their mind five seconds later. They open the menu a few times a day, mostly to start one of a few usual blocks or to check how long is left; editing what a list holds is rarer.

## Product Purpose

Seawall locks websites and apps on a Mac for a chosen time. Starting takes a deliberate press-and-hold; leaving early takes a wait. It's a free, open-source (GPL-3.0) alternative to Cold Turkey Pro and Freedom.

## Positioning

- No browser extension: it reads tab addresses over Apple Events and swaps blocked tabs for a calm local page.
- Blocks stack and only ever add: a new block never loosens a running one.
- The commitment is physical (hold to lock) and the way out is honest friction (a 10- or 30-minute wait, or none), not a password game.
- A plain, standard Mac menu in light and dark mode; the blocked-site page is flat too (breathe, what brought you here, stack), chosen in Settings.

## Operating Context

Lives in the menu bar, no Dock icon. Starts blocks from the menu, from schedules, from a Focus via Shortcuts (`seawall://lock?list=Work&until=18:00`), or from Raycast and Alfred. A watchdog LaunchAgent relaunches it during a block. Blocked tabs land on `127.0.0.1:47321`.

## Capabilities and Constraints

Kept for release: saved lists, categories (Games, Social, Video, News, Shopping), block the whole web with exceptions, apps, other browsers, durations and "until" times, rounds with breaks, strictness levels, schedules, start with a Focus, notifications, sounds, keyboard shortcut, time left in the menu bar, daily stats, launch at login, first-run welcome, Settings and About, automatic updates.

Later: type-to-lock, accessibility pass beyond the redesign floor, word rules, sync between Macs. Dropped: Homebrew cask, anti-uninstall, translations, import/export of lists, accountability, Safari extension, share cards, iPhone version.

Engine constraints: blocks run on a monotonic clock; running blocks keep their own copy of what they cover; Seawall can't stop a determined person with a terminal.

## Brand Commitments

- Name: Seawall. Tilted-lock app icon and menu bar glyph.
- The water/sea visuals were removed from the menu on 2026-10-26; the blocked-site page was redesigned on 2026-10-26 (breathe, what brought you here, stack; picked in Settings, Random by default).
- Hold to lock stays (confirmed 2026-10-20).
- Voice: plain, kind, short. No guilt, no streak pressure, no shouting.

## Evidence on Hand

Real screenshots of every current state can be regenerated with the scratch harness described in the project memory. No user testimonials, metrics or press exist yet; don't invent any.

## Product Principles

1. It should feel like a real Mac app first: standard controls, keyboard and VoiceOver work.
2. Starting is easy and deliberate; loosening is slow. Never make leaving early cheaper than it is today.
3. Show only what's needed now; everything else has one obvious home.
4. No feature is cut by the redesign; things move or wait until needed.
5. Say what will happen before it happens: what gets locked, and until when.

## Accessibility & Inclusion

Text contrast 4.5:1 up to 17 pt. State never by colour alone. Every control named for VoiceOver, reachable by keyboard; the hold has a keyboard and VoiceOver path. Reduce Motion turns off the hold's fill animation.
