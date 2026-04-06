# Changelog

## 1.0.0 (2026-04-05)

### Features
- Group gambling via `/roll` — highest roll wins the difference from the lowest roll
- Host starts a game; group members type `1` to join, `-1` to leave
- One-click **Roll!** button so the host never has to type the command
- Tie-breaking re-rolls among tied winners, preserving the original prize
- Cross-client sync via addon messages so all players see live roll results
- **Leaderboard tab** with top 10 winners and top 10 losers, persisted across sessions
- **Alt linking** — merge stats across characters with `/gr link <alt> [main]`
- Draggable, resizable UI with Game and Leaderboard tabs
- Announce button to re-broadcast join instructions to group chat
- Remind Roll button to nudge players who haven't rolled yet
- Slash commands: `/gr` / `/goldroll`
