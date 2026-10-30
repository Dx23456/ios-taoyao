# taoyao UEFI CI build

The workflow builds the Project Silicium / Mu-Silicium taoyao platform from the device's own official XBL firmware.

## Required Actions secrets

Add these under Settings → Secrets and variables → Actions:

- `TAOYAO_XBL_URL`: HTTPS URL to official taoyao `xbl.img`, accessible to curl without interactive login.
- `TAOYAO_XBL_SHA256`: exact 64-character SHA-256 digest.

The workflow verifies the digest, extracts Qualcomm DXE files with UEFIReader, checks required inputs, and builds the 2 MiB UEFI FD plus BootShim. Do not commit XBL or extracted vendor files.

## Run

Open Actions → Build taoyao Silicium UEFI → Run workflow on the taoyao development branch. Download the short-lived `taoyao-silicium-uefi-<commit>` artifact when it completes.

The artifact contains `SILICIUM_UEFI.fd`, `BootShim.bin`, `taoyao.dtb`, `BUILD-INFO.txt`, and `SHA256SUMS`. The FD contains vendor DXE binaries; keep the repository and artifact private and do not redistribute without appropriate rights.

## Safety

A successful build proves compilation and packaging only. It does not prove XBL/ABL can launch the image, runtime memory-map correctness, or XNU boot. The workflow does not run `fastboot boot` or `fastboot flash`.

Never flash these outputs to `abl`, `xbl`, `boot`, `vendor_boot`, `dtbo`, or any other partition. A separately reviewed, non-destructive launch path is required before handset testing.
