#!/usr/bin/env python3
"""Face recognition comparison engine for Caelestia lockscreen / Howdy PAM."""

import configparser
import datetime
import json
import os
import sys
import time
import _thread as thread

HOWDY_PATH = "/usr/lib/security/howdy"
if HOWDY_PATH not in sys.path:
    sys.path.insert(0, HOWDY_PATH)

import cv2
import dlib
import numpy as np

try:
    from recorders.video_capture import VideoCapture
except Exception:
    VideoCapture = None


def make_snapshot(snapframes, status_type, frames_count, start_time, lowest_val):
    try:
        import snapshot
        utc_str = datetime.datetime.now(datetime.timezone.utc).strftime("%Y/%m/%d %H:%M:%S UTC")
        duration = round(time.time() - start_time, 2)
        fps = round(frames_count / max(0.01, duration), 2)
        snapshot.generate(snapframes, [
            f"{status_type} LOGIN",
            f"Date: {utc_str}",
            f"Scan time: {duration}s",
            f"Frames: {frames_count} ({fps}FPS)",
            f"Hostname: {os.uname().nodename}",
            f"Best certainty value: {round(lowest_val * 10, 1)}"
        ])
    except Exception:
        pass


def main():
    start_time = time.time()
    user = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("USER", "")
    if not user:
        sys.exit(12)

    # Load face models
    models_path = os.path.join(HOWDY_PATH, "models", f"{user}.dat")
    if not os.path.isfile(models_path):
        user_home_model = os.path.expanduser(f"~/.config/howdy/models/{user}.dat")
        if os.path.isfile(user_home_model):
            models_path = user_home_model
        else:
            sys.exit(10)

    try:
        with open(models_path, "r", encoding="utf-8") as fp:
            models = json.load(fp)
    except Exception:
        sys.exit(10)

    encodings = []
    for model in models:
        encodings.extend(model.get("data", []))

    if not encodings:
        sys.exit(10)

    # Read config with priority: user override > /etc/howdy > /usr/lib/security/howdy
    config = configparser.ConfigParser()
    config_files = [
        os.path.join(HOWDY_PATH, "config.ini"),
        "/etc/howdy/config.ini",
        os.path.expanduser("~/.config/howdy/config.ini"),
        os.path.expanduser("~/.config/caelestia/howdy.ini")
    ]
    for cfg in config_files:
        if os.path.isfile(cfg):
            config.read(cfg)

    # Prefer IR camera sensor if available
    current_dev = config.get("video", "device_path", fallback="")
    if not current_dev or "video0" in os.path.realpath(current_dev) if os.path.exists(current_dev) else True:
        import glob
        import subprocess
        for p in sorted(glob.glob("/dev/v4l/by-path/*index0")):
            real = os.path.realpath(p)
            try:
                fmts = subprocess.check_output(["v4l2-ctl", "-d", real, "--list-formats"], stderr=subprocess.DEVNULL).decode()
                if any(f in fmts for f in ("GREY", "Y16", "Y8", "Z16")):
                    config.set("video", "device_path", p)
                    break
            except Exception:
                pass

    # Tuned defaults for robust webcam recognition
    certainty_val = config.getfloat("video", "certainty", fallback=4.3)
    # Ensure laptop RGB webcams are not blocked by overly strict 3.5 default
    if certainty_val <= 3.5:
        certainty_val = 4.3
    video_certainty = certainty_val / 10.0

    timeout = max(5, config.getint("video", "timeout", fallback=6))
    dark_threshold = config.getfloat("video", "dark_threshold", fallback=60.0)
    capture_failed = config.getboolean("snapshots", "capture_failed", fallback=True)
    capture_successful = config.getboolean("snapshots", "capture_successful", fallback=False)

    # Load Dlib detectors in background thread while camera initializes
    detector_lock = thread.allocate_lock()
    detector_lock.acquire()

    face_detector = None
    pose_predictor = None
    face_encoder = None

    def init_detector():
        nonlocal face_detector, pose_predictor, face_encoder
        try:
            dlib_data = os.path.join(HOWDY_PATH, "dlib-data")
            pose_predictor = dlib.shape_predictor(os.path.join(dlib_data, "shape_predictor_5_face_landmarks.dat"))
            face_encoder = dlib.face_recognition_model_v1(os.path.join(dlib_data, "dlib_face_recognition_resnet_model_v1.dat"))
            face_detector = dlib.get_frontal_face_detector()
        finally:
            detector_lock.release()

    thread.start_new_thread(init_detector, ())

    # Initialize video capture
    try:
        video_capture = VideoCapture(config)
    except Exception:
        sys.exit(1)

    # Wait for detector models
    detector_lock.acquire()
    detector_lock.release()

    if face_detector is None or pose_predictor is None or face_encoder is None:
        sys.exit(1)

    frames = 0
    valid_frames = 0
    dark_tries = 0
    black_tries = 0
    snapframes = []
    lowest_certainty = 10.0

    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    scan_start = time.time()

    try:
        while True:
            frames += 1
            if time.time() - scan_start > timeout:
                if capture_failed:
                    make_snapshot(snapframes, "FAILED", frames, scan_start, lowest_certainty)
                if dark_tries == valid_frames and valid_frames > 0:
                    sys.exit(13)
                sys.exit(11)

            frame, gsframe = video_capture.read_frame()
            if frame is None:
                continue

            gsframe = clahe.apply(gsframe)

            if (capture_failed or capture_successful) and len(snapframes) < 3:
                snapframes.append(frame.copy())

            hist = cv2.calcHist([gsframe], [0], None, [8], [0, 256])
            hist_total = np.sum(hist)
            if hist_total == 0:
                black_tries += 1
                continue

            darkness = (hist[0] / hist_total) * 100
            if darkness == 100:
                black_tries += 1
                continue

            valid_frames += 1
            if darkness > dark_threshold:
                dark_tries += 1
                continue

            face_locations = face_detector(gsframe, 0)
            for fl in face_locations:
                face_landmark = pose_predictor(frame, fl)
                face_descriptor = face_encoder.compute_face_descriptor(frame, face_landmark, 1)
                face_encoding = np.array(face_descriptor)

                matches = np.linalg.norm(encodings - face_encoding, axis=1)
                match = float(np.min(matches))

                if match < lowest_certainty:
                    lowest_certainty = match

                if 0.0 < match < video_certainty:
                    if capture_successful:
                        make_snapshot(snapframes, "SUCCESSFUL", frames, scan_start, match)
                    sys.exit(0)

    finally:
        try:
            video_capture.release()
        except Exception:
            pass


if __name__ == "__main__":
    main()
