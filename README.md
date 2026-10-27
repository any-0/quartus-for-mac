# Quartus für Mac

Intel Quartus Prime Lite und ein Programmierer für das DE0-Nano auf Macs mit Apple-Chip, mit einem einzigen Befehl.

Quartus gibt es nur für x86-Windows und -Linux. Deshalb läuft es hier in einer kleinen NixOS-VM
(Apples Virtualization.framework, über [microvm.nix](https://github.com/microvm-nix/microvm.nix) und vfkit)
und wird von Rosetta übersetzt. Das Board wird direkt von macOS aus mit
[openFPGALoader](https://github.com/trabucayre/openFPGALoader) programmiert, weil die VM keine USB-Geräte sieht.

## Installation

Öffne das Terminal, füge diese Zeile ein, drück Return und gib dein Mac-Passwort ein, wenn danach gefragt wird:

```bash
curl -fsSL https://raw.githubusercontent.com/any-0/quartus-for-mac/main/setup | bash
```

Das dauert 30–90 Minuten, das meiste davon ist Download. Der Mac geht währenddessen nicht in den Ruhezustand.
Falls es zwischendurch abbricht, führ einfach dieselbe Zeile noch einmal aus.

**Voraussetzungen:** ein Mac mit Apple-Chip (M1 oder neuer), macOS 14 oder neuer, 8 GB Arbeitsspeicher und etwa 45 GB freier Speicherplatz.

## Benutzung

- **Quartus** (im Dock) öffnet Quartus. Wenn du Quartus schließt, schließt sich auch das Fenster.
- Speichere deine Projekte im Ordner **FPGA** in deinem Benutzerordner. Es ist derselbe Ordner auf dem Mac und in Quartus.
- Nach dem Kompilieren das Board per USB anschließen und auf **Program DE0-Nano** klicken:
  - **Load**: Das Design läuft, bis das Board vom Strom getrennt wird.
  - **Save**: Das Design wird in den Flash-Speicher des Boards geschrieben und bleibt dort.

## Was eingerichtet wird

- Rosetta, falls es noch fehlt
- [Nix](https://github.com/NixOS/nix-installer) (die offizielle Version, kein Konto nötig)
- [nix-darwin](https://github.com/nix-darwin/nix-darwin) mit `darwin.linux-builder-vz` aus nixpkgs, einem Linux-Builder,
  der x86_64-Pakete über Rosetta baut
- Eine NixOS-VM mit XFCE, die sich automatisch anmeldet und Quartus Prime Lite 25.1 startet (nur Cyclone IV).
  Zu jeder kompilierten `.sof`-Datei wird automatisch eine `.rbf`-Datei daneben geschrieben, die der Programmierer verwendet.
- Die beiden Apps in `~/Applications`, im Dock abgelegt

Die Konfiguration liegt danach in `~/.config/quartus-mac`, die Festplatte der VM in `~/.local/share/quartus-vm`.

## Einschränkungen

- Kein Questa-Simulator: Er braucht 32-Bit-x86, und das kann Rosetta nicht ausführen. Stattdessen sind Icarus Verilog und GTKWave in der VM installiert.
- Kein Signal Tap und kein anderes Live-JTAG-Debugging aus Quartus heraus, weil die VM keinen USB-Zugriff hat.
- Der Programmierer ist auf das DE0-Nano eingestellt (`openFPGALoader -b de0nano`).

## Deinstallation

```bash
bash ~/.config/quartus-mac/uninstall.sh
```

Das entfernt die Apps, die VM, nix-darwin und Nix. Projekte in `~/FPGA` bleiben erhalten.
