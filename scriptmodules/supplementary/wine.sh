#!/usr/bin/env bash

# Wine - RetroPie-Setup module (ext/windows, Experimental section)
#
# Installs Kron4ek's vanilla x86_64 WoW64 Wine builds (run with Box64):
#   ~/wine-wow64/wine-<version>   one folder per downloaded version
#   ~/wine-wow64/wine             link to the active version
# so game launch scripts can always use:
#   WINE_DIR="$HOME/wine-wow64/wine/bin"
#
# Also sets up the "windows" system for EmulationStation:
#   ~/RetroPie/roms/windows, /opt/retropie/configs/windows/emulators.cfg and
#   the windows entry in es_systems.cfg (your custom copy in configs/all too).
#
# Configuration / Options menu:
#   - choose a version: the newest release, or a specific one
#   - installed versions: switch between them, or delete them (with sizes)
#   - sharing identical Wine files between the game prefixes: on/off, and
#     "Share now" for all of them
#   - status
#
# Sharing: each game's prefix (~/wine-prefixes/<game>) holds its own ~600 MB
# copy of Wine's files (drive_c/windows/system32 and syswow64), nearly all
# identical. With sharing on, those identical files are hard links to one
# copy, kept in a plain prefix of their own: ~/wine-prefixes/.master. This
# module makes it and updates it with each Wine version; the game launchers'
# shared code (common.inc) shares each game's files as it starts, and never
# updates a prefix while it shares. A game whose script sets PREFIX_LINK=0
# never shares (marker .nolink in its prefix - "Share now" skips it).
#
# Removing Wine deletes ~/wine-wow64 and the windows entry in EmulationStation.
# ~/RetroPie/roms/windows, configs/windows and ~/wine-prefixes (with .master)
# are kept.
#
# Settings are kept in /opt/retropie/configs/all/wine-setup.cfg

rp_module_id="wine"
rp_module_desc="Wine - Kron4ek vanilla WoW64 build, run with Box64"
rp_module_help="Downloads Kron4ek's vanilla WoW64 Wine build (https://github.com/Kron4ek/Wine-Builds) to ~/wine-wow64/wine-<version> and points ~/wine-wow64/wine at it.\n\nGame launch scripts should use:\nWINE_DIR=\"\$HOME/wine-wow64/wine/bin\"\n\nUse 'Configuration / Options' to choose the newest release or a specific version, and to switch between or delete downloaded versions.\n\nAlso creates the Windows system for EmulationStation (roms/windows, configs/windows/emulators.cfg and es_systems.cfg).\n\nNeeds the box64 and wine-deps modules (Experimental section)."
rp_module_licence="LGPL https://gitlab.winehq.org/wine/wine/-/raw/master/COPYING.LIB"
rp_module_repo=":_pkg_info_wine"
rp_module_section="exp"
rp_module_flags="!all rpi5 !32bit noinstclean"

# ----- paths / settings ---------------------------------------------------------

function _repo_wine() {
    echo "https://github.com/Kron4ek/Wine-Builds"
}

function _root_wine() {
    echo "$home/wine-wow64"
}

function _url_wine() {
    echo "$(_repo_wine)/releases/download/$1/wine-$1-amd64-wow64.tar.xz"
}

function _config_wine() {
    echo "$configdir/all/wine-setup.cfg"
}

# _get_setting_wine KEY DEFAULT
function _get_setting_wine() {
    local file="$(_config_wine)"
    local value=""
    [[ -f "$file" ]] && value="$(grep -oP "^$1\s*=\s*\"\K[^\"]*" "$file" | tail -n1)"
    [[ -z "$value" ]] && value="$2"
    echo "$value"
}

# _set_setting_wine KEY VALUE
function _set_setting_wine() {
    local file="$(_config_wine)"
    iniConfig " = " '"' "$file"
    iniSet "$1" "$2"
    chown "$__user":"$__group" "$file"
}

# ----- versions -----------------------------------------------------------------

# sort version numbers newest first, with release candidates before their release
function _sort_wine() {
    sed 's/-rc/~rc/' | sort -rV | sed 's/~rc/-rc/'
}

# all vanilla Wine versions Kron4ek has published (10.0 onwards have WoW64 builds),
# newest first - cached for 10 minutes so the menus stay quick
function _versions_wine() {
    local cache="$__tmpdir/wine-versions.cache"
    if [[ -s "$cache" && -n "$(find "$cache" -mmin -10 2>/dev/null)" ]]; then
        cat "$cache"
        return 0
    fi
    local list
    list="$(git ls-remote --tags --refs "$(_repo_wine)" 2>/dev/null \
        | awk -F/ '{print $3}' \
        | grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?(-rc[0-9]+)?$' \
        | awk -F. '$1 >= 10' \
        | _sort_wine)"
    [[ -z "$list" ]] && return 1
    mkdir -p "$__tmpdir"
    echo "$list" > "$cache"
    echo "$list"
}

# the version that should be installed: the pinned one, or the newest release
function _target_version_wine() {
    local version="$(_get_setting_wine version latest)"
    if [[ "$version" == "latest" ]]; then
        version="$(_versions_wine | head -n1)"
    fi
    [[ -z "$version" ]] && return 1
    echo "$version"
}

# the version ~/wine-wow64/wine points to
function _active_version_wine() {
    local link="$(readlink "$(_root_wine)/wine" 2>/dev/null)"
    [[ "$link" == wine-* ]] && echo "${link#wine-}"
}

# downloaded versions, newest first
function _installed_versions_wine() {
    local dir
    for dir in "$(_root_wine)"/wine-*; do
        [[ -d "$dir" && ! -L "$dir" && -x "$dir/bin/wine" ]] && echo "${dir##*/wine-}"
    done | _sort_wine
}

function _activate_wine() {
    local root="$(_root_wine)"
    ln -sfn "wine-$1" "$root/wine"
    chown -h "$__user":"$__group" "$root/wine"
}

# package information / update check used by RetroPie-Setup
function _pkg_info_wine() {
    local mode="$1"
    case "$mode" in
        get)
            local version="$(_active_version_wine)"
            echo "local pkg_repo_url=\"$(_url_wine "$version")\""
            echo "local pkg_repo_branch=\"$version\""
            echo "local pkg_repo_extra=\"$version\""
            ;;
        newer)
            local target
            target="$(_target_version_wine)" || return 3
            [[ "$target" != "$(_active_version_wine)" ]] && return 0
            return 1
            ;;
    esac
}

# ----- EmulationStation ---------------------------------------------------------

function _es_conf_custom_wine() {
    echo "$configdir/all/emulationstation/es_systems.cfg"
}

# is the windows system in the es_systems.cfg EmulationStation actually uses?
function _es_has_system_wine() {
    local conf="$(_es_conf_custom_wine)"
    [[ -f "$conf" ]] || conf="/etc/emulationstation/es_systems.cfg"
    [[ -f "$conf" ]] || return 1
    [[ "$(xmlstarlet sel -t -v "count(/systemList/system[name='windows'])" "$conf" 2>/dev/null)" -gt 0 ]]
}

# _es_custom_wine add|remove - add / remove the windows entry in a custom
# es_systems.cfg. The file is edited as text so its layout is kept; the new
# entry goes after "pc" (or before "ports" / "retropie" / at the end).
function _es_custom_wine() {
    local mode="$1"
    local conf="$(_es_conf_custom_wine)"
    [[ -f "$conf" ]] || return 0

    local tmp="$(mktemp)"
    python3 -I - "$mode" "$conf" "$tmp" "$romdir/windows" "$rootdir/supplementary/runcommand/runcommand.sh" <<'_EOF_'
import re, sys

mode, conf, out, path, runcommand = sys.argv[1:6]
with open(conf, encoding="utf-8") as f:
    text = f.read()

blocks = list(re.finditer(r"[ \t]*<system>.*?</system>[^\S\n]*\n?", text, re.S))

def name(block):
    m = re.search(r"<name>\s*(.*?)\s*</name>", block.group(0))
    return m.group(1) if m else None

windows = [b for b in blocks if name(b) == "windows"]

if mode == "add":
    if windows:
        sys.exit(10)
    entry = (
        "  <system>\n"
        "    <name>windows</name>\n"
        "    <fullname>Windows</fullname>\n"
        f"    <path>{path}</path>\n"
        "    <extension>.sh .SH</extension>\n"
        f"    <command>{runcommand} 0 _SYS_ windows %ROM%</command>\n"
        "    <platform>windows</platform>\n"
        "    <theme>windows</theme>\n"
        "  </system>\n"
    )
    pos = None
    for b in blocks:
        if name(b) == "pc":
            pos = b.end()
    if pos is None:
        for b in blocks:
            if name(b) in ("ports", "retropie"):
                pos = b.start()
                break
    if pos is None:
        pos = text.rfind("</systemList>")
    if pos < 0:
        sys.exit(2)
    if pos > 0 and text[pos - 1] != "\n":
        entry = "\n" + entry
    text = text[:pos] + entry + text[pos:]
else:
    if not windows:
        sys.exit(10)
    for b in reversed(windows):
        text = text[:b.start()] + text[b.end():]

with open(out, "w", encoding="utf-8") as f:
    f.write(text)
_EOF_
    local ret="$?"

    if [[ "$ret" -eq 0 ]]; then
        if xmlstarlet val -q -w "$tmp" 2>/dev/null; then
            cp -p "$conf" "$conf.bak"
            # write in place, so the file keeps its owner and any links to it
            cat "$tmp" > "$conf"
            if [[ "$mode" == "add" ]]; then
                printMsgs "console" "Added the windows system to $conf (backup: $conf.bak)"
            else
                printMsgs "console" "Removed the windows system from $conf (backup: $conf.bak)"
            fi
        else
            md_ret_errors+=("Could not update $conf - the result was not valid XML, so the file was left unchanged.")
        fi
    elif [[ "$ret" -ne 10 ]]; then
        md_ret_errors+=("Could not update $conf - please check the file. It was left unchanged.")
    fi
    rm -f "$tmp"
}

# ----- sharing Wine files between the game prefixes -----------------------------

function _prefixes_wine() {
    echo "$home/wine-prefixes"
}

function _master_wine() {
    echo "$(_prefixes_wine)/.master"
}

function _share_on_wine() {
    [[ "$(_get_setting_wine share_prefixes off)" == "on" ]]
}

# _as_user_wine command... - runs it as the RetroPie user, with the Wine
# settings the game launchers use (no Mono/Gecko, no menu entries, no debugger)
function _as_user_wine() {
    ( cd "$home" && sudo -u "$__user" env HOME="$home" WINEARCH=win64 WINEDEBUG=-all \
        BOX64_LOG=0 BOX64_NOBANNER=1 \
        WINEDLLOVERRIDES="mscoree,mshtml=;winemenubuilder.exe=d;winedbg.exe=d" "$@" )
}

# _master_update_wine - creates the master prefix, or updates it to the
# active Wine; nothing to do if it's up to date (marker .wine_updated = the
# active Wine's wine.inf time, as the launchers check). Before an update it
# gets its own copy of every file it shares, so Wine never writes into files
# the games share. If it's interrupted, the marker isn't written and it's
# simply done again next time.
# (callers give it no terminal: </dev/null >/dev/null 2>&1 - with the
# terminal as its input, Wine writes to the screen behind the dialogs)
function _master_update_wine() {
    local master="$(_master_wine)" bin="$(_root_wine)/wine/bin"
    local inf="$(_root_wine)/wine/share/wine/wine.inf" box64 stamp mode="-i"
    [[ -f "$inf" ]] || return 1
    stamp="$(stat -c %Y "$inf")"
    [[ "$(cat "$master/.wine_updated" 2>/dev/null)" == "$stamp" ]] && return 0
    box64="$(command -v box64 || echo /usr/local/bin/box64)"
    _as_user_wine mkdir -p "$master"
    rm -f "$master/.wine_updated"
    if [[ -f "$master/system.reg" ]]; then
        mode="-u"
        _as_user_wine bash -c 'find "$1/drive_c/windows/system32" "$1/drive_c/windows/syswow64" \
            -type f -links +1 -print0 2>/dev/null | while IFS= read -r -d "" f; do
                cp -p "$f" "$f.unshare" && mv -f "$f.unshare" "$f"; done' _ "$master"
    fi
    _as_user_wine env WINEPREFIX="$master" "$box64" "$bin/wine" wineboot "$mode"
    _as_user_wine env WINEPREFIX="$master" "$box64" "$bin/wineserver" -w
    [[ -f "$master/system.reg" ]] || return 1
    _as_user_wine bash -c 'echo "$1" > "$2/.wine_updated"' _ "$stamp" "$master"
}

# after a new or different Wine version is made active (sharing on): false,
# with the message in SHARE_ERROR_WINE, if the master couldn't be updated
function _master_after_switch_wine() {
    SHARE_ERROR_WINE=""
    _master_update_wine </dev/null >/dev/null 2>&1 && return 0
    SHARE_ERROR_WINE="Could not prepare the shared Wine files ($(_master_wine)). The games will try again when they start."
    return 1
}

function _hardlink_opts_wine() {
    # same folder and name, same contents (owner, permissions and times ignored)
    local opts="-p -o -t -f -m"
    hardlink --help 2>&1 | grep -q -- '--respect-dir' && opts+=" -d"
    echo "$opts"
}

# _share_now_wine - shares the identical Wine files of every game prefix
# (except .nolink ones) with the master, showing progress and the space saved
function _share_now_wine() {
    local root="$(_prefixes_wine)" master="$(_master_wine)"
    if ! command -v hardlink >/dev/null; then
        printMsgs "dialog" "hardlink was not found (it's part of util-linux), so nothing can be shared."
        return 1
    fi
    dialog --backtitle "$__backtitle" --infobox "Preparing the shared Wine files (Wine $(_active_version_wine)) ...\n\nThe first time, or after a Wine update, this takes a minute or two." 7 60 >/dev/tty
    if ! _master_update_wine </dev/null >/dev/null 2>&1; then
        printMsgs "dialog" "Could not prepare the shared Wine files in $master."
        return 1
    fi

    local prefixes=() p skipped=0
    for p in "$root"/*/; do
        p="${p%/}"
        [[ -f "$p/system.reg" ]] || continue
        if [[ -f "$p/.nolink" ]]; then
            skipped=$((skipped + 1))
            continue
        fi
        prefixes+=("$p")
    done
    if [[ "${#prefixes[@]}" -eq 0 ]]; then
        printMsgs "dialog" "There are no game prefixes in $root to share yet."
        return 0
    fi

    dialog --backtitle "$__backtitle" --infobox "Measuring the game prefixes ..." 3 50 >/dev/tty
    local before after stamp opts
    before="$(du -sb "$root" | cut -f1)"
    stamp="$(cat "$master/.wine_updated")"
    read -r -a opts <<< "$(_hardlink_opts_wine)"
    local n="${#prefixes[@]}" i=0 d
    {
        trap '' PIPE                    # (the sharing carries on if the gauge goes)
        for p in "${prefixes[@]}"; do
            printf 'XXX\n%d\nSharing Wine files: %s (%d of %d)\nXXX\n' \
                $(( i * 100 / n )) "${p##*/}" $(( i + 1 )) "$n" 2>/dev/null
            for d in system32 syswow64; do
                [[ -d "$master/drive_c/windows/$d" && -d "$p/drive_c/windows/$d" ]] || continue
                hardlink -q "${opts[@]}" "$master/drive_c/windows/$d" "$p/drive_c/windows/$d" >/dev/null 2>&1
            done
            # (a prefix not yet updated to this Wine is unshared and shared
            #  again by its game's next start anyway)
            echo "$stamp" > "$p/.shared"
            chown "$__user":"$__group" "$p/.shared"
            i=$(( i + 1 ))
        done
        printf 'XXX\n100\nMeasuring the game prefixes ...\nXXX\n' 2>/dev/null
    } | dialog --backtitle "$__backtitle" --title "Share now" --gauge "Sharing Wine files ..." 8 70 0 >/dev/tty
    after="$(du -sb "$root" | cut -f1)"

    local saved=$(( before - after ))
    (( saved < 0 )) && saved=0
    local msg="$n game prefixes, $(numfmt --to=iec "$saved") saved - now $(numfmt --to=iec "$after") in all"
    _set_setting_wine share_last "$(date '+%Y-%m-%d %H:%M'): $msg"
    local extra=""
    [[ "$skipped" -gt 0 ]] && extra="\n\nLeft out: $skipped (their scripts set PREFIX_LINK=0)."
    printMsgs "dialog" "Shared: $msg.\n\nBefore: $(numfmt --to=iec "$before")\nAfter:  $(numfmt --to=iec "$after")$extra"
}

function _share_toggle_wine() {
    if _share_on_wine; then
        dialog --backtitle "$__backtitle" --defaultno --yesno "Turn off sharing identical Wine files between game prefixes?\n\nGames that already share keep their shared files (that's safe: a game never updates its prefix while it shares). New prefixes and Wine updates won't be shared.\n\nA game gets its own copies back if its script sets PREFIX_LINK=0." 14 70 2>&1 >/dev/tty || return
        _set_setting_wine share_prefixes off
        return
    fi
    if ! command -v hardlink >/dev/null; then
        printMsgs "dialog" "hardlink was not found (it's part of util-linux) - sharing needs it."
        return
    fi
    local cmd=(dialog --backtitle "$__backtitle" --cancel-label "Back" --menu "Share identical Wine files between game prefixes?\n\nEach game's prefix holds its own ~600 MB copy of Wine's files. Shared, they're kept once ($(_master_wine))." 14 76 2)
    local choice
    choice=$("${cmd[@]}" \
        1 "Turn sharing on, and share all the game prefixes now" \
        2 "Turn sharing on - each game shares when it next starts" 2>&1 >/dev/tty)
    case "$choice" in
        1) _set_setting_wine share_prefixes on; _share_now_wine ;;
        2) _set_setting_wine share_prefixes on ;;
    esac
}

function _share_status_wine() {
    local master="$(_master_wine)" inf="$(_root_wine)/wine/share/wine/wine.inf" m="not made yet"
    if [[ -f "$master/.wine_updated" ]]; then
        if [[ -f "$inf" && "$(cat "$master/.wine_updated")" == "$(stat -c %Y "$inf")" ]]; then
            m="up to date"
        else
            m="for another Wine version (updated when needed)"
        fi
    fi
    local state="off"
    _share_on_wine && state="on"
    echo "Sharing Wine files between game prefixes: $state\nShared copy ($master): $m\nLast 'Share now': $(_get_setting_wine share_last never)"
}

# ----- module functions ---------------------------------------------------------

function depends_wine() {
    # libraries Wine itself uses (Box64 passes these through to the native arm64 versions)
    getDepends xz-utils \
        libasound2 libasound2-plugins libpulse0 libmpg123-0 \
        libglib2.0-0 libdbus-1-3 libsdl2-2.0-0 \
        libx11-6 libxext6 libxrandr2 libxi6 libxcursor1 libxrender1 \
        libxinerama1 libxcomposite1 libxfixes3 libxxf86vm1 \
        libfreetype6 libfontconfig1 libgnutls30 \
        libgl1 libegl1 libvulkan1 mesa-vulkan-drivers
}

function sources_wine() {
    local version
    version="$(_target_version_wine)"
    if [[ -z "$version" ]]; then
        md_ret_errors+=("Could not get the list of Wine versions from $(_repo_wine) - please check your network connection.")
        return 1
    fi
    echo "$version" > "$md_build/wine-version"

    if [[ -x "$(_root_wine)/wine-$version/bin/wine" ]]; then
        printMsgs "console" "Wine $version is already downloaded in $(_root_wine)/wine-$version"
        return 0
    fi

    download "$(_url_wine "$version")" "$md_build/wine.tar.xz" || return 1
    mkdir -p "$md_build/extract"
    runCmd tar -xJf "$md_build/wine.tar.xz" -C "$md_build/extract" || return 1
    rm -f "$md_build/wine.tar.xz"
}

function install_wine() {
    local version="$(cat "$md_build/wine-version" 2>/dev/null)"
    local root="$(_root_wine)"
    if [[ -z "$version" ]]; then
        md_ret_errors+=("No Wine version was chosen.")
        return 1
    fi

    mkUserDir "$root"
    if [[ -d "$md_build/extract" ]]; then
        local dirs=("$md_build"/extract/*/)
        if [[ "${#dirs[@]}" -ne 1 || ! -x "${dirs[0]}bin/wine" ]]; then
            md_ret_errors+=("The Wine $version download did not contain the expected files.")
            return 1
        fi
        rm -rf "$root/wine-$version"
        mv "${dirs[0]%/}" "$root/wine-$version"
        chown -R "$__user":"$__group" "$root/wine-$version"
    fi

    _activate_wine "$version"
    printMsgs "console" "Wine $version is active: $root/wine -> wine-$version"
    if _share_on_wine; then
        printMsgs "console" "Updating the shared Wine files ($(_master_wine)) ..."
        _master_after_switch_wine || md_ret_errors+=("$SHARE_ERROR_WINE")
    fi
    md_ret_require=("$root/wine/bin/wine")
}

function configure_wine() {
    if [[ "$md_mode" == "remove" ]]; then
        # configs/windows (emulators.cfg) and roms/windows are kept
        delSystem "windows" "Windows"
        _es_custom_wine remove
        return
    fi

    local had_system=0
    _es_has_system_wine && had_system=1

    mkRomDir "windows"
    addEmulator 1 "windows" "windows" "bash %ROM%"
    # custom es_systems.cfg first, so RetroPie doesn't warn about it
    _es_custom_wine add
    addSystem "windows" "Windows" ".sh"

    if [[ "$had_system" -eq 0 ]]; then
        md_ret_info+=("The Windows system has been added to EmulationStation. Restart EmulationStation to see it.")
    fi

    if [[ ! -x /usr/local/bin/box64 ]] && ! command -v box64 >/dev/null; then
        md_ret_info+=("WARNING: Box64 is not installed - Windows games won't run until you install box64 from the Experimental section.")
    fi
}

function remove_wine() {
    local root="$(_root_wine)"
    [[ -n "$home" && -d "$root" ]] && rm -rf "$root"
    rm -f "$(_config_wine)" "$__tmpdir/wine-versions.cache"
    md_ret_info+=("Wine has been removed ($root) and the Windows system taken out of EmulationStation - restart EmulationStation to see the change.\n\nKept:\n$romdir/windows\n$configdir/windows\n$home/wine-prefixes")
}

# ----- Configuration / Options --------------------------------------------------

# run an install with its output shown on screen as well as written to the log
function _install_now_wine() {
    clear
    rp_callModule "$md_id" _source_ > >(tee /dev/tty) 2>&1
    sleep 1
}

function _choose_version_wine() {
    local current="$(_get_setting_wine version latest)"
    local active="$(_active_version_wine)"

    dialog --backtitle "$__backtitle" --infobox "Getting the list of Wine versions ..." 3 50 >/dev/tty
    local versions=()
    mapfile -t versions < <(_versions_wine)
    if [[ "${#versions[@]}" -eq 0 ]]; then
        printMsgs "dialog" "Could not get the list of Wine versions from GitHub. Please check your network connection."
        return
    fi

    local installed=" $(_installed_versions_wine | tr '\n' ' ') "
    local options=(latest "Newest release (now ${versions[0]})")
    local version desc
    for version in "${versions[@]}"; do
        desc="Release"
        [[ "$installed" == *" $version "* ]] && desc+=" - downloaded"
        [[ "$version" == "$active" ]] && desc+=" (active)"
        options+=("$version" "$desc")
    done

    local cmd=(dialog --backtitle "$__backtitle" --cancel-label "Back" --default-item "$current" \
        --menu "Which Wine version should be used?\n\nCurrently chosen: $current\n\n'latest' moves to each new release when you choose Update. A version number stays on that version." 22 76 12)
    local choice
    choice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
    [[ -z "$choice" ]] && return

    _set_setting_wine version "$choice"
    rp_clearCachedInfo "$md_id"

    local target="$(_target_version_wine)"
    if [[ -n "$target" && "$target" != "$active" ]]; then
        if dialog --backtitle "$__backtitle" --yesno "Install Wine $target now?\n\nIf you choose No, it will be installed the next time you choose Update." 10 70 2>&1 >/dev/tty; then
            _install_now_wine
        fi
    else
        printMsgs "dialog" "Wine $target is already the active version."
    fi
}

function _manage_versions_wine() {
    local root="$(_root_wine)"
    local default
    while true; do
        local active="$(_active_version_wine)"
        local versions=()
        mapfile -t versions < <(_installed_versions_wine)
        if [[ "${#versions[@]}" -eq 0 ]]; then
            printMsgs "dialog" "No Wine versions are downloaded in $root."
            return
        fi

        local options=()
        local version desc
        for version in "${versions[@]}"; do
            desc="$(du -sh "$root/wine-$version" 2>/dev/null | cut -f1)"
            [[ "$version" == "$active" ]] && desc+="  (active)"
            options+=("$version" "$desc")
        done

        local cmd=(dialog --backtitle "$__backtitle" --cancel-label "Back" --default-item "$default" \
            --menu "Downloaded Wine versions in $root\n\nChoose a version to switch to it or delete it." 20 76 10)
        local choice
        choice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
        [[ -z "$choice" ]] && return
        default="$choice"

        if [[ "$choice" == "$active" ]]; then
            printMsgs "dialog" "Wine $choice is the active version.\n\nTo delete it, switch to another version first."
            continue
        fi

        local size="$(du -sh "$root/wine-$choice" 2>/dev/null | cut -f1)"
        cmd=(dialog --backtitle "$__backtitle" --cancel-label "Back" --menu "Wine $choice ($size)" 12 76 4)
        local action
        action=$("${cmd[@]}" 1 "Switch to Wine $choice (and stay on it when updating)" 2 "Delete Wine $choice" 2>&1 >/dev/tty)
        case "$action" in
            1)
                _activate_wine "$choice"
                _set_setting_wine version "$choice"
                rp_setPackageInfo "$md_id" "source"
                if _share_on_wine; then
                    dialog --backtitle "$__backtitle" --infobox "Updating the shared Wine files for Wine $choice ...\n\nThis takes a minute or two." 6 60 >/dev/tty
                    _master_after_switch_wine || printMsgs "dialog" "$SHARE_ERROR_WINE"
                fi
                printMsgs "dialog" "Wine $choice is now active.\n\nUpdate will stay on this version. To follow new releases again, choose 'latest' under 'Choose Wine version'."
                ;;
            2)
                if dialog --backtitle "$__backtitle" --defaultno --yesno "Delete Wine $choice ($size)?\n\n$root/wine-$choice\n\nYour game prefixes are not affected." 12 70 2>&1 >/dev/tty; then
                    rm -rf "$root/wine-$choice"
                fi
                ;;
        esac
    done
}

function _status_wine() {
    local root="$(_root_wine)"
    local active="$(_active_version_wine)"
    [[ -z "$active" ]] && active="none"
    local box64="not installed"
    [[ -x /usr/local/bin/box64 ]] && box64="$(timeout 10 /usr/local/bin/box64 --version 2>&1 | grep -m1 -i 'box64')"
    [[ -z "$box64" ]] && box64="installed"
    local es="no"
    _es_has_system_wine && es="yes"
    local emucfg="no"
    [[ -f "$configdir/windows/emulators.cfg" ]] && emucfg="yes"

    dialog --backtitle "$__backtitle" --infobox "Measuring the game prefixes ..." 3 50 >/dev/tty
    local psize="$(du -sh "$(_prefixes_wine)" 2>/dev/null | cut -f1)"

    printMsgs "dialog" "Active Wine: $active\nChosen version: $(_get_setting_wine version latest)\nDownloaded: $(_installed_versions_wine | tr '\n' ' ')\n\nWINE_DIR=\"\$HOME/wine-wow64/wine/bin\"\n$root/wine -> $(readlink "$root/wine" 2>/dev/null)\n\nBox64: $box64\nWindows system in EmulationStation: $es\n$configdir/windows/emulators.cfg: $emucfg\n\nGame prefixes ($(_prefixes_wine)): ${psize:-none}\n$(_share_status_wine)"
}

function gui_wine() {
    local default
    while true; do
        local share="off"
        _share_on_wine && share="on"
        local options=(
            1 "Choose Wine version (now: $(_get_setting_wine version latest))"
            2 "Downloaded versions (switch / delete)"
            3 "Share identical Wine files between game prefixes: $share"
            4 "Share now (all game prefixes)"
            5 "Status"
        )
        local cmd=(dialog --backtitle "$__backtitle" --cancel-label "Back" --default-item "$default" \
            --menu "Wine options\n\nActive version: $(_active_version_wine)" 18 76 8)
        local choice
        choice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
        default="$choice"
        case "$choice" in
            1) _choose_version_wine ;;
            2) _manage_versions_wine ;;
            3) _share_toggle_wine ;;
            4) _share_now_wine ;;
            5) _status_wine ;;
            *) break ;;
        esac
    done
}
