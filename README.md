# GoldRoll

A friendly group gambling addon for World of Warcraft: Midnight.

The host sets a gold wager, group members join, everyone rolls `/roll X`, and the **highest roll wins the difference** from the lowest roll. A persistent leaderboard tracks lifetime wins and losses across characters, with alt-linking to merge stats across the same player's alts.

---

## How to Play

1. Open the window with `/gr`
2. Set your **Wager** and **Channel** (Party / Raid / Guild)
3. Click **New Game** — GoldRoll announces the game to your group
4. Click **Announce** any time to re-broadcast join instructions
5. Group members type **`1`** in chat to join, **`-1`** to leave
6. When everyone is in, click **Start Rolls** — GoldRoll tells everyone to `/roll X`
7. Click **Roll!** to roll for yourself in one click
8. Results are announced automatically once everyone has rolled

**Winner:** highest roll — receives `(highRoll - lowRoll)` gold from the lowest roller.  
**Ties** for the highest roll trigger a re-roll tiebreaker; the original prize is preserved.

---

## Slash Commands

| Command | Description |
|---|---|
| `/gr` | Toggle the GoldRoll window |
| `/gr stats` | Show top 5 leaderboard |
| `/gr allstats` | Show full leaderboard |
| `/gr link <alt> [main]` | Link an alt to a main (omit main to use current character) |
| `/gr unlink <alt>` | Remove an alt link |
| `/gr links` | List all alt links |
| `/gr reset` | Reset all stats |

---

## Leaderboard & Alt Linking

Stats persist across sessions in the **Leaderboard** tab. To merge a character's stats into a main:

```
/gr link Altname Mainname
```

Or, while logged in on your main:

```
/gr link Altname
```

Linked alts appear as `Mainname (+N alts)` on the leaderboard with their totals combined.

---

## Installation

- **CurseForge:** [CurseForge page](#)
- **Wago Addons:** [Wago page](#)
- **Manual:** Download the latest release from [GitHub](https://github.com/lyonsbp/wow-gambling-addon/releases) and extract `GoldRoll/` into `World of Warcraft/_retail_/Interface/AddOns/`

---

## License

MIT — see [LICENSE](LICENSE)
