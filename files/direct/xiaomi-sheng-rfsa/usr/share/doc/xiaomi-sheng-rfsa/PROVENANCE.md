# Xiaomi sheng RFSA provenance

These proprietary Qualcomm Hexagon DSP libraries were extracted unchanged
from the unpacked official Android image in `/home/lzx/ROM/backup`:

- `vendor/lib/rfsa/adsp`
- `odm/lib/rfsa/adsp`
- `odm/mount/camera/lib/rfsa/adsp`

Source vendor fingerprint:
`Xiaomi/mivendor_pad8550_cn/mivendor:13/TKQ1.221114.001/OS3.0.304.0.WNXCNXM:user/release-keys`

`SHA256SUMS` records every packaged RFSA file relative to the device firmware
root. The package uses `options=('!strip')` so makepkg cannot alter DSP6 ELF
objects.
