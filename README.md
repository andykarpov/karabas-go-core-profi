# Karabas Go Profi Core

A port of the Karabas Pro main core to the Karabas Go hardware

## What's done:
- True turbo 28 MHz with no-wait mem cycles
- Floppy disk support on the Go (the VG93 model of [FD1793_1818VG93](https://github.com/demyanenko-d/FD1793_1818VG93) on the CPU clock, TurboFDC always on)
- CF card by Profi / NemoIDE standard, or a virtual HDD image from the SD card (OSD: HDD = Image, file HDF0: .img .hdf .vhd)
- General Sound (2MB) @ 16MHz
- Soundrive / Covox
- Turbosound + FM
- SAA1099
- OPL2
- MIDI by Dream SAM2596
- Tape monitor in the OSD (Menu+T: off / in / out / both): the tape input and the tape output (MIC) heard in the mix
- RTC
- DivMMC / ZC support
- ESP8266 (ZXUNO, Zifi and ZXEVO standard)
- RS232 over USB (Zifi and ZXEVO standard), on the core serial port of the board (the second USB serial port, `/dev/serial/by-id/usb-Karabas_Go_<serial>-if02` on Linux)
- OSD support
- 2x Sega/Atari Joysticks (go)
- USB keyboard, mouse, joystiks
- VGA 8-8-8 (go), HDMI output (mini/minig)

## esxDOS 0.9.0 on SD card #2

Since build 26112002 the DivMMC of the core has the [esxDOS 0.9.0](https://www.esxdos.org/) ROM (in `profi.kg`, OSD DivMMC = On). This ROM checks the version of `SYS/ESXDOS.SYS` and does not start with the system files of 0.8.x, so update SD card #2 together with the core:

- copy the `SYS` and `BIN` folders of [esxdos090.zip](https://www.esxdos.org/files/esxdos090.zip) to the root of SD card #2 (the system commands are in `SYS/BIN` now; their old copies in `BIN` are not used any more);
- long file names: take the new `SYS/CONFIG/ESXDOS.CFG` or add the line `LFN=1` to yours;
- ZX Next on the same card: replace `machines/next/ESXMMC.BIN` with `ROMS/esxdos-0.9.0-divmmc.bin` of the archive, renamed to `ESXMMC.BIN` (the Next machines with DivMMC need the same version as `SYS`);
- `NMI.SYS` / `RTC.SYS` made for older esxDOS versions must be rebuilt for the new addresses ($2000 / $2F00);
- the ROM itself is in `profi.kg`: do not flash it with the `FLASHERS` tapes of the archive.

