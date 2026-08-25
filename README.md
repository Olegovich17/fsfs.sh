# fsfs.sh (fast strong flac splitter) ⚡

`fsfs.sh` is a powerful, fast, and robust Bash script designed for batch splitting single-file FLAC albums (`.flac` + `.cue`) into individual tracks.

The script is fully **encoding-agnostic** (automatically converting any garbled text/mojibake to UTF-8), handles both standard 16-bit audio files and **Hi-Res FLAC (24-bit/96kHz+)** flawlessly, and carefully preserves metadata tags.

---

## 🔥 Key Features

- 🎯 **FLAC-Focused:** Strictly specialized for flawless handling of FLAC containers.
- 🔤 **Auto UTF-8 Encoding:** No more mojibake in tags (`CP1251`, `CP866`, `ISO-8859-1`, `Shift-JIS`, etc., handled seamlessly via `uchardet`).
- 💎 **Full Hi-Res Support (24-bit+):** Uses `ffmpeg` for Hi-Res tracks (preventing junction clicks and ensuring precise track lengths via `-t`).
- ⚡ **High Speed:** Lightning-fast `shnsplit` utilization for standard 16-bit FLAC files.
- 🔍 **Smart CUE + FLAC Pairing:** Finds matches even with filename mismatches or double extensions (`Album.flac.cue`).
- 🏷️ **Clean Metadata:** Preserves `TITLE`, `ARTIST`, `ALBUM`, `ALBUMARTIST`, `TRACKNUMBER`, `DATE`/`YEAR`, and `GENRE`.
- 🛡️ **Safe Cleanup:** Option to automatically delete the original monolithic FLAC and CUE files post-splitting without data loss risks.

---

## 🛠️ Dependency Installation

The script relies on standard console audio utilities: `cuetools`, `shntool`, `flac`, `ffmpeg`, `iconv`, and `uchardet`.

You can install them automatically by running the script with the `-i` flag:
```bash
chmod +x fsfs.sh
./fsfs.sh --install-deps
```
*The script will automatically detect your package manager (apt, dnf, pacman, apk, zypper) and install the appropriate one.*

---

## 🚀 Usage

### Basic Syntax

```bash
./fsfs.sh [FLAGS] [PATH_TO_MEDIA_LIBRARY]
```

If the path is not specified, the script will process the **current directory**.

---

## 🚩 Available Flags

| Flag | Full Name | Description |
| :--- | :--- | :--- |
| `-d` | `--dry-run` | **Dry run.** Scans the media library and displays the found CUE+FLAC pairs without cutting anything. |
| `-s` | `--skip-existing` | Skip albums if the `splitted` folder already contains files. Useful when resuming interrupted processing. |
| `-k` | `--delete-original` | **Safe deletion.** Deletes the original `.flac` and `.cue` files only after a successful split and moves the tracks to the root of the album. |
| `-i` | `--install-deps` | Automatically install all required dependencies on the system. |
| `-r` | `--remove-deps` | Remove installed dependencies from the system. |
| `-h` | `--help` | Show usage help. |

---

## 💡 Usage Examples

#### 1. Check the media library before processing (Dry Run)
```bash
./fsfs.sh -d /path/to/music
```

#### 2. Split the entire media library in the `splitted/` folders
```bash
./fsfs.sh /path/to/music
```

#### 3. Split and replace originals with separate tracks (Clean Run)
Splits albums, removes the original monolithic FLAC and CUE, and places the finished tracks directly in the album folder:
```bash
./fsfs.sh -k /path/to/music
```

#### 4. Split only new albums (skipping existing ones)
```bash
./fsfs.sh -s /path/to/music
```

---

## 📜 License
MIT License — free to use, modify, and distribute.
