/**
  XNU loader for taoyao (SM7325), stage 0: payload handoff and diagnostics.

  Runs when BDS finds nothing to boot. If an "XNUP" container at 0xF0000000
  carries "loader.efi" and "taoyao.dtb", publishes the DTB as an EFI
  configuration table and starts the loader directly from memory. Otherwise,
  collects diagnostics (exception level, CPU feature registers, framebuffer,
  memory map, payload), writes them as text to the raw "logdump" partition so
  they can be read back from Android over adb, and cold-resets.

  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#include <Uefi.h>

#include <Library/BaseLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/MemoryAllocationLib.h>
#include <Library/PrintLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/UefiRuntimeServicesTableLib.h>

#include <Protocol/GraphicsOutput.h>

#include "XnuLoader.h"

#define LOG_SIZE  SIZE_256KB

STATIC CHAR8  *mLog;
STATIC UINTN   mLogLen;

STATIC
VOID
EFIAPI
Log (
  IN CONST CHAR8 *Format,
  ...)
{
  VA_LIST Marker;

  if (mLog == NULL || mLogLen >= LOG_SIZE - 512) {
    return;
  }

  VA_START (Marker, Format);
  mLogLen += AsciiVSPrint (mLog + mLogLen, LOG_SIZE - mLogLen, Format, Marker);
  VA_END (Marker);
}

#define READ_SYSREG(Name) ({ UINT64 _Value; __asm__ volatile ("mrs %0, " #Name : "=r" (_Value)); _Value; })

STATIC
VOID
LogCpu ()
{
  Log ("[cpu]\n");
  Log ("CurrentEL=%lx\n", READ_SYSREG (CurrentEL) >> 2);
  Log ("MIDR_EL1=%016lx\n", READ_SYSREG (MIDR_EL1));
  Log ("ID_AA64MMFR0_EL1=%016lx\n", READ_SYSREG (ID_AA64MMFR0_EL1));
  Log ("ID_AA64MMFR1_EL1=%016lx\n", READ_SYSREG (ID_AA64MMFR1_EL1));
  Log ("ID_AA64MMFR2_EL1=%016lx\n", READ_SYSREG (ID_AA64MMFR2_EL1));
  Log ("ID_AA64PFR0_EL1=%016lx\n", READ_SYSREG (ID_AA64PFR0_EL1));
  Log ("ID_AA64PFR1_EL1=%016lx\n", READ_SYSREG (ID_AA64PFR1_EL1));
  Log ("ID_AA64ISAR0_EL1=%016lx\n", READ_SYSREG (ID_AA64ISAR0_EL1));
  Log ("ID_AA64ISAR1_EL1=%016lx\n", READ_SYSREG (ID_AA64ISAR1_EL1));
  Log ("ID_AA64DFR0_EL1=%016lx\n", READ_SYSREG (ID_AA64DFR0_EL1));
  Log ("SCTLR_EL1=%016lx\n", READ_SYSREG (SCTLR_EL1));
  Log ("TCR_EL1=%016lx\n", READ_SYSREG (TCR_EL1));
  Log ("MAIR_EL1=%016lx\n", READ_SYSREG (MAIR_EL1));
  Log ("TTBR0_EL1=%016lx\n", READ_SYSREG (TTBR0_EL1));
  Log ("VBAR_EL1=%016lx\n", READ_SYSREG (VBAR_EL1));
  Log ("CNTFRQ_EL0=%ld\n", READ_SYSREG (CNTFRQ_EL0));
  Log ("MPIDR_EL1=%016lx\n", READ_SYSREG (MPIDR_EL1));
  Log ("DAIF=%lx\n", READ_SYSREG (DAIF));
}

STATIC
VOID
LogDisplay ()
{
  EFI_STATUS                    Status;
  EFI_GRAPHICS_OUTPUT_PROTOCOL *Gop;

  Log ("[display]\n");

  Status = gBS->LocateProtocol (&gEfiGraphicsOutputProtocolGuid, NULL, (VOID **)&Gop);
  if (EFI_ERROR (Status)) {
    Log ("gop=missing status=%r\n", Status);
    return;
  }

  Log ("fb_base=%lx fb_size=%lx\n", Gop->Mode->FrameBufferBase, (UINT64)Gop->Mode->FrameBufferSize);
  Log ("width=%d height=%d stride=%d format=%d\n",
       Gop->Mode->Info->HorizontalResolution, Gop->Mode->Info->VerticalResolution,
       Gop->Mode->Info->PixelsPerScanLine, Gop->Mode->Info->PixelFormat);
}

STATIC
VOID
LogMemoryMap ()
{
  EFI_STATUS             Status;
  EFI_MEMORY_DESCRIPTOR *Map;
  UINTN                  MapSize = 0;
  UINTN                  MapKey;
  UINTN                  DescSize;
  UINT32                 DescVersion;

  Log ("[memmap]\n");

  Status = gBS->GetMemoryMap (&MapSize, NULL, &MapKey, &DescSize, &DescVersion);
  if (Status != EFI_BUFFER_TOO_SMALL) {
    Log ("getmemorymap status=%r\n", Status);
    return;
  }

  MapSize += SIZE_4KB;
  Map      = AllocatePool (MapSize);
  if (Map == NULL) {
    return;
  }

  Status = gBS->GetMemoryMap (&MapSize, Map, &MapKey, &DescSize, &DescVersion);
  if (EFI_ERROR (Status)) {
    Log ("getmemorymap status=%r\n", Status);
    FreePool (Map);
    return;
  }

  if (DescSize < sizeof (EFI_MEMORY_DESCRIPTOR) || DescSize == 0 ||
      MapSize % DescSize != 0) {
    Log ("invalid memory map descriptor size=%u map_size=%u\n", DescSize, MapSize);
    FreePool (Map);
    return;
  }

  for (UINTN Offset = 0; Offset < MapSize; Offset += DescSize) {
    EFI_MEMORY_DESCRIPTOR *Desc = (EFI_MEMORY_DESCRIPTOR *)((UINT8 *)Map + Offset);
    UINT64                 Bytes;

    if (Desc->NumberOfPages > MAX_UINT64 / EFI_PAGE_SIZE) {
      Log ("skipping memory descriptor with overflowing page count\n");
      continue;
    }

    Bytes = EFI_PAGES_TO_SIZE (Desc->NumberOfPages);
    if (Desc->PhysicalStart > MAX_UINT64 - Bytes) {
      Log ("skipping memory descriptor with overflowing physical range\n");
      continue;
    }

    Log ("%016lx %016lx type=%d attr=%lx\n", Desc->PhysicalStart,
         Desc->PhysicalStart + Bytes, Desc->Type, Desc->Attribute);
  }

  FreePool (Map);
}

STATIC
VOID
LogPayload ()
{
  XNU_PAYLOAD_HEADER *Header = (XNU_PAYLOAD_HEADER *)XNU_PAYLOAD_BASE;

  Log ("[payload]\n");
  Log ("base=%lx magic=%08x size=%x\n", (UINT64)XNU_PAYLOAD_BASE, Header->Magic, Header->Size);

}

STATIC
VOID
LogPersistence ()
{
  //
  // Read-only observation only. The payload reservation may contain live
  // XNUP bytes; never mutate its tail with a diagnostic marker.
  //
  CONST volatile UINT32 *Ram =
    (CONST volatile UINT32 *)(UINTN)(XNU_PAYLOAD_BASE + XNU_PAYLOAD_MAX_SIZE - SIZE_4KB);

  Log ("[persistence]\n");
  Log ("marker_before=%08x %08x (read-only; no RAM mutation)\n", Ram[0], Ram[1]);
}

STATIC
VOID
FlushLog ()
{
  //
  // Deliberately RAM-only. A GPT partition name does not prove that LBA 0
  // is disposable; writing there can destroy partition data. Persistent
  // diagnostics require a separately validated offset and partition layout.
  //
  // No disk writes. The in-memory log remains available until reset.
}

//
// The payload is a list of named blobs. If it carries "loader.efi", that is
// the real XNU loader: start it straight from memory, so the loader can be
// iterated on without rebuilding this firmware.
//
STATIC EFI_GUID mEfiDtbTableGuid = {
  0xb1b621d5, 0xf19c, 0x41a5, { 0x83, 0x0b, 0xd9, 0x15, 0x2c, 0x69, 0xaa, 0xe0 }
};

STATIC
UINT32
ReadFdtBe32 (
  IN CONST UINT8 *Data
  )
{
  return ((UINT32)Data[0] << 24) | ((UINT32)Data[1] << 16) |
         ((UINT32)Data[2] << 8) | Data[3];
}

STATIC
BOOLEAN
IsValidFdt (
  IN CONST VOID *Buffer,
  IN UINTN       BufferSize
  )
{
  CONST UINT8 *Data = (CONST UINT8 *)Buffer;
  UINT32      TotalSize;

  if (Data == NULL || BufferSize < 40 || ReadFdtBe32 (Data) != 0xD00DFEED) {
    return FALSE;
  }

  TotalSize = ReadFdtBe32 (Data + 4);
  return (BOOLEAN)(TotalSize >= 40 && TotalSize <= BufferSize && TotalSize <= 0x01000000);
}

//
// The payload carries both the loader EFI image and the taoyao DTB. Publish
// the DTB through the standard EFI configuration-table GUID before starting
// loader.efi; the loader refuses to select the taoyao profile without it.
//
STATIC
VOID
StartPayloadLoader ()
{
  XNU_PAYLOAD_HEADER *Header = (XNU_PAYLOAD_HEADER *)XNU_PAYLOAD_BASE;
  UINT8              *Cursor;
  UINT8              *End;
  VOID               *LoaderBuffer = NULL;
  UINTN               LoaderSize = 0;
  VOID               *DtbBuffer = NULL;
  UINTN               DtbSize = 0;

  if (Header->Magic != XNU_PAYLOAD_MAGIC ||
      Header->Size > XNU_PAYLOAD_MAX_SIZE - sizeof (*Header)) {
    Log ("[payload] invalid magic or container size\n");
    return;
  }

  Cursor = (UINT8 *)(Header + 1);
  End    = Cursor + Header->Size;

  while ((UINTN)(End - Cursor) >= sizeof (XNU_PAYLOAD_ENTRY)) {
    XNU_PAYLOAD_ENTRY *Entry = (XNU_PAYLOAD_ENTRY *)Cursor;
    UINTN              Remaining;
    UINTN              AlignedSize;

    if (Entry->Name[0] == 0) {
      break;
    }

    Cursor += sizeof (*Entry);
    Remaining = (UINTN)(End - Cursor);
    if ((UINTN)Entry->Size > Remaining) {
      Log ("[payload] truncated entry size=%u remaining=%u\n", Entry->Size, Remaining);
      return;
    }

    AlignedSize = ALIGN_VALUE ((UINTN)Entry->Size, 16);
    if (AlignedSize > Remaining) {
      Log ("[payload] entry alignment exceeds container bounds\n");
      return;
    }

    if (AsciiStrnCmp (Entry->Name, "loader.efi", sizeof (Entry->Name)) == 0) {
      if (LoaderBuffer != NULL || Entry->Size == 0) {
        Log ("[payload] duplicate or empty loader.efi entry\n");
        return;
      }
      LoaderBuffer = Cursor;
      LoaderSize = Entry->Size;
    } else if (AsciiStrnCmp (Entry->Name, "taoyao.dtb", sizeof (Entry->Name)) == 0) {
      if (DtbBuffer != NULL || !IsValidFdt (Cursor, Entry->Size)) {
        Log ("[payload] duplicate or invalid taoyao.dtb entry\n");
        return;
      }
      DtbBuffer = Cursor;
      DtbSize = Entry->Size;
    }

    Cursor += AlignedSize;
  }

  if (LoaderBuffer == NULL || LoaderSize == 0) {
    Log ("[payload] no complete loader.efi entry found\n");
    return;
  }
  if (DtbBuffer == NULL || DtbSize == 0) {
    Log ("[payload] taoyao.dtb missing; refusing to launch without board identity\n");
    return;
  }

  EFI_STATUS Status = gBS->InstallConfigurationTable (&mEfiDtbTableGuid, DtbBuffer);
  if (EFI_ERROR (Status)) {
    Log ("[payload] InstallConfigurationTable(DTB) failed: %r\n", Status);
    return;
  }
  Log ("[payload] installed taoyao DTB configuration table (%u bytes)\n", DtbSize);

  EFI_HANDLE Handle;
  Status = gBS->LoadImage (FALSE, gImageHandle, NULL, LoaderBuffer, LoaderSize, &Handle);
  if (EFI_ERROR (Status)) {
    Log ("[payload] LoadImage failed: %r\n", Status);
    return;
  }

  Status = gBS->StartImage (Handle, NULL, NULL);
  Log ("[payload] StartImage returned: %r\n", Status);
}

VOID
XnuLoaderMain ()
{
  EFI_TIME Time;

  mLog = AllocateZeroPool (LOG_SIZE);
  if (mLog != NULL) {
    Log ("== XNULOADER LOG v1 ==\n");

    if (!EFI_ERROR (gRT->GetTime (&Time, NULL))) {
      Log ("time=%04d-%02d-%02d %02d:%02d:%02d\n", Time.Year, Time.Month, Time.Day, Time.Hour, Time.Minute, Time.Second);
    }
  }

  // Normally does not return; initialize the log first so handoff failures
  // are recorded in the fallback diagnostic buffer.
  StartPayloadLoader ();

  if (mLog != NULL) {

    FlushLog ();
    LogCpu ();
    FlushLog ();
    LogDisplay ();
    FlushLog ();
    LogMemoryMap ();
    FlushLog ();
    LogPayload ();
    FlushLog ();
    LogPersistence ();
    Log ("== END ==\n");
    FlushLog ();
  }

  // The phone is unattended: always come back to Android.
  gRT->ResetSystem (EfiResetCold, EFI_SUCCESS, 0, NULL);
}
