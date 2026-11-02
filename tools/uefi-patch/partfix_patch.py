p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
code = r'''// Mu's PartitionDxe does not install Qualcomm's per-partition GPT-entry protocol FE2555BE-D716-4686-B9D0-79DB5921B70D that PIL's partition lookup needs
// (interface = EFI_PARTITION_ENTRY, name at +0x38).  Install it on modem_b only (sde partition 37, start LBA 355418, type basic-data): PIL requires exactly one match of the type GUID.
STATIC VOID
PartFixModem (VOID)
{
  STATIC EFI_GUID  FeGuid = { 0xFE2555BE, 0xD716, 0x4686, { 0xB9, 0xD0, 0x79, 0xDB, 0x59, 0x21, 0xB7, 0x0D } };
  STATIC EFI_GUID  BasicData = { 0xEBD0A0A2, 0xB9E5, 0x4433, { 0x87, 0xC0, 0x68, 0xB6, 0xB7, 0x26, 0x99, 0xC7 } };
  EFI_HANDLE  *H = NULL;
  UINTN       N = 0, I;

  if (EFI_ERROR (gBS->LocateHandleBuffer (ByProtocol, &gEfiBlockIoProtocolGuid, NULL, &N, &H))) {
    return;
  }
  for (I = 0; I < N; I++) {
    EFI_DEVICE_PATH_PROTOCOL  *Dp = NULL, *Node;

    if (EFI_ERROR (gBS->HandleProtocol (H[I], &gEfiDevicePathProtocolGuid, (VOID **)&Dp)) || Dp == NULL) {
      continue;
    }
    for (Node = Dp; !IsDevicePathEnd (Node); Node = NextDevicePathNode (Node)) {
      if (DevicePathType (Node) == MEDIA_DEVICE_PATH && DevicePathSubType (Node) == MEDIA_HARDDRIVE_DP) {
        HARDDRIVE_DEVICE_PATH  *Hd = (HARDDRIVE_DEVICE_PATH *)Node;
        if (Hd->PartitionNumber == 37 && Hd->PartitionStart == 355418ULL && Hd->SignatureType == 2) {
          UINT8  *E = AllocateZeroPool (128);
          UINTN  K;
          EFI_STATUS  St;
          STATIC CONST CHAR16  Nm[] = L"modem_b";

          CopyMem (E + 0, &BasicData, 16);
          CopyMem (E + 16, Hd->Signature, 16);
          *(UINT64 *)(E + 32) = Hd->PartitionStart;
          *(UINT64 *)(E + 40) = Hd->PartitionStart + Hd->PartitionSize - 1;
          for (K = 0; K < 8; K++) {
            *(UINT16 *)(E + 56 + 2 * K) = Nm[K];
          }
          St = gBS->InstallProtocolInterface (&H[I], &FeGuid, EFI_NATIVE_INTERFACE, E);
          PL ("PART modem_b handle %p: installed FE2555BE entry -> %r\n", H[I], St);
        }
      }
    }
  }
  FreePool (H);
}

'''
marker = '// ADSP.TXT + NOBOOT:'
assert marker in s and 'PartFixModem' not in s
s = s.replace(marker, code + marker, 1)
old = '    PartProbe ();'
s = s.replace(old, '    PartFixModem ();\n    PartProbe ();', 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
