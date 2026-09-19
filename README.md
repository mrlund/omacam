# Omacam

Crop the part of a 4K webcam where you actually sit, and present that as a
1080p virtual camera. Meeting apps see a normal camera named **Omacam**. You
get a sharp downsample from 4K instead of a smeary zoom of a 1080p stream.

This is an [Omarchy](https://omarchy.org/) shell plugin: a bar toggle plus a
fullscreen framer. It wraps the same idea as a manual `v4l2loopback` + `ffmpeg`
pipeline, without leaving that pipeline running all day.

## What you get

- **Bar icon** — left-click starts or stops the virtual camera. Right-click
  opens the framer. The icon lights up while Omacam is live.
- **Framer overlay** — a still of the full sensor with a draggable 16:9 crop,
  corner handles, scroll-wheel zoom, and sliders. Defaults match a typical
  “sit in the middle of a 4K frame” crop (`zoom 30`, nudge up 30px, right 100px).
- **On-demand ffmpeg** — the plugin UI is idle until you turn the camera on.
  The encode/crop process is a separate session, so restarting the Omarchy
  shell does not kill a call.
- **Picture sliders** — brightness, contrast, and saturation. If the camera
  has those UVC knobs, Omacam uses them (no extra CPU, live). Otherwise it
  falls back to a cheap ffmpeg `eq` on the 1080p crop. The overlay labels
  each slider `camera` or `software`.

## Install

Omarchy’s plugin installer only copies QML. It will **not** load a kernel
module or install packages. You need three steps once; after that the bar
icon is enough.

### 1. Packages

On Omarchy these are usually already present:

```bash
omarchy pkg add ffmpeg v4l2loopback-dkms v4l2loopback-utils
```

### 2. Virtual camera (once, needs sudo)

`v4l2loopback` must load with `exclusive_caps=1` or Chrome / Zoom often refuse
the device. The plugin cannot do this itself.

After the plugin is on disk (step 3), run:

```bash
sudo ~/.config/omarchy/plugins/mrlund.omacam/scripts/install-loopback.sh
```

Or, before installing the plugin, copy these two files by hand:

```bash
echo v4l2loopback | sudo tee /etc/modules-load.d/v4l2loopback.conf

echo 'options v4l2loopback exclusive_caps=1 card_label="Omacam" devices=1' \
  | sudo tee /etc/modprobe.d/v4l2loopback.conf

sudo modprobe v4l2loopback exclusive_caps=1 card_label="Omacam" devices=1
```

That last `modprobe` is only needed until the next reboot; after that the
module loads on its own. In the meeting app, pick **Omacam**, not the Logitech
device.

If you skip this step, preview still works (it uses the real camera) but
**Start** fails with “no loopback device” after a reboot. Starting from the
bar will then ask for your password once via a polkit prompt and run the
same setup.

If you already had a hand-rolled “Cropped Webcam” loopback, Omacam will still
find it. After a reboot it will show up as **Omacam** instead.

### 3. Plugin

```bash
omarchy plugin add https://github.com/mrlund/omacam.git --enable
```

That clones into `~/.config/omarchy/plugins/mrlund.omacam/` and puts **Omacam**
on the right side of the bar. You can move it with:

```bash
omarchy bar move mrlund.omacam --section right
```

## Usage

1. Right-click the webcam icon and frame yourself. **Start cropped camera**
   (or Enter) saves the crop and starts the pipeline.
2. In Zoom / Meet / Chromium, choose **Omacam**.
3. Left-click the icon when the call is over. That is what drops the CPU/USB
   load — leaving it running is the expensive part, not having the plugin
   enabled.

Escape or a click outside the overlay cancels framing. If the camera was
already live, cancel puts the previous crop back and restarts it.

Keyboard in the overlay: arrows nudge the crop, Enter starts, Escape cancels.

The last crop lives in `~/.config/omacam/config.json`. Left-click on the bar
reuses it without opening the overlay.

You can also drive it from a terminal:

```bash
~/.config/omarchy/plugins/mrlund.omacam/scripts/omacam start
~/.config/omarchy/plugins/mrlund.omacam/scripts/omacam stop
~/.config/omarchy/plugins/mrlund.omacam/scripts/omacam status
```

## Cost

The plugin does **not** have to run the camera all the time. Enabled QML is
cheap. **ffmpeg** is not: while Omacam is live it decodes 4K MJPEG (that is
most of the CPU), crops, and writes 1080p YUYV into the loopback device.

Most USB webcams send MJPEG, not H.264, so NVIDIA NVDEC usually cannot take
that decode. Omacam probes once (first time you open the framer, or **Retry
GPU decode**) and stores `cpu` or `cuda` in `~/.config/omacam/config.json`.
Start only reads the flag. On 4:2:2 MJPEG cameras the result is almost
always `cpu`; that is expected, not a failed install.

When the crop is already about 1920×1080, scale is skipped (1:1 pixels).
Otherwise it uses bilinear rather than Lanczos. The frame queue is kept
small so RSS stays down. Software picture adjustments, when used, run on
the 1080p crop, not the 4K frame.

Turn it off between calls. Do not autostart it at login.

The framer pauses the pipeline for a moment so it can grab the physical
camera. You cannot preview 4K and stream it at the same time; UVC devices
are exclusive.

## Uninstall

```bash
omarchy plugin remove mrlund.omacam
```

That does not unload `v4l2loopback` or remove the two files under `/etc`.
Leave them if you still want a virtual camera; otherwise:

```bash
sudo rm /etc/modules-load.d/v4l2loopback.conf /etc/modprobe.d/v4l2loopback.conf
sudo modprobe -r v4l2loopback
```

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Bar tooltip “Need: v4l2loopback module…” | Step 2 was skipped, or you have not rebooted / `modprobe`’d |
| Meeting app shows a black Omacam | Start the pipeline *before* opening the camera picker |
| Logitech camera missing from apps | That is expected while Omacam is live — ffmpeg holds it |
| `ffmpeg exited immediately` | Another app already has the webcam, or the loopback node is missing |
| Crop looks soft | Make sure **4K source** is on in the overlay so the crop is a downsample |

`omacam doctor` prints a JSON readiness check.

## License

MIT.
