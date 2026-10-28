#!/usr/bin/env sh
# Lists pending updates without root, one per line.
# Usage: check_updates.sh repo|aur|flatpak
#   repo/aur: "<name> <old> -> <new>"
#   flatpak:  "<app id>\t<version>"

case "$1" in
    repo)
        if command -v checkupdates > /dev/null; then
            checkupdates 2> /dev/null
        else
            # Same approach as checkupdates: sync a private copy of the sync dbs
            db="${XDG_CACHE_HOME:-$HOME/.cache}/caelestia/checkup-db"
            mkdir -p "$db"
            ln -sfn /var/lib/pacman/local "$db/local"
            fakeroot -- pacman -Sy --disable-sandbox --dbpath "$db" --logfile /dev/null > /dev/null 2>&1 || exit 1
            pacman -Qu --dbpath "$db" 2> /dev/null
        fi
        ;;
    aur)
        if command -v paru > /dev/null; then
            paru -Qua 2> /dev/null
        elif command -v yay > /dev/null; then
            yay -Qua 2> /dev/null
        fi
        ;;
    flatpak)
        flatpak remote-ls --updates --columns=application,version 2> /dev/null
        ;;
esac

exit 0
