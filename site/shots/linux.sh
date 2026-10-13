#!/bin/sh
# Runs in a Linux container (site/shots/take.sh starts it): builds raftaar and takes the site's
# screenshots headless, as PPM files in /out. /src is the checkout and /git its git directory,
# both read-only; the project in the pictures is a clone of /git's main branch.
set -eu
command -v as >/dev/null && command -v git >/dev/null || {
    apt-get update -qq && apt-get install -y -qq binutils git >/dev/null
}
id dev >/dev/null 2>&1 || useradd -m -s /bin/bash dev
home=/home/dev
repo=$home/raftaar
mkdir -p "$home/shop"
git config --global --add safe.directory '*'
git clone -q --branch main /git "$repo"
git -C "$repo" remote remove origin
cp -R /src/site/shots/demo/. "$home/shop/"
# made-up agent sessions, so no real one ends up in a picture
slug=$(printf '%s' "$repo" | sed 's/[^A-Za-z0-9]/-/g')
mkdir -p "$home/.claude/projects/$slug" "$home/.codex/sessions/2026/09/26"
sed "s|@PROJECT@|$repo|g" /src/assets/social/demo/claude.jsonl > "$home/.claude/projects/$slug/d1.jsonl"
sed "s|@PROJECT@|$repo|g" /src/assets/social/demo/codex.jsonl > "$home/.codex/sessions/2026/09/26/rollout-d2.jsonl"
cat > "$home/.bashrc" <<'RC'
PS1='\[\e[32m\]\u@\h\[\e[0m\]:\[\e[34m\]\w\[\e[0m\]\$ '
RC
chown -R dev:dev "$home"
chmod 777 /out
su dev -c "cd $repo && ./build.sh release >/dev/null"
# an uncommitted change for the Git panel and the diff (after the build, which it does not affect)
su dev -c "cd $repo && sed -i 's/^# soft wrap: lines are split into visual rows/# soft wrap: each line is split into visual rows/' src/app/wrap.s"
cat > /tmp/shoot.sh <<'SH'
#!/bin/sh
# shoot NAME THEME PROJECT FILE SCRIPT [CONFIG LINES...]
set -eu
home=/home/dev
name=$1 theme=$2 project=$3 file=$4 script=$5
shift 5
rm -rf "$home/.config/raftaar" "$home/.local/state/raftaar"
mkdir -p "$home/.config/raftaar"
{
    printf '[ui]\ntheme = %s\n' "$theme"
    for l in "$@"; do case $l in ui.*) printf '%s\n' "${l#ui.}" ;; esac; done
    printf '[editor]\ncursor_blink = false\n'
    for l in "$@"; do case $l in editor.*) printf '%s\n' "${l#editor.}" ;; esac; done
    printf '[files]\nrestore_session = false\n'
} > "$home/.config/raftaar/config"
sed "s|@OUT@|/out/$name.ppm|" "/src/site/shots/scripts/$script" > "/tmp/$name.rsc"
cd "$project"
timeout 60 "$home/raftaar/build/raftaar" "$project" $file --headless 2560x1600 --scale 2 --script "/tmp/$name.rsc" >/dev/null 2>&1 || echo "shot $name failed" >&2
[ -s "/out/$name.ppm" ] && echo "$name"
SH
chmod 755 /tmp/shoot.sh
s() { su dev -c "HOME=/home/dev SHELL=/bin/bash /tmp/shoot.sh $*"; }
r=$repo
# Retake one theme without replacing unrelated screenshots.
if [ -n "${THEME:-}" ]; then
    case "$THEME" in *[!a-z0-9-]*) echo 'Invalid theme name' >&2; exit 1 ;; esac
    [ -f "$repo/runtime/themes/$THEME.theme" ] || { echo 'Unknown theme' >&2; exit 1; }
    s theme-$THEME $THEME $home/shop src/main.rs gallery.rsc ui.agents_panel=false
    exit 0
fi
# features, in the brand's themes
s hero raftaar-dark $r src/app/wrap.s hero.rsc
s hero-light raftaar-light $r src/app/wrap.s hero.rsc
s agents raftaar-dark $r src/app/agents.s agents.rsc
s terminal raftaar-dark $r src/app/wrap.s terminal.rsc ui.agents_panel=false
s git raftaar-dark $r src/app/wrap.s git.rsc ui.agents_panel=false
s diff raftaar-dark $r src/app/wrap.s diff.rsc ui.agents_panel=false
s palette raftaar-dark $r src/app/wrap.s palette.rsc ui.agents_panel=false
s quickopen raftaar-dark $r src/app/wrap.s quickopen.rsc ui.agents_panel=false
s search raftaar-dark $r src/app/wrap.s search.rsc ui.agents_panel=false
s find raftaar-dark $r src/app/wrap.s find.rsc ui.agents_panel=false
s vim raftaar-dark $r src/app/wrap.s vim.rsc ui.agents_panel=false editor.vim_mode=true
s settings raftaar-dark $r src/app/wrap.s settings.rsc ui.agents_panel=false
s image raftaar-dark $r assets/social/square.png image.rsc ui.agents_panel=false
# the theme gallery: a theme and a language each
d=$home/shop
s theme-tokyo-night tokyo-night $d src/main.rs gallery.rsc ui.agents_panel=false
s theme-catppuccin-mocha catppuccin-mocha $d api/app.py gallery.rsc ui.agents_panel=false
s theme-gruvbox-dark gruvbox-dark $d cmd/server/main.go gallery.rsc ui.agents_panel=false
s theme-nord nord $d web/App.tsx gallery.rsc ui.agents_panel=false
s theme-rose-pine-dawn rose-pine-dawn $d templates/order.html.erb gallery.rsc ui.agents_panel=false
s theme-dracula dracula $d db/schema.sql gallery.rsc ui.agents_panel=false
s theme-github-light github-light $d app/models/order.rb gallery.rsc ui.agents_panel=false
s theme-kanagawa kanagawa $d lib/notifier.ex gallery.rsc ui.agents_panel=false
s theme-elflord-dark elflord-dark $d src/main.rs gallery.rsc ui.agents_panel=false
