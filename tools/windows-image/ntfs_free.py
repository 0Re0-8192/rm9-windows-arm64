"""Free space of the phone's windows partition (reads only the $Bitmap over adb).  Run inside WSL."""
import sys
sys.argv = ['x']
from ntfs_remote import Remote, NTFS
fh = Remote()
n = NTFS(fh)
bm = n.mft.get('$Bitmap').open().read()
used = sum(bin(b).count('1') for b in bm)
cl = n.cluster_size
tot_clusters = 33442999 * 4096 // cl
print('cluster', cl, 'total GiB %.1f' % (tot_clusters * cl / 2**30), 'used GiB %.1f' % (used * cl / 2**30), 'free GiB %.1f' % ((tot_clusters - used) * cl / 2**30))
