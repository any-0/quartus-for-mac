# Quartus für Mac

Intel Quartus Prime Lite und ein Programmierer für das DE0-Nano auf Macs mit Apple-Chip.

Quartus gibt es nur für Windows und Linux auf Intel-Prozessoren. Hier läuft es deshalb in einer kleinen Linux-VM
und wird von Rosetta übersetzt. Das Board wird direkt vom Mac aus mit
[openFPGALoader](https://github.com/trabucayre/openFPGALoader) programmiert.

## Installation

Terminal öffnen, diese Zeile einfügen, Enter drücken und das Mac-Passwort eingeben:

```bash
curl -fsSL https://raw.githubusercontent.com/any-0/quartus-for-mac/main/setup | bash
```

Die Installation dauert 30 bis 90 Minuten, der Großteil davon ist Download.
Bricht sie ab, einfach dieselbe Zeile noch einmal ausführen.

Voraussetzungen: Mac mit M1 oder neuer, macOS 14 oder neuer, 8 GB Arbeitsspeicher, etwa 60 GB freier Speicherplatz
während der Installation (danach belegt alles etwa 25 GB).

## Benutzung

- **Quartus** im Dock öffnet Quartus.
- Projekte im Ordner **FPGA** im Benutzerordner speichern. Derselbe Ordner ist auch in Quartus sichtbar.
- Nach dem Kompilieren das Board per USB anschließen und **Program DE0-Nano** öffnen:
  - **Load** lädt das Design, bis das Board vom Strom getrennt wird.
  - **Save** speichert das Design dauerhaft auf dem Board.
- Für die Simulation mit Questa braucht man eine kostenlose Lizenz von Altera. Wie das geht, steht in
  `Questa-Lizenz.txt` im FPGA-Ordner.

## Technisches

- [Nix](https://github.com/NixOS/nix-installer) mit [nix-darwin](https://github.com/nix-darwin/nix-darwin)
  und `darwin.linux-builder-vz` aus nixpkgs, das x86_64-Pakete über Rosetta baut
- Eine NixOS-VM über [microvm.nix](https://github.com/microvm-nix/microvm.nix) und vfkit, mit XFCE,
  Quartus Prime Lite 25.1 (nur Cyclone IV) und Questa Starter Edition. Zu jeder kompilierten `.sof`-Datei wird
  automatisch eine `.rbf`-Datei erzeugt.
- Der Linux-Builder läuft nur während der Installation und wird danach mitsamt seiner Festplatte entfernt.
- Konfiguration in `~/.config/quartus-mac`, die Festplatte der VM in `~/.local/share/quartus-vm`

Nicht enthalten ist Signal Tap, weil die VM keinen USB-Zugriff hat. Aus demselben Grund zeigt Quartus unter
Hardware Setup kein Board an; programmiert wird über **Program DE0-Nano**.

## Deinstallation

```bash
bash ~/.config/quartus-mac/uninstall.sh
```

Projekte im Ordner FPGA bleiben erhalten.
