# taoyao iOS 16.5 userland artifact

This note describes how to retrieve and inspect the owner-encrypted output from the
GitHub Actions userland build. It does **not** describe a taoyao boot procedure.

## Build record

- Repository: `Dx23456/ios-taoyao`
- Branch: `work/taoyao-xnu-platform-preflight`
- Commit: `ff7b8454b7acbfc6a3da7a8926373fd8751d8c37`
- Workflow run: [41048098725](https://github.com/Dx23456/ios-taoyao/actions/runs/41048098725)
- Artifact: `hakios-ios16.5-userland-encrypted-ff7b8454b7acbfc6a3da7a8926373fd8751d8c37`
- Artifact ID: `12973284132`
- GitHub artifact ZIP size: 2,391,993,682 bytes
- GitHub artifact SHA-256: `c1d907d0f0795c1f7d33908322249a3f136ec9dd1e999206c518399c50fb0e1c`
- Expiry: 2026-11-06 11:34 UTC

The workflow uploaded only the age-encrypted tarball and its checksum. The age private
key was not placed in the repository or in the workflow.

## Retrieve

Open the workflow run above, scroll to **Artifacts**, and download the encrypted artifact.
The downloaded file is a ZIP archive. Extract it with MT Manager or another ZIP tool.
It should contain:

- `hakios-ios16.5-userland-ff7b8454b7acbfc6a3da7a8926373fd8751d8c37.tar.gz.age`
- `hakios-ios16.5-userland-ff7b8454b7acbfc6a3da7a8926373fd8751d8c37.tar.gz.age.sha256`

Verify the checksum before decryption. On a Linux/Android shell with `sha256sum`:

```sh
sha256sum -c hakios-ios16.5-userland-ff7b8454b7acbfc6a3da7a8926373fd8751d8c37.tar.gz.age.sha256
```

If `sha256sum` is unavailable, calculate the digest with OpenSSL and compare it
with the checksum file:

```sh
openssl dgst -sha256 hakios-ios16.5-userland-ff7b8454b7acbfc6a3da7a8926373fd8751d8c37.tar.gz.age
```

## Decrypt on the Xiaomi 12 Lite

Use the ARM64 `age` binary already obtained for the phone. Run it from an executable
location such as `/data/local/tmp`, not directly from shared storage. Keep the private
key file in private app storage or another location with appropriately restricted access.

Replace the two placeholder paths below with the actual paths on the phone:

```sh
/data/local/tmp/hakios-age/age -d \
  -i /path/to/private-age-key.txt \
  -o /sdcard/HakiOS/ios165-userland.tar.gz \
  /sdcard/HakiOS/hakios-ios16.5-userland-ff7b8454b7acbfc6a3da7a8926373fd8751d8c37.tar.gz.age
```

Never paste, upload, commit, or send the `AGE-SECRET-KEY-1...` private key. The public
`age1...` recipient is safe to publish; the private key must remain with its owner.

Inspect the archive before extracting it:

```sh
tar -tzf /sdcard/HakiOS/ios165-userland.tar.gz
```

Expected members:

- `userland/root.apfs`
- `userland/system.apfs`
- `xnuloader/identity.h`
- `xnuloader/loader.efi`
- `userland/taoyao-userland-audit.txt`
- `userland/taoyao-userland-SHA256SUMS`

Extract to a separate staging directory, not over the repository or an existing boot
package. Review the audit and checksum manifest before using any file.

## Compatibility warning

This workflow extracts the iOS 16.5 system from the iPhone X donor IPSW
(`iPhone10,3` / `iPhone10,6`, build 20F66). Its generated `identity.h` is a donor
identity, not a native Xiaomi 12 Lite identity. The APFS images are not yet validated
against taoyao's kernel ABI, drivers, storage path, memory handoff, or hardware.

Do not flash these files. Do not use the existing `boot.img` alias as a normal Android
boot image. Do not run `fastboot boot` or `./xl enter` on taoyao until the separate
UEFI and XNU hardware safety gates in `devices/taoyao/xnu/SM7325_PORTING.md` have
passed. A successful image build and APFS audit are not evidence of a physical boot.
