#!/usr/bin/env bash
# Super+Alt+V toggles recording, then transcribes and pastes into the focused app.
set -u
umask 077
export PATH="$HOME/.local/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VOICE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/caelestia-voice"
mkdir -p "$VOICE_DIR" || exit 1
chmod 700 "$VOICE_DIR"
PID_FILE="$VOICE_DIR/recorder.pid"
AUDIO_FILE="$VOICE_DIR/recording.wav"
START_TIME_FILE="$VOICE_DIR/started"
LOG_FILE="$VOICE_DIR/status.log"

notify() {
    notify-send -t 5000 -h string:x-canonical-private-synchronous:caelestia-voice \
        -i audio-input-microphone "$1" "$2" >/dev/null 2>&1 9>&- &
}
log() { printf '[%s] %s\n' "$(date -Is)" "$1" >> "$LOG_FILE"; }
# Keep this lock through transcription/paste. A new press cannot overwrite audio
# belonging to an in-flight request. Background children must not inherit it.
exec 9>"$VOICE_DIR/toggle.lock"
if ! flock -n 9; then
    notify 'Voice typing is busy' 'Wait for the current transcription to finish.'
    exit 0
fi

recorder_running() {
    [[ "$PID" =~ ^[0-9]+$ ]] && kill -0 "$PID" 2>/dev/null || return 1
    [[ -r "/proc/$PID/stat" ]] || return 1
    [[ $(awk '{print $3}' "/proc/$PID/stat" 2>/dev/null) != Z ]] || return 1
    # Never signal an unrelated process after a stale PID is reused.
    grep -Fzq -- "$AUDIO_FILE" "/proc/$PID/cmdline" 2>/dev/null
}
window_info() {
    hyprctl activewindow -j 2>/dev/null | python3 -c '
import json,sys
try:
 d=json.load(sys.stdin); print(d.get("address", "")); print(d.get("class", "").lower())
except (ValueError, AttributeError): pass
' 2>/dev/null
}

PID=$(cat "$PID_FILE" 2>/dev/null || true)
if recorder_running; then
    START_TIME=$(cat "$START_TIME_FILE" 2>/dev/null || true)
    NOW=$(date +%s%N)
    if [[ "$START_TIME" =~ ^[0-9]+$ ]] && (( NOW - START_TIME < 200000000 )); then
        exit 0
    fi
    TARGET_WINDOW=$(cat "$VOICE_DIR/target_window" 2>/dev/null || true)
    CURRENT_WINDOW=$(window_info)
    [[ -z "$TARGET_WINDOW" ]] && TARGET_WINDOW="$CURRENT_WINDOW"
    TARGET_ADDR=$(printf '%s\n' "$TARGET_WINDOW" | head -n 1)
    CURRENT_ADDR=$(printf '%s\n' "$CURRENT_WINDOW" | head -n 1)
    kill -INT "$PID" 2>/dev/null || true
    # The recorder belongs to the previous invocation: bash wait cannot wait for
    # it. Poll its exit instead, so libsndfile has finished the WAV header.
    for ((attempt=0; attempt<60; attempt++)); do
        recorder_running || break
        sleep 0.05
    done
    if recorder_running; then
        notify 'Recording could not stop' 'Please try Super+Alt+V again.'
        log 'Recorder did not exit after SIGINT.'
        exit 1
    fi
    rm -f "$PID_FILE" "$START_TIME_FILE"
    trap 'rm -f "$AUDIO_FILE" "$VOICE_DIR/error" "$VOICE_DIR/clipboard" "$VOICE_DIR/transcript" "$VOICE_DIR/current"' EXIT
    notify 'Transcribing…' 'Processing your speech.'
    if ! TEXT=$(python3 "$SCRIPT_DIR/voice_transcribe.py" "$AUDIO_FILE" 2>"$VOICE_DIR/error"); then
        ERROR=$(cat "$VOICE_DIR/error")
        log "$ERROR"
        notify 'Transcription failed' "${ERROR:-Please try again.}"
        exit 1
    fi
    if [[ -z "$TEXT" ]]; then
        log 'No speech detected.'
        notify 'No speech detected' 'Check the microphone and try again.'
        exit 0
    fi
    printf '%s' "$TEXT" > "$VOICE_DIR/transcript"
    # Preserve text OR image clipboard bytes, including trailing newlines.
    CLIP_TYPE=$(wl-paste --list-types 2>/dev/null | awk '/^text\/plain;charset=utf-8$/{print; found=1; exit} {if (!first) first=$0} END {if (!found) print first}')
    HAD_CLIP=false
    if [[ -n "$CLIP_TYPE" ]] && wl-paste --no-newline --type "$CLIP_TYPE" > "$VOICE_DIR/clipboard" 2>/dev/null; then
        HAD_CLIP=true
    fi
    if ! wl-copy --type 'text/plain;charset=utf-8' 9>&- < "$VOICE_DIR/transcript"; then
        notify 'Could not insert text' 'The clipboard service is unavailable.'
        exit 1
    fi
    CURRENT_WINDOW=$(window_info)
    CURRENT_ADDR=$(printf '%s\n' "$CURRENT_WINDOW" | head -n 1)
    if [[ -n "$TARGET_ADDR" && "$TARGET_ADDR" != "$CURRENT_ADDR" ]]; then
        notify 'Transcription copied' 'The focused window changed. Paste the text where you want it.'
        log 'Focus changed; transcript left on clipboard.'
        exit 0
    fi
    if [[ -n "$TARGET_ADDR" ]]; then
        hyprctl dispatch "hl.dsp.focus({ window = \"address:${TARGET_ADDR}\" })" >/dev/null 2>&1 || true
        sleep 0.05
    fi
    MODIFIERS=(-M ctrl)
    RELEASE=(-m ctrl)
    case "${TARGET_WINDOW#*$'\n'}" in
        *kitty*|*foot*|*alacritty*|*konsole*|*wezterm*|*ghostty*|*gnome-terminal*)
            MODIFIERS+=(-M shift); RELEASE=(-m shift -m ctrl) ;;
    esac
    sleep 0.1
    if ! wtype "${MODIFIERS[@]}" -k v "${RELEASE[@]}" 2>"$VOICE_DIR/error"; then
        log 'Paste keystroke failed; transcript left on clipboard.'
        notify 'Transcription copied' 'Automatic paste failed. Press Ctrl+V to paste it.'
        exit 0
    fi
    sleep 0.6
    # If the user had a non-text clipboard (e.g. image), restore it so binary data isn't lost.
    if $HAD_CLIP && [[ "$CLIP_TYPE" != text/* ]] && wl-paste --no-newline --type 'text/plain;charset=utf-8' > "$VOICE_DIR/current" 2>/dev/null \
            && cmp -s "$VOICE_DIR/current" "$VOICE_DIR/transcript"; then
        wl-copy --type "$CLIP_TYPE" 9>&- < "$VOICE_DIR/clipboard"
    fi
    log 'Transcription completed; paste shortcut sent.'
    notify 'Voice typing finished' 'Text inserted.'
else
    # Stale state from a crashed/expired recorder must not block the next use.
    rm -f "$PID_FILE" "$START_TIME_FILE" "$AUDIO_FILE"
    if ! command -v pw-record >/dev/null; then
        notify 'Microphone unavailable' 'pw-record is not installed.'
        exit 1
    fi
    if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -q MUTED; then
        notify 'Microphone is muted' 'Unmute it, then press Super+Alt+V again.'
        exit 1
    fi
    TARGET_WINDOW=$(window_info)
    printf '%s\n' "$TARGET_WINDOW" > "$VOICE_DIR/target_window"
    # Ten-minute cap prevents an abandoned recording from growing indefinitely.
    pw-record --channels 1 --rate 16000 --format s16 --sample-count 9600000 \
        "$AUDIO_FILE" > /dev/null 2>"$VOICE_DIR/recorder.log" 9>&- &
    PID=$!
    printf '%s\n' "$PID" > "$PID_FILE"
    date +%s%N > "$START_TIME_FILE"
    sleep 0.1
    if ! recorder_running; then
        rm -f "$PID_FILE" "$START_TIME_FILE" "$AUDIO_FILE"
        log 'Microphone recorder failed to start.'
        notify 'Microphone unavailable' 'Check the selected input device in audio settings.'
        exit 1
    fi
    log 'Recording started.'
    notify 'Listening…' 'Speak now. Press Super+Alt+V when finished.'
fi
