# C3HTTPRequest benchmark vs native HTTPRequest
```
commit 4041d55
Godot 4.7-stable (official) | Windows | AMD Ryzen 5 7600 6-Core Processor | forward_plus renderer
```
All timing values are in milliseconds. Tables show medians; five-number summary follows each section.

| ID       | Description                                              |
| -------- | -------------------------------------------------------- |
| nat_coop | native HTTPRequest node, cooperative (default) polling   |
| c3_coop  | C3HTTPRequest, cooperative (default) polling             |
| c3s_coop | C3HTTPRequest, cooperative polling, session (keep-alive) |
| nat_thr  | native HTTPRequest node, threaded polling                |
| c3_thr   | C3HTTPRequest, threaded polling                          |
| c3s_thr  | C3HTTPRequest, threaded polling, session (keep-alive)    |

## Single-request latency (median of 25 requests)
Round-trip time for a single small GET request across frame-rate caps.

| Frame rate | nat_coop | c3_coop | c3s_coop | nat_thr | c3_thr | c3s_thr |
| ---------- | -------- | ------- | -------- | ------- | ------ | ------- |
| uncapped   | 162.1    | 162.9   | 33.5     | 165.7   | 163.6  | 34.5    |
| 120 fps    | 183.3    | 174.9   | 41.7     | 166.6   | 166.5  | 41.5    |
| 60 fps     | 200.0    | 183.3   | 50.0     | 166.6   | 166.5  | 49.8    |
| 30 fps     | 233.3    | 199.9   | 66.7     | 166.6   | 166.5  | 66.5    |

| Label    | Trial    | Min   | Q1    | Median | Q3    | Max   |
| -------- | -------- | ----- | ----- | ------ | ----- | ----- |
| uncapped | c3_coop  | 158.9 | 161.3 | 162.9  | 165.1 | 186.1 |
| uncapped | c3_thr   | 162.1 | 162.9 | 163.6  | 167.1 | 173.0 |
| uncapped | c3s_coop | 33.0  | 33.2  | 33.5   | 33.6  | 37.6  |
| uncapped | c3s_thr  | 33.5  | 34.0  | 34.5   | 35.2  | 43.8  |
| uncapped | nat_coop | 158.6 | 161.1 | 162.1  | 165.2 | 167.9 |
| uncapped | nat_thr  | 160.8 | 163.0 | 165.7  | 167.4 | 175.4 |
| 120 fps  | c3_coop  | 174.9 | 174.9 | 174.9  | 174.9 | 183.3 |
| 120 fps  | c3_thr   | 166.5 | 166.5 | 166.5  | 166.5 | 183.2 |
| 120 fps  | c3s_coop | 33.3  | 41.7  | 41.7   | 41.7  | 50.0  |
| 120 fps  | c3s_thr  | 41.5  | 41.5  | 41.5   | 41.5  | 49.8  |
| 120 fps  | nat_coop | 183.3 | 183.3 | 183.3  | 183.3 | 208.3 |
| 120 fps  | nat_thr  | 166.5 | 166.6 | 166.6  | 174.9 | 191.6 |
| 60 fps   | c3_coop  | 183.2 | 183.2 | 183.3  | 183.3 | 199.9 |
| 60 fps   | c3_thr   | 166.4 | 166.5 | 166.5  | 183.1 | 183.3 |
| 60 fps   | c3s_coop | 33.3  | 33.5  | 50.0   | 50.0  | 50.4  |
| 60 fps   | c3s_thr  | 49.4  | 49.8  | 49.8   | 49.8  | 49.9  |
| 60 fps   | nat_coop | 199.9 | 200.0 | 200.0  | 200.0 | 233.3 |
| 60 fps   | nat_thr  | 166.5 | 166.5 | 166.6  | 166.6 | 199.9 |
| 30 fps   | c3_coop  | 199.9 | 199.9 | 199.9  | 199.9 | 266.6 |
| 30 fps   | c3_thr   | 166.5 | 166.5 | 166.5  | 166.5 | 199.9 |
| 30 fps   | c3s_coop | 66.7  | 66.7  | 66.7   | 66.7  | 66.7  |
| 30 fps   | c3s_thr  | 66.4  | 66.5  | 66.5   | 66.5  | 66.5  |
| 30 fps   | nat_coop | 233.3 | 233.3 | 233.3  | 233.3 | 233.4 |
| 30 fps   | nat_thr  | 166.5 | 166.5 | 166.6  | 199.9 | 199.9 |

## Small download: slow-start control vs. straddled IW10 (median of 25 runs, 60 fps)
Tests how TCP slow-start affects small responses.

| Body size | nat_coop | c3_coop | c3s_coop | nat_thr | c3_thr | c3s_thr |
| --------- | -------- | ------- | -------- | ------- | ------ | ------- |
| 10 KB     | 200.0    | 183.3   | 50.0     | 183.2   | 183.1  | 49.8    |
| 20 KB     | 200.0    | 199.9   | 50.0     | 199.8   | 199.9  | 49.8    |
| 400 KB    | 333.4    | 300.1   | 51.1     | 299.8   | 299.6  | 65.4    |

| Label  | Trial    | Min   | Q1    | Median | Q3    | Max   |
| ------ | -------- | ----- | ----- | ------ | ----- | ----- |
| 10 KB  | c3_coop  | 183.3 | 183.3 | 183.3  | 183.3 | 233.3 |
| 10 KB  | c3_thr   | 166.4 | 183.1 | 183.1  | 183.1 | 183.2 |
| 10 KB  | c3s_coop | 50.0  | 50.0  | 50.0   | 50.0  | 66.7  |
| 10 KB  | c3s_thr  | 49.8  | 49.8  | 49.8   | 49.8  | 83.2  |
| 10 KB  | nat_coop | 199.9 | 200.0 | 200.0  | 200.0 | 216.7 |
| 10 KB  | nat_thr  | 166.5 | 183.2 | 183.2  | 183.2 | 216.5 |
| 20 KB  | c3_coop  | 199.6 | 199.9 | 199.9  | 199.9 | 200.0 |
| 20 KB  | c3_thr   | 183.2 | 199.8 | 199.9  | 199.9 | 216.5 |
| 20 KB  | c3s_coop | 49.9  | 50.0  | 50.0   | 50.0  | 200.0 |
| 20 KB  | c3s_thr  | 49.7  | 49.8  | 49.8   | 49.8  | 50.0  |
| 20 KB  | nat_coop | 199.9 | 200.0 | 200.0  | 200.1 | 233.4 |
| 20 KB  | nat_thr  | 183.1 | 183.2 | 199.8  | 199.8 | 200.0 |
| 400 KB | c3_coop  | 300.0 | 300.1 | 300.1  | 300.2 | 333.3 |
| 400 KB | c3_thr   | 282.7 | 283.0 | 299.6  | 299.7 | 349.7 |
| 400 KB | c3s_coop | 51.1  | 51.1  | 51.1   | 51.2  | 183.4 |
| 400 KB | c3s_thr  | 48.7  | 65.3  | 65.4   | 65.4  | 116.5 |
| 400 KB | nat_coop | 333.3 | 333.4 | 333.4  | 333.4 | 433.3 |
| 400 KB | nat_thr  | 283.1 | 299.7 | 299.8  | 299.8 | 299.9 |

## File download to disk (median of 25 runs, 60 fps)
Target: https://api.chriskumm.com/api/benchmark/download/{byte_count}/
Measures throughput for downloading bodies of increasing size to disk.

| Body size | nat_coop | c3_coop | c3s_coop | nat_thr | c3_thr | c3s_thr |
| --------- | -------- | ------- | -------- | ------- | ------ | ------- |
| 1 MB      | 500.1    | 334.0   | 67.6     | 333.1   | 332.5  | 65.6    |
| 8 MB      | 2366.7   | 486.5   | 150.5    | 549.8   | 466.4  | 164.2   |
| 32 MB     | 8799.7   | 984.4   | 534.8    | 1334.6  | 948.5  | 561.5   |

| Label | Trial    | Min    | Q1     | Median | Q3     | Max    |
| ----- | -------- | ------ | ------ | ------ | ------ | ------ |
| 1 MB  | c3_coop  | 333.6  | 333.8  | 334.0  | 334.1  | 362.7  |
| 1 MB  | c3_thr   | 332.2  | 332.4  | 332.5  | 332.7  | 349.0  |
| 1 MB  | c3s_coop | 53.6   | 67.6   | 67.6   | 67.6   | 100.1  |
| 1 MB  | c3s_thr  | 46.2   | 65.5   | 65.6   | 65.6   | 66.4   |
| 1 MB  | nat_coop | 483.5  | 500.0  | 500.1  | 500.1  | 533.5  |
| 1 MB  | nat_thr  | 316.6  | 333.1  | 333.1  | 333.2  | 349.9  |
| 8 MB  | c3_coop  | 469.2  | 470.0  | 486.5  | 550.4  | 1196.5 |
| 8 MB  | c3_thr   | 448.5  | 463.4  | 466.4  | 497.1  | 966.2  |
| 8 MB  | c3s_coop | 134.7  | 135.5  | 150.5  | 184.2  | 1002.7 |
| 8 MB  | c3s_thr  | 130.8  | 132.5  | 164.2  | 197.6  | 847.4  |
| 8 MB  | nat_coop | 2366.4 | 2366.7 | 2366.7 | 2368.9 | 2969.9 |
| 8 MB  | nat_thr  | 533.0  | 549.7  | 549.8  | 551.1  | 599.8  |
| 32 MB | c3_coop  | 870.7  | 918.4  | 984.4  | 1036.5 | 1472.8 |
| 32 MB | c3_thr   | 847.3  | 910.5  | 948.5  | 1030.7 | 1646.2 |
| 32 MB | c3s_coop | 471.4  | 501.0  | 534.8  | 571.2  | 700.1  |
| 32 MB | c3s_thr  | 478.2  | 516.4  | 561.5  | 596.0  | 1047.7 |
| 32 MB | nat_coop | 8783.1 | 8783.2 | 8799.7 | 9045.0 | 9425.2 |
| 32 MB | nat_thr  | 1266.4 | 1333.0 | 1334.6 | 1356.8 | 2098.5 |
