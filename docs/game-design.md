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

The diagram is conceptual. A1 is not frozen until B/C/D review its proposed
interfaces. A2/A3 runtime work and A5 integration must respect that gate.
