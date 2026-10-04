# Design decisions

The single job of the welcome screen is to start or join a private date-night room. Paired sculptural loops supply DateNight.io's visual identity, with only two primary actions and no explanatory marketing sections.

Apple references consulted: accessibility (Vision and Mobility), layout (Visual hierarchy), typography, color, designing for iOS, buttons, dark mode (Best practices), motion (Best practices), and the installed cross-platform translation. Web semantics take precedence over native iOS navigation patterns.

Semantic tokens are in `src/app/globals.css`:

| Role | Light | Dark |
|---|---|---|
| Surface | #F8F8F5 | #191D1A |
| Card | #FFFFFF | #222823 |
| Content | #303631 | #EEF0E9 |
| Secondary content | #656C65 | #B4BCB3 |
| Accent | #69516B | #D0B4D2 |
| Connected signal | #39765A | #93D2AA |

Calculated contrast on the page surface: light primary text 11.63:1, light secondary text 5.08:1, dark primary text 14.83:1, and dark secondary text 8.75:1. Primary button text has 7.02:1 contrast in light mode and 8.72:1 in dark mode.

Verification: dark appearance and compact home/collection layouts were inspected in the browser, with no horizontal overflow at the tested mobile widths. The light palette was checked numerically. Live multiplayer and assistive-technology testing require additional verification.

System sans-serif carries headlines, controls and body copy. Spacing follows a mostly 4/8px rhythm. General body text is 17px, descriptions 13–15px, and secondary captions 11–12px. Native form fields are 16px to avoid iOS input zoom. Actions are at least 44px high.

Regular layout: `[welcome + actions] [paired-loop artwork]`. Compact layout: welcome, actions, artwork. Collection cards collapse from three columns to one. Games share an 860px-wide shell with player status, focused question cards and restrained progress indicators. The drawing canvas uses a consistent 4:3 coordinate space; Snake uses a square board with touch controls.

Motion is limited to short entrances, button feedback and loading indicators; reduced motion disables these. Dark appearance follows the OS without a separate theme preference. The drawing surface stays warm white so stored pen colors retain their meaning across both appearances. Presence, ready, locked answers and pauses include words rather than relying on color alone. Game CSS lives in `src/games/games.css` and reuses the foundation's semantic tokens.
