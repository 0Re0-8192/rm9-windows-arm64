f=$(find /root/Mu-Silicium/Mu_Basecore -name ArmLib.h 2>/dev/null | head -1)
echo "$f"
grep -n -i "DataCache\|DisableMmu\|InvalidateTlb\|DisableInterrupts\|InstructionCache\|CleanInvalidate\|CleanData" "$f" | head -30
