# `floating-player scan`: open a link from a phone QR code

`bin/floating-player-scan` (run as `floating-player scan`) uses the laptop camera
to read a QR code. For example, the phone's YouTube app can show one via
Share → QR code, and Chrome can via Share → QR code. The script then opens that
link in the floating player.

```
floating-player scan [--timeout SEC] [--device PATH] [--print] [--no-preview] [--image FILE] [--list]
```

| Option | Meaning |
|---|---|
| `--timeout SEC` | Give up after SEC seconds. Default 60. |
| `--device PATH` | Camera node to use. Overrides `$FLOATING_PLAYER_CAMERA`, which in turn overrides auto-detection. A still image or video file also works, which is useful for testing. |
| `--print` | Print the decoded text to stdout and exit 0. Opens nothing. |
| `--no-preview` | Scan without the preview window. This is automatic when there is no display. |
| `--image FILE` | Decode a QR code in an image file. Doesn't use the camera. |
| `--list` | Print the cameras auto-detection would try, best first. |

Exit status:

| Code | Meaning |
|---|---|
| 0 | Opened (or printed) |
| 1 | Error: no camera, camera busy, missing tool, or the player failed |
| 2 | The QR code isn't an http(s) link |
| 3 | No QR code found before the timeout |
| 4 | Cancelled with Esc or by closing the preview |

## How it works

1. **Lock.** `flock` on `$XDG_RUNTIME_DIR/floating-player/scan.lock` allows one
   scan at a time. A second scan gets a notification and exits 1. Work files
   live in `$XDG_RUNTIME_DIR/floating-player/scan.XXXXXX/` and are removed on exit.
2. **Window rule.** Before the window exists, the script uses `hyprctl eval` to
   register a window rule in the running compositor only:
   `floating_player_scan_rule = hl.window_rule({ match = { class = "^floating-player-scan$" }, float, pin, center, size = 2/5 × 9/40 of monitor_w, keep_aspect_ratio, opacity 1 })`.
   This is the same replace-the-previous-rule pattern as `omarchy-launch-about`.
   The preview therefore maps already floating, pinned, centered and 16:9 (on
   a 1536×960 logical screen: 614×346 logical px at 461,320). The rule is disabled again when
   the scan ends. Nothing under `~/.config/hypr` is touched. If `eval` fails
   (Hyprland without the Lua API), a fallback floats, resizes, centers and pins
   the window after it maps. It tries the Lua dispatchers first, then the
   classic ones.
3. **Capture.** One `ffmpeg` process owns the camera:
   `-f v4l2 -use_wallclock_as_timestamps 1 [-input_format mjpeg] [-video_size 1280x720] -i /dev/videoN`.
   A `split` filter feeds two outputs:
   - **Preview:** 640 px wide and mirrored (`hflip`), so aiming feels like a
     mirror. Sent as raw video in NUT through a FIFO to
     `mpv --no-config --wayland-app-id=floating-player-scan`, using its own
     input.conf in which Esc and q quit.
   - **Decode stream:** 4 fps, grayscale, at most 1280 px wide, not mirrored.
     Written with `-update 1 -atomic_writing 1` to `frame.png`, so a partly
     written frame is never read.
4. **Decode loop.** Every 0.2 s the script runs
   `zbarimg -q --raw -Sdisable -Sqrcode.enable frame.png`, which looks for QR
   codes only, so stray barcodes in the scene are ignored. It stops on the first
   decode, at the timeout, or when mpv exits (Esc or closing the window =
   cancel). It also stops if ffmpeg dies, which is reported as an error.
5. **Release.** Before anything is opened, mpv and ffmpeg are stopped
   (TERM, then KILL after 2 s) and the script waits for them to exit. That
   releases the camera and turns the LED off. The lock is released before the
   player starts, so a long-lived browser never holds it.
6. **Validate and open.** See the next section.

Notifications use `notify-send`. Each one replaces the previous one, so a scan
shows a single bubble that changes:

- "Hold the QR code up to the camera… (Esc cancels)"
- "Opened …", or "Opened … (not a YouTube link)"
- "No QR code found", "Scan cancelled", or "That QR code isn't a web link: …"

After 10 s, if the picture is still almost black (mean brightness < 3 %), the
bubble changes to a hint about the privacy shutter or a covered lens.
Notification text is markup-escaped. Messages are also printed to stderr.

## Validating the decoded text

The decoded text is only ever handled as data. It is never `eval`ed, never run
through a shell and never interpolated into Lua or hyprctl. It reaches the
player as one argument: `"$DIR/floating-player" open "$url"`.

1. Leading and trailing whitespace and CR/LF are trimmed.
2. The text must match `^https?://[^[:space:][:cntrl:]]+$` (scheme matched
   case-insensitively) and be at most 4096 characters. Anything else, such as
   plain text, `javascript:`, `intent:` or multi-line data, produces a
   notification and exit code 2.
3. The host is taken after the scheme. Userinfo is stripped, so
   `https://youtube.com@evil.example/` has the host `evil.example`, and the
   port and trailing dot are stripped too.
4. The YouTube hosts are `youtube.com`, `*.youtube.com` (www, m, music, tv) and
   `youtu.be`, plus `youtube-nocookie.com` and `*.youtube-nocookie.com`. These
   are opened silently. Any other http(s) host is still opened, but the script
   prints a note to stderr and the notification adds "(not a YouTube link)".
5. With `--print`, the raw decoded text is printed unchanged and nothing is
   validated or opened.

## Choosing the camera

1. `--device`, then `$FLOATING_PLAYER_CAMERA`. If one is set, only that device
   is tried. It may be a file, for testing.
2. Otherwise every `/sys/class/video4linux/video*` is checked. A node is
   **skipped** if it:
   - isn't a character device the user can read and write;
   - has a name containing `ISYS`, `IPU … Capture` or `Metadata`. Intel IPU
     ISYS nodes deliver raw Bayer and need the vendor ISP; here they are root-only
     anyway;
   - doesn't list `Video Capture` in its **Device Caps**;
   - lists no pixel formats.
3. The remaining nodes are ranked:

   | Score | Node |
   |---|---|
   | 40 | v4l2loopback node that a running `v4l2-relayd` writes to (`device=/dev/videoN` in its command line). This is how IPU6/IPU7 laptops expose the ISP camera. |
   | 30 | `uvcvideo` (ordinary USB/UVC webcam) |
   | 20 | other drivers |
   | 10 | other v4l2loopback nodes |
   | 1 | loopback nodes named OBS or dummy (virtual cameras, not a real lens) |

4. Candidates are **tried in order**. A candidate is used if ffmpeg writes a
   first frame within 10 s. If ffmpeg exits first (EBUSY, permission, bad
   format) or 10 s pass with no frame, the next candidate is tried. If none
   works: "Couldn't start the camera: <ffmpeg's last error> (in use by another
   app?)".
5. Capture format: a size from 1280x720, 1920x1080, 960x540, 1024x576, 640x480,
   800x600, in that order. MJPEG at that size is preferred when offered (higher
   frame rate on UVC cams). Otherwise the driver default format is used.

### Tested camera: Intel IPU7 laptop camera (v4l2-relayd)

- `v4l2-ctl --list-devices` shows `ipu7` (only `/dev/media0`) and
  `Hardware ISP Camera (platform:v4l2loopback-050)` at `/dev/video50`.
  `/dev/video0` to `/dev/video31` are `Intel IPU7 ISYS Capture N`. They are
  root-only raw nodes.
- `v4l2-relayd@ipu7.service` runs
  `icamerasrc device-name=ov08x40-uf … ! v4l2sink device=/dev/video50` as NV12
  1920x1080 at 30 fps. It only starts the sensor when a reader opens
  `/dev/video50`. Plain `ffmpeg -f v4l2` on `/dev/video50` therefore works, and
  PipeWire or libcamera isn't needed.
- **Warm-up:** for about the first 3 s after opening, the loopback returns
  black or stale frames (luma average about 1 to 16). Then the real image
  arrives (luma about 120 in a lit room). The loopback also releases a burst of
  buffered frames with bogus timestamps at the start. That is why ffmpeg uses
  `-use_wallclock_as_timestamps 1`. Without it, `-t`/`fps` treated 15 s of
  "timestamps" as about 3 s of wall time, and every early test frame looked
  black.
- `--list` prints `/dev/video50  Hardware ISP Camera (score 40)`.

## What was verified (2026-10-05)

- **Decoding and validation, with `qrencode` images.** The script was run with
  `--image` against a stub `floating-player` that only echoes its arguments.
  - `https://youtu.be/dQw4w9WgXcQ` gave `open https://youtu.be/dQw4w9WgXcQ`
    (2 args) and rc 0.
  - `https://tv.youtube.com/watch/abc` was opened silently.
  - `https://example.com/path?q=1` was opened, with a note.
  - `https://youtube.com@evil.example/x` was treated as host `evil.example`:
    opened with a note.
  - `javascript:alert(1)`, `hello; rm -rf ~ $(touch /tmp/pwned)` and a
    two-line payload each gave rc 2 and opened nothing. `/tmp/pwned` was not
    created.
  - A blank image gave rc 3.
  - `--print` printed every payload unchanged.
- **Full live loop without the camera.** `--device scene.jpg` was used, where
  `scene.jpg` is a 1920x1080 noisy, blurred plasma background with a 300 px
  QR code rotated 12°. ffmpeg looped it as if it were a camera. The script
  decoded it and called the stub with the YouTube URL in about 0.6 s. The
  `--no-preview --print` variant also worked.
- **Preview window.** It mapped with class `floating-player-scan`, floating and
  pinned, at 614×346 at 461,320. That is centered on eDP-1, which is
  1536×960 logical. A screenshot showed the frame. Esc (sent with `wtype` while
  the preview had focus) gave "Scan cancelled", rc 4. Closing the window with
  `hl.dsp.window.close` also gave rc 4. Afterwards no window, ffmpeg or mpv
  was left, and `floating_player_scan_rule` was `nil` again.
- **Real camera** (`--print --timeout 12`, about 15 s wall time in total):
  - It picked `/dev/video50`.
  - The preview window showed the live image (screenshot mean 0.45, standard
    deviation 0.16, so not black).
  - `frame.png` in the work dir was a 1280x720 grayscale live frame (mean
    about 0.44) at 5 s and 8 s, and `zbarimg` ran on it. There was no QR code
    in view, so the result was rc 3, "No QR code found".
  - Afterwards `fuser /dev/video50` showed no users, so the camera was released
    and the relay stopped the sensor.

  A real phone QR code could not be held up during testing. The decode step
  itself is the one exercised with the generated images.
- **Other paths:**
  - A second concurrent scan gives "A QR scan is already running", rc 1.
  - `--timeout 0` is rejected.
  - `FLOATING_PLAYER_CAMERA=/dev/video0` (root-only) gives "Couldn't start the
    camera: … Permission denied", rc 1.
- **Static checks:** `bash -n` and `shellcheck -x` (0.11.0, run through
  `mise x shellcheck@latest`) are clean.

## Caveats

- **Startup delay.** On IPU6/IPU7 relay cameras the first decodable frame comes
  about 2 to 3 s after the start. The preview shows black until then. The
  timeout includes this time.
- **Mirroring.** Only the preview is mirrored. A camera that already outputs a
  mirrored image would give zbar a mirrored QR code, which it generally can't
  read. No such camera has been seen; if it happens, `--device` a different
  node.
- **Busy cameras.** UVC cameras are usually exclusive. If a video call holds the
  camera, ffmpeg gets EBUSY and the scan fails with that message. The relay
  loopback (`/dev/video50`) accepts several readers, so it works alongside, for
  example, a browser call.
- **No V4L2 node at all.** On libcamera-only setups (IPU6 without
  `v4l2-relayd`) no candidate exists, and the script asks for
  `FLOATING_PLAYER_CAMERA`. A PipeWire/libcamera fallback
  (`gst-launch-1.0 libcamerasrc|pipewiresrc …`) isn't implemented because this
  machine doesn't need it. It would slot in as another input in
  `start_capture`.
- **Privacy shutter.** Some laptops report the camera shutter as
  "unsupported", so its state can't be read. A closed shutter shows up
  only as a black picture, which triggers the hint after 10 s.
- **Small QR codes.** The decode stream is limited to 1280 px wide. A phone
  should fill roughly a quarter of the preview for a reliable read.
- **Dependencies:** `ffmpeg`, `zbar` (zbarimg), `v4l-utils` and `mpv`.
  Optional: `notify-send`, `jq` (only used by the fallback placement), and
  ImageMagick `magick` (only used by the black-picture hint). Without `mpv`, the
  scan runs without a preview.
