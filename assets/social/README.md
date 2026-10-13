# Social media kit

| File | Size | Use |
| --- | --- | --- |
| `avatar.png` | 1024×1024 | Profile picture, safe for round crops |
| `icon-1024.png` | 1024×1024 | App icon with transparent corners |
| `card.png`, `card@2x.png` | 1200×630 | Link previews: Open Graph, X, LinkedIn, Mastodon, Bluesky |
| `github.png`, `github@2x.png` | 1280×640 | GitHub social preview (repository Settings) |
| `square.png` | 1080×1080 | Image posts |
| `banner.png`, `banner@2x.png` | 1500×500 | X header; the bottom left stays free for the avatar |
| `screenshot-dark.png`, `screenshot-light.png` | 2560×1600 | The editor at 2× |

The SVGs are the sources; the icon is `../icons/raftaar.svg`. They use Iosevka Fixed from `../fonts` and embed `window-dark.png`.

`./export.sh` renders every PNG from its SVG with headless Chrome or Chromium. `./export.sh --shots` first retakes the screenshots with `build/raftaar`, using the scripts and the made-up agent sessions in `demo/`.

Colors: background `#111216`, surface `#1c1e24`, text `#e4e7ee`, secondary `#a3a9b8`, accent `#8aa4ff`. Font: Iosevka Fixed, under the SIL Open Font License (`../fonts/LICENSE-Iosevka.md`).
