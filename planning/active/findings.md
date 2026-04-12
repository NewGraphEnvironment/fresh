# Findings

Three attempts:
1. No distance cap on cross-BLK → 11.7km segment survived
2. No cross-BLK at all → overcorrected (14.9 km vs 85.7)
3. This fix: Euclidean ST_Distance for cross-BLK, capped at connected_distance_max

Euclidean is an underestimate of network distance (straight line < river path). For a 3km cap, a segment 3km Euclidean might be 4-5km by stream. This means slightly more spawning survives than bcfishpass (which uses a network-aware approach). But it's much closer than either extreme.

Adams River verification: segment at measure 760 is ~9.3km Euclidean from lake rearing. 9300 > 3000 → removed. Correct.
