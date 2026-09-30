# Recorded project decisions

This document records confirmed decisions separately from the proposed demo scope.

## Confirmed

- Reference: Final Fantasy III on Nintendo DS (Jordan, September 22, 2026).
- 2D top-down exploration: Luke's B1 handoff and draft PR #1.
- Primary demo target: browser, minimum 1280 x 720 window (Jordan,
  September 25, 2026). Test the game viewport at 1280 x 720 CSS pixels at
  100% zoom; browser chrome can require a larger outer window. Reconfirm
  this measurement with the team during the UI review.
- Windows remains a secondary build target, not the primary demo target.
- A: Jordan; B: Luke; C: Joseph; D: Trey (current Trello assignments).
- Flutter 3.47.1 / Dart 3.13.1 is the existing CI toolchain.

## Proposed scope already listed on T0

Four heroes, four starter jobs, a 15–20 minute demo with a town, connecting
route, dungeon and boss, and one local save slot. The Trello card proposes
Warrior, Monk, White Mage and Black Mage; a small spell set; simplified MP;
and no job-transition penalty or multiplayer in the first demo.

## D4 story direction under review

Luke's September 29 proposal reframes Bellwether as a tutorial island: the four
heroes survive a shipwreck with the living lantern, restore the tide bell, and
end the opening chapter with the route to a future island unlocked. The lantern's
long-term connection to each island and the next-island hook remain team decisions.
The authored draft reflects the shipwreck and onward-travel payoff while keeping
the first-island route unchanged.

Luke also proposed setting-specific job identities: Breakwater (Anchor), Tide
Striker (Current), Lantern Keeper (Glow), and Stormcaller (Charged). These names
and signature ability IDs are authored content; C still owns formulas, costs,
balance and command legality. Treat them as the current D4 review proposal until
the team confirms the shared vocabulary.

T0 is marked complete, but no written team approval of those detailed rules
was found. Do not treat synthetic A1 fixture values as game balance or content.
C and D must confirm the job/resource/content rules in the contract review.
The deadline and availability are not recorded here because none were supplied.

## Sources and dependency gate

- T0: https://trello.com/c/Cq43OrCE
- B1: https://trello.com/c/HoKeQKvy
- B1 draft: https://github.com/LBrou28/App-4/pull/1
- Conceptual diagram: [Relations.drawio.png](Relations.drawio.png)
- Review candidate: [contracts.md](contracts.md)

The diagram is conceptual. Jordan approved the B1-v1 world boundary after
Luke/Joseph feedback; see contracts.md. B1 can begin from the tested PR handoff
with a fake host/notifier. Remaining combat/menu/save contracts are provisional;
full A1 completion and dependent A2/A3/A5 work still require those decisions.
