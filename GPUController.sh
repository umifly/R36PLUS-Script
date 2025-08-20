#!/bin/bash

# --- Root check ---
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi
set -euo pipefail

CURR_TTY="/dev/tty1"
GPU_SYSFS=$(ls -d /sys/class/devfreq/ff400000.gpu 2>/dev/null | head -n 1)

# --- Initial Setup ---
printf "\033c" > "$CURR_TTY"
printf "\e[?25l" > "$CURR_TTY" # hide cursor
export TERM=linux

setfont /usr/share/consolefonts/Lat7-Terminus16.psf.gz
printf "\033c" > "$CURR_TTY"
printf "GPU Freq Manager\nPlease wait..." > "$CURR_TTY"
sleep 1

# --- Functions ---
get_gpu_status() {
    local cur max min avails
    cur=$(cat "$GPU_SYSFS/cur_freq" 2>/dev/null || echo "N/A")
    max=$(cat "$GPU_SYSFS/max_freq" 2>/dev/null || echo "N/A")
    min=$(cat "$GPU_SYSFS/min_freq" 2>/dev/null || echo "N/A")
    avails=$(cat "$GPU_SYSFS/available_frequencies" 2>/dev/null || echo "")
    echo -e "Current: $cur\nMax: $max\nMin: $min\nAvailable:\n$avails"
}

set_gpu_max() {
    local freq="$1"
    if [[ -w "$GPU_SYSFS/max_freq" ]]; then
        echo "$freq" > "$GPU_SYSFS/max_freq"
    fi
}

choose_gpu_max() {
    local avails
    avails=($(cat "$GPU_SYSFS/available_frequencies" 2>/dev/null))
    if [[ ${#avails[@]} -eq 0 ]]; then
        dialog --msgbox "Can't read GPU available frequencies!" 6 40 > "$CURR_TTY"
        return
    fi

    # 构造菜单
    local menu_opts=()
    for f in "${avails[@]}"; do
        menu_opts+=("$f" "")
    done

    local choice
    choice=$(dialog --output-fd 1 --menu "Select GPU max freq (Current: $(cat "$GPU_SYSFS/max_freq"))" 15 50 6 "${menu_opts[@]}" 2>"$CURR_TTY")
    if [[ -n "$choice" ]]; then
        set_gpu_max "$choice"
        dialog --msgbox "GPU Max Freq set to $choice" 6 40 > "$CURR_TTY"
    fi
}

ExitMenu() {
    printf "\033c" > "$CURR_TTY"
    printf "\e[?25h" > "$CURR_TTY" # show cursor
    pkill -f "gptokeyb -1 gpu-toggle.sh" || true
    exit 0
}

MainMenu() {
    while true; do
        local STATUS
        STATUS=$(get_gpu_status)
        local CHOICE
        CHOICE=$(dialog --output-fd 1 \
            --backtitle "GPU Freq Manager - R36PLUS" \
            --title "GPU Freq Manager" \
            --menu "Current GPU Status:\n$STATUS" 20 60 10 \
            1 "Choose Max Freq" \
            2 "Exit" \
            2>"$CURR_TTY")

        case $CHOICE in
            1) choose_gpu_max ;;
            2) ExitMenu ;;
            *) ExitMenu ;;
        esac
    done
}

# --- Main Execution ---
trap ExitMenu EXIT SIGINT SIGTERM

# gptokeyb setup for joystick control
if command -v /opt/inttools/gptokeyb &> /dev/null; then
    [[ -e /dev/uinput ]] && chmod 666 /dev/uinput 2>/dev/null || true
    export SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt"
    pkill -f "gptokeyb -1 gpu-toggle.sh" || true
    /opt/inttools/gptokeyb -1 "gpu-toggle.sh" -c "/opt/inttools/keys.gptk" >/dev/null 2>&1 &
else
    dialog --infobox "gptokeyb not found. Joystick control disabled." 5 65 > "$CURR_TTY"
    sleep 2
fi

printf "\033c" > "$CURR_TTY"
MainMenu