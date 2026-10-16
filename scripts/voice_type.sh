#!/usr/bin/env bash
# Caelestia Voice Typing (Toggle / Push-to-Talk)
# Triggered via Super+Alt+V in Hyprland

echo "[$(date)] voice_type.sh invoked with args: $*" >> /tmp/voice_debug.log
export PATH="$HOME/.local/bin:$PATH"

PID_FILE="/tmp/caelestia_voice.pid"
AUDIO_FILE="/tmp/caelestia_voice.wav"
START_TIME_FILE="/tmp/caelestia_voice.time"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$PID_FILE" ]; then
    NOW=$(date +%s%N)
    START_TIME=$(cat "$START_TIME_FILE" 2>/dev/null || echo 0)
    DIFF_MS=$(( (NOW - START_TIME) / 1000000 ))

    # If triggered within 500ms of starting, ignore to prevent accidental double-trigger
    if [ "$DIFF_MS" -ge 0 ] && [ "$DIFF_MS" -lt 500 ]; then
        echo "[$(date)] Debounce: triggered after only ${DIFF_MS}ms, ignoring." >> /tmp/voice_debug.log
        exit 0
    fi

    PID=$(cat "$PID_FILE" 2>/dev/null)
    rm -f "$PID_FILE" "$START_TIME_FILE"
    
    # 1. Stop recording
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill -INT "$PID" 2>/dev/null || kill "$PID" 2>/dev/null
        wait "$PID" 2>/dev/null
    else
        pkill -f "pw-record.*caelestia_voice.wav" 2>/dev/null
    fi
    
    # Processing feedback
    pw-play /usr/share/sounds/freedesktop/stereo/bell.oga >/dev/null 2>&1 &
    notify-send -t 2000 -h string:x-canonical-private-synchronous:caelestia-voice -i audio-speakers "⚡ Transcribing..." "Processing your speech..." >/dev/null 2>&1 &
    
    # 2. Transcribe via Groq Whisper / Gemini / Offline
    TEXT=$(python3 "$SCRIPT_DIR/voice_transcribe.py" "$AUDIO_FILE" 2>>/tmp/voice_debug.log)
    echo "[$(date)] Transcribe output: '$TEXT'" >> /tmp/voice_debug.log
    
    # Clean up audio file
    rm -f "$AUDIO_FILE"
    
    # 3. Paste into active window if text was recognized
    if [ -n "$TEXT" ]; then
        # Save previous clipboard content
        PREV_CLIP=$(wl-paste 2>/dev/null)
        
        # Put transcription in clipboard and paste via virtual keystroke
        wl-copy "$TEXT"
        wtype -M ctrl -k v -m ctrl
        
        # Give application a moment to register paste, then restore previous clipboard
        sleep 0.35
        if [ -n "$PREV_CLIP" ]; then
            echo -n "$PREV_CLIP" | wl-copy
        fi
        
        # Confirmation feedback
        notify-send -t 1000 -h string:x-canonical-private-synchronous:caelestia-voice -i check "Done" "$TEXT" >/dev/null 2>&1 &
    else
        notify-send -t 2000 -h string:x-canonical-private-synchronous:caelestia-voice -i dialog-warning "No Speech Detected" "Try speaking clearly closer to your mic." >/dev/null 2>&1 &
    fi

else
    # ── START RECORDING ──────────────────────────────────────────
    rm -f "$AUDIO_FILE"
    
    # Audio feedback & visual notifications
    pw-play /usr/share/sounds/freedesktop/stereo/audio-volume-change.oga >/dev/null 2>&1 &
    notify-send -t 30000 -h string:x-canonical-private-synchronous:caelestia-voice -i microphone-sensitivity-high "🎙️ Listening..." "Speak now. Press Super+Alt+V when finished." >/dev/null 2>&1 &
    
    # Record at 16kHz mono (standard speech recognition format)
    pw-record --channels 1 --rate 16000 --format s16 "$AUDIO_FILE" >/dev/null 2>&1 &
    echo $! > "$PID_FILE"
    date +%s%N > "$START_TIME_FILE"
fi
