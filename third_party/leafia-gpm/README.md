# Leafia's GPM deltas

`ev6.HKMC_GPM.tbt.lpd` and `neev.HKMC_GPM.tbt.lpd` are copied unchanged from
[HMG Leafia Plus](https://github.com/VysseCodes/HMG-Leafia-Plus) (`patches/ev6/` and
`patches/neev/`, commit db371907d20d340c791e1cab6502d7ae2e7c4dd6), GPL-3.0 (`LICENSE`).

Each rebuilds Leafia v1.0.5's turn-by-turn `classes.dex` for `HKMC_GPM` from that
car's stock `HKMC_GPM.odex` (EV6 US/Canada `96cd7c27…`, Ioniq 5 US `6e67470f…`).
Both give the same `classes.dex` (md5 `6124a666b2ae11883e91de85c19389d2`): the
package rebuilds it on the head unit from the stock odex in Leafia's own backup, and
our `classes.dex.lpd` turns that into ours. No Hyundai/Kia/Google bytes are in either file
beyond what bsdiff needs to rebuild the target from the car's own original.
