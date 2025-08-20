#!/bin/bash

# --- Root check ---
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi
set -euo pipefail

CURR_TTY="/dev/tty1"
CPU_SYSFS="/sys/devices/system/cpu"
UPDATER_PATH="/usr/local/bin/cpu_core_state_updater.sh"

# --- Initial Setup ---
printf "\033c" > "$CURR_TTY"
printf "\e[?25l" > "$CURR_TTY" # hide cursor
export TERM=linux

setfont /usr/share/consolefonts/Lat7-Terminus16.psf.gz
printf "\033c" > "$CURR_TTY"
printf "CPU Core Manager\nPlease wait..." > "$CURR_TTY"
printf "\n\nScript by @umifly" > "$CURR_TTY"
sleep 1

# --- Functions ---
get_cpu_status() {
    local status=""
    for cpu_path in "$CPU_SYSFS"/cpu[0-9]*; do
        local cpu_name=$(basename "$cpu_path")
        local online=$(cat "$cpu_path/online" 2>/dev/null || echo 1)
        status+="$cpu_name: $([[ "$online" -eq 1 ]] && echo "ON" || echo "OFF")\n"
    done
    echo -e "$status"
}

toggle_cpu_core() {
    local cpu="$1"
    local cpu_path="$CPU_SYSFS/$cpu"
    if [[ ! -f "$cpu_path/online" ]]; then
        dialog --title "Error" --msgbox "CPU $cpu cannot be toggled" 6 40 > "$CURR_TTY"
        return
    fi
    local online=$(cat "$cpu_path/online")
    if [[ "$online" -eq 1 ]]; then
        echo 0 > "$cpu_path/online"
    else
        echo 1 > "$cpu_path/online"
    fi
}

ExitMenu() {
    printf "\033c" > "$CURR_TTY"
    printf "\e[?25h" > "$CURR_TTY" # show cursor
    pkill -f "gptokeyb -1 cpu-toggle.sh" || true
    exit 0
}

set_all_cores() {
    local state="$1"  # 1=开启, 0=关闭
    for cpu_path in "$CPU_SYSFS"/cpu[0-9]*; do
        if [[ -f "$cpu_path/online" ]]; then
            echo "$state" > "$cpu_path/online"
        fi
    done
}

# --- CPU Governor 相关 ---
CPU_SYSFS="/sys/devices/system/cpu"

get_available_governors() {
    # 返回 cpu0 的可用 governor 列表
    cat "$CPU_SYSFS/cpu0/cpufreq/scaling_available_governors" 2>/dev/null
}

get_current_governor() {
    local target="$1"   # cpu0, cpu1, ... 或 "all"
    if [[ "$target" == "all" ]]; then
        local govs=()
        for cpu_path in "$CPU_SYSFS"/cpu[0-9]*; do
            if [[ -f "$cpu_path/cpufreq/scaling_governor" ]]; then
                govs+=("$(cat "$cpu_path/cpufreq/scaling_governor")")
            fi
        done
        echo "${govs[*]}"
    else
        local cpu_path="$CPU_SYSFS/$target"
        if [[ -f "$cpu_path/cpufreq/scaling_governor" ]]; then
            cat "$cpu_path/cpufreq/scaling_governor"
        fi
    fi
}

set_cpu_governor() {
    local target="$1"   # cpu0, cpu1, ... 或 "all"
    local governor="$2"
    local cpu

    if [[ "$target" == "all" ]]; then
        for cpu_path in "$CPU_SYSFS"/cpu[0-9]*; do
            if [[ -f "$cpu_path/cpufreq/scaling_governor" ]]; then
                echo "$governor" > "$cpu_path/cpufreq/scaling_governor"
            fi
        done
    else
        local cpu_path="$CPU_SYSFS/$target"
        if [[ -f "$cpu_path/cpufreq/scaling_governor" ]]; then
            echo "$governor" > "$cpu_path/cpufreq/scaling_governor"
        fi
    fi
}

# --- 菜单选择 Governor ---
choose_governor() {
    local governors
    governors=($(get_available_governors))
    if [[ ${#governors[@]} -eq 0 ]]; then
        dialog --msgbox "Can't read CPU support governor!" 6 40 > "$CURR_TTY"
        return
    fi

    # 拼接选项
    local menu_opts=()
    for gov in "${governors[@]}"; do
        menu_opts+=("$gov" "")
    done

    local choice
    choice=$(dialog --output-fd 1 --menu "Select CPU governor (Current CPU0: $(get_current_governor cpu0))" 15 40 6 "${menu_opts[@]}" 2>"$CURR_TTY")
    if [[ -n "$choice" ]]; then
        local target_choice
        target_choice=$(dialog --output-fd 1 --menu "Choose a CPU" 12 40 6 \
        1 "All Cores" \
        2 "CPU0 ($(get_current_governor cpu0))" \
        3 "CPU1 ($(get_current_governor cpu1))" \
        4 "CPU2 ($(get_current_governor cpu2))" \
        5 "CPU3 ($(get_current_governor cpu3))" 2>"$CURR_TTY")
        
        case $target_choice in
            1) set_cpu_governor "all" "$choice" ;;
            2) set_cpu_governor "cpu0" "$choice" ;;
            3) set_cpu_governor "cpu1" "$choice" ;;
            4) set_cpu_governor "cpu2" "$choice" ;;
            5) set_cpu_governor "cpu3" "$choice" ;;
        esac

        dialog --msgbox "Now is $choice governor" 6 40 > "$CURR_TTY"
    fi
}

# --- CPU Freq 相关 ---
get_available_freqs() {
    # 返回 cpu0 的可用频率列表
    if [[ -f "$CPU_SYSFS/cpu0/cpufreq/scaling_available_frequencies" ]]; then
        cat "$CPU_SYSFS/cpu0/cpufreq/scaling_available_frequencies"
    fi
}

get_current_max_freq() {
    local target="$1"
    local cpu_path="$CPU_SYSFS/$target"
    if [[ -f "$cpu_path/cpufreq/scaling_max_freq" ]]; then
        cat "$cpu_path/cpufreq/scaling_max_freq"
    fi
}

set_cpu_max_freq() {
    local target="$1"
    local freq="$2"
    if [[ "$target" == "all" ]]; then
        for cpu_path in "$CPU_SYSFS"/cpu[0-3]*; do
            if [[ -f "$cpu_path/cpufreq/scaling_max_freq" ]]; then
                echo "$freq" > "$cpu_path/cpufreq/scaling_max_freq"
            fi
        done
    else
        local cpu_path="$CPU_SYSFS/$target"
        if [[ -f "$cpu_path/cpufreq/scaling_max_freq" ]]; then
            echo "$freq" > "$cpu_path/cpufreq/scaling_max_freq"
        fi
    fi
}

choose_max_freq() {
    local freqs
    freqs=($(get_available_freqs))
    if [[ ${#freqs[@]} -eq 0 ]]; then
        dialog --msgbox "Can't read CPU frequencies!" 6 40 > "$CURR_TTY"
        return
    fi

    # 拼接选项（单位 MHz 更直观）
    local menu_opts=()
    for f in "${freqs[@]}"; do
        local mhz=$((f / 1000))
        menu_opts+=("$f" "${mhz} MHz")
    done

    local choice
    choice=$(dialog --output-fd 1 --menu "Select Max CPU Frequency\n(Current CPU0: $(get_current_max_freq cpu0))" 20 50 10 "${menu_opts[@]}" 2>"$CURR_TTY") || return

    if [[ -z "$choice" ]]; then
        return
    fi

    local target_choice
    target_choice=$(dialog --output-fd 1 --menu "Apply to:" 12 40 6 \
        1 "All Cores" \
        2 "CPU0 ($(get_current_max_freq cpu0))" \
        3 "CPU1 ($(get_current_max_freq cpu1))" \
        4 "CPU2 ($(get_current_max_freq cpu2))" \
        5 "CPU3 ($(get_current_max_freq cpu3))" 2>"$CURR_TTY") || return

    case $target_choice in
        1) set_cpu_max_freq "all" "$choice" ;;
        2) set_cpu_max_freq "cpu0" "$choice" ;;
        3) set_cpu_max_freq "cpu1" "$choice" ;;
        4) set_cpu_max_freq "cpu2" "$choice" ;;
        5) set_cpu_max_freq "cpu3" "$choice" ;;
        *) return ;;
    esac

    local mhz=$((choice / 1000))
    dialog --msgbox "Now max freq is ${mhz} MHz" 6 40 > "$CURR_TTY"
}

MainMenu() {
    while true; do
        local STATUS
        STATUS=$(get_cpu_status)
        local CHOICE
        CHOICE=$(dialog --output-fd 1 \
            --backtitle "CPU Core Manager - R36PLUS Script by @umifly" \
            --title "CPU Core Manager" \
            --menu "Current CPU Status:\n$STATUS" 20 60 10 \
            1 "Toggle CPU0" \
            2 "Toggle CPU1" \
            3 "Toggle CPU2" \
            4 "Toggle CPU3" \
            5 "Enable All Cores" \
            6 "Choose Governor" \
            7 "Set Max CPU Frequency" \
            8 "Exit" \
            2>"$CURR_TTY")

        case $CHOICE in
            1) toggle_cpu_core "cpu0" ;;
            2) toggle_cpu_core "cpu1" ;;
            3) toggle_cpu_core "cpu2" ;;
            4) toggle_cpu_core "cpu3" ;;
            5) set_all_cores 1 ;;
            6) choose_governor ;;
            7) choose_max_freq ;;
            8) ExitMenu ;;
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
    pkill -f "gptokeyb -1 cpu-toggle.sh" || true
    /opt/inttools/gptokeyb -1 "cpu-toggle.sh" -c "/opt/inttools/keys.gptk" >/dev/null 2>&1 &
else
    dialog --infobox "gptokeyb not found. Joystick control disabled." 5 65 > "$CURR_TTY"
    sleep 2
fi

printf "\033c" > "$CURR_TTY"
MainMenu
