# All Knighters Tournament Manager ♟️

**🌍 Live Demo:** [https://thegreyarea42.github.io/all-knighters-manager/](https://thegreyarea42.github.io/all-knighters-manager/)

<div align="center">

[![Deploy Flutter Web to GitHub Pages](https://github.com/thegreyarea42/all-knighters-manager/actions/workflows/deploy.yml/badge.svg)](https://github.com/thegreyarea42/all-knighters-manager/actions/workflows/deploy.yml)

</div>

A high-polish, Markdown-driven Chess Tournament Manager built in Flutter for the **All Knighters Chess Club**. This app automates pairings, parses historical handicap data natively from Markdown files, and visually coordinates live timed rounds—all without needing a hidden or external database.

## ✨ Features

### 📄 Markdown-as-Database
The exported Markdown file serves as the absolute source of truth. 
* **Smart Import**: The app parses past `.md` files to extract player records.
* **Rolling Averages**: Native logic utilizes historical data to automatically assign an adjusted handicap (`Handicap = 2.0 - ((Current Score + Previous Avg) / 2)`) to returning players dynamically upon check-in.
* **Transparency**: Human-readable player data and updated scores are natively appended to the Markdown body for clear, auditable tracking.

### ⚔️ Hybrid Pairing Engine
* **Round 1 (Strength Parity)**: Automatically matches players by their Starting Handicap to keep games competitive out the gate (with automatic BYE generation for the highest-handicapped novice in case of odd pairings).
* **Rounds 2+ (Swiss Format)**: Reverts to standard Swiss pairing using purely Earned Points, including rigid "No-Repeat Opponent" chronological backchecking and organic color balancing.

### 🛑 "Overlord" Admin Controls
No need to restart your session when things shift dynamically in real time:
* **Time Warps**: Increment/decrement the active round countdown (`+1:00` / `-1:00`) instantly mid-round.
* **Add Extra Rounds**: If the night is young, seamlessly bypass the standard "Tournament Over" screen by clicking "Add Extra Round" dynamically.
* **Manual Overrides**: Admins have total control to tap and edit player handicaps live on the Check-in screen.

### 🏆 Visual Identity & Alert Systems
* **The Red-Out**: The app background triggers a hyper-visible neon yellow state at the 5-minute mark and abruptly hard-cuts to Dark Red accompanied by haptics and a full buzzer audio alert at `00:00`.
* **Olympic Podium**: Tapping "Finalize Tournament" generates a clean, scalable podium screen ranking the top 3 visually against the Final Standings.
* **Custom Assets**: Distinct, premium dark-themed aesthetic specifically styled to contrast against standard generic timer apps.

## 🚀 Live Demo (GitHub Pages)
*(Ensure your GitHub Pages setting in this repo is directed to the `gh-pages` branch `/root` to see your deployed build!)*
[Live Application](https://thegreyarea42.github.io/all-knighters-manager/)

## 🛠️ Local Development

Ensure you have [Flutter](https://docs.flutter.dev/get-started/install) installed.

```bash
# Clone the repo
git clone https://github.com/thegreyarea42/all-knighters-manager.git

cd all-knighters-manager

# Get dependencies
flutter pub get

# Run the app locally
flutter run
```

## 📄 License

This project is licensed under the **MIT License** — see the [`LICENSE`](LICENSE) file for the full text.

---
*Built with ❤️ in Flutter.*
